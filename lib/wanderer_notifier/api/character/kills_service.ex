defmodule WandererNotifier.Api.Character.KillsService do
  @moduledoc """
  Service for fetching and processing character kills from ESI.
  """

  # Maximum number of kills to fetch in a single operation
  @max_kills 100

  alias WandererNotifier.Api.ESI.Service, as: ESIService
  alias WandererNotifier.Api.ZKill.Client, as: ZKillClient
  alias WandererNotifier.Core.Stats
  alias WandererNotifier.Data.Cache.Helpers, as: CacheHelpers
  alias WandererNotifier.Data.Cache.Repository, as: CacheRepo
  alias WandererNotifier.Data.Repository
  alias WandererNotifier.KillmailProcessing.Context
  alias WandererNotifier.KillmailProcessing.Pipeline, as: KillmailPipeline
  alias WandererNotifier.Logger.Logger, as: AppLogger
  alias WandererNotifier.Resources.KillmailPersistence

  # Default implementations
  @default_deps %{
    logger: AppLogger,
    repository: Repository,
    esi_service: ESIService,
    persistence: KillmailPersistence,
    zkill_client: ZKillClient,
    cache_helpers: CacheHelpers
  }

  # A special character ID to enable debug logs
  @debug_character_id 640_170_087

  # Debug logging helper
  defp debug_log(character_id, message, metadata \\ %{}) do
    if character_id == @debug_character_id do
      AppLogger.kill_info(
        "[DEBUG_KILLS] #{message}",
        Map.put(metadata, :character_id, character_id)
      )
    end
  end

  # Helper to consistently resolve a character's name by checking:
  # 1. any known/tracked name from an input argument (if available),
  # 2. the repository,
  # 3. ESI, and
  # 4. caching the result if found via ESI.
  #
  # Raises if it cannot resolve the name at all.
  defp resolve_character_name(character_id, maybe_tracked_name, deps)
       when is_binary(maybe_tracked_name) do
    if valid_name?(maybe_tracked_name),
      do: maybe_tracked_name,
      else: resolve_from_sources(character_id, deps)
  end

  defp resolve_character_name(character_id, _maybe_tracked_name, deps),
    do: resolve_from_sources(character_id, deps)

  defp valid_name?(name), do: name != "" and name != "Unknown"

  defp resolve_from_sources(character_id, deps) do
    case try_repository_lookup(character_id, deps) do
      {:ok, name} -> name
      {:error, repo_error} -> try_esi_lookup(character_id, deps, repo_error)
    end
  end

  defp try_repository_lookup(character_id, deps) do
    case deps.repository.get_character_name(character_id) do
      {:ok, name} when is_binary(name) and name not in ["", "Unknown"] ->
        AppLogger.kill_debug("[RESOLVE_NAME] Found character name in repository", %{
          character_id: character_id,
          character_name: name
        })

        {:ok, name}

      error ->
        {:error, error}
    end
  end

  defp try_esi_lookup(character_id, deps, repo_error) do
    AppLogger.kill_warn("[RESOLVE_NAME] Repository lookup failed", %{
      character_id: character_id,
      repo_error: inspect(repo_error)
    })

    case deps.esi_service.get_character(character_id) do
      {:ok, %{"name" => name}} when is_binary(name) and name != "" ->
        cache_and_return_name(character_id, name, deps)

      esi_error ->
        log_resolution_failure(character_id, repo_error, esi_error)
        raise "Failed to resolve character name for ID #{character_id}"
    end
  end

  defp cache_and_return_name(character_id, name, deps) do
    deps.cache_helpers.cache_character_info(%{
      "character_id" => character_id,
      "name" => name
    })

    name
  end

  defp log_resolution_failure(character_id, repo_error, esi_error) do
    AppLogger.kill_error(
      "[RESOLVE_NAME] Failed to resolve character name via ESI and repository",
      %{
        character_id: character_id,
        repo_error: inspect(repo_error),
        esi_error: inspect(esi_error)
      }
    )
  end

  # Helper for processing kills with error handling
  defp process_kills_with_logging(kills, transform_fn, character_id) do
    debug_log(character_id, "Processing #{length(kills)} kills")

    transformed_kills = Enum.map(kills, transform_fn)

    case Enum.find(transformed_kills, &match?({:error, _}, &1)) do
      nil ->
        successful_kills = Enum.map(transformed_kills, fn {:ok, kill} -> kill end)

        debug_log(character_id, "Successfully processed all kills",
          processed_count: length(successful_kills),
          sample_kill: List.first(successful_kills)
        )

        {:ok, successful_kills}

      {:error, reason} ->
        debug_log(character_id, "Error processing kills", error: inspect(reason))
        {:error, reason}
    end
  end

  @type date_range :: %{start: DateTime.t() | nil, end: DateTime.t() | nil}
  @type batch_stats :: %{
          total: non_neg_integer(),
          processed: non_neg_integer(),
          skipped: non_neg_integer(),
          duplicates: non_neg_integer(),
          errors: non_neg_integer(),
          duration_ms: non_neg_integer()
        }

  @doc """
  Processes historical killmails for a character within a date range.

  ## Parameters
    - character_id: The character ID to process kills for
    - character_name: The character name for logging
    - date_range: Map with :start and :end DateTime
    - opts: Additional options for processing
      - :concurrency - Number of concurrent processes (default: 5)
      - :skip_notification - Whether to skip notifications (default: true)

  ## Returns
    - {:ok, batch_stats} on success
    - {:error, reason} on failure
  """
  @spec process_historical_kills(pos_integer(), String.t(), date_range(), keyword()) ::
          {:ok, batch_stats()} | {:error, term()}
  def process_historical_kills(character_id, character_name, date_range, opts \\ []) do
    start_time = System.monotonic_time()
    batch_id = generate_batch_id()

    AppLogger.kill_info("Starting historical kill processing", %{
      character_id: character_id,
      character_name: character_name,
      date_range: date_range,
      batch_id: batch_id
    })

    # Create processing context with default options
    ctx =
      Context.new_historical(
        character_id,
        character_name,
        :zkill_api,
        batch_id,
        Keyword.merge([concurrency: 5, skip_notification: true], opts)
      )

    # Fetch kills from ZKill
    with {:ok, kills} <- fetch_kills(character_id, date_range) do
      stats = process_kills_batch(kills, ctx)

      duration =
        System.convert_time_unit(System.monotonic_time() - start_time, :native, :millisecond)

      AppLogger.kill_info("Completed historical kill processing", %{
        character_id: character_id,
        character_name: character_name,
        batch_id: batch_id,
        total_kills: stats.total,
        processed: stats.processed,
        skipped: stats.skipped,
        duplicates: stats.duplicates,
        errors: stats.errors,
        duration_ms: duration
      })

      {:ok, Map.put(stats, :duration_ms, duration)}
    end
  end

  @doc """
  Gets kills for a character within a date range.

  ## Options
    * `:from` - Start date for filtering kills (inclusive). If not specified, no lower bound is applied.
    * `:to` - End date for filtering kills (inclusive). If not specified, no upper bound is applied.

  ## Examples
      # Get all kills
      get_kills_for_character(123456)

      # Get kills from a specific date onwards
      get_kills_for_character(123456, from: ~D[2024-03-01])

      # Get kills within a date range
      get_kills_for_character(123456, from: ~D[2024-03-01], to: ~D[2024-03-31])
  """
  @spec get_kills_for_character(integer(), Keyword.t(), map()) ::
          {:ok, list(map())} | {:error, term()}
  def get_kills_for_character(character_id, opts \\ [], deps \\ @default_deps) do
    debug_log(character_id, "Starting kill fetch with options",
      date_range: %{from: opts[:from], to: opts[:to]}
    )

    case fetch_character_kills(character_id, 25, 1, deps) do
      {:ok, kills} ->
        filtered_kills = filter_kills_by_date(kills, opts[:from], opts[:to])

        debug_log(character_id, "Filtered kills by date",
          total_kills: length(kills),
          filtered_kills: length(filtered_kills),
          date_range: %{from: opts[:from], to: opts[:to]}
        )

        process_kills_with_logging(filtered_kills, &transform_kill(&1, deps), character_id)

      {:error, reason} ->
        debug_log(character_id, "Failed to fetch kills", error: inspect(reason))
        {:error, :api_error}
    end
  end

  @doc """
  Fetches and persists kills for all tracked characters.
  """
  @spec fetch_and_persist_all_tracked_character_kills(integer(), integer(), map()) ::
          {:ok, %{processed: integer(), persisted: integer(), characters: integer()}}
          | {:error, term()}
  def fetch_and_persist_all_tracked_character_kills(limit \\ 25, page \\ 1, deps \\ @default_deps) do
    AppLogger.kill_info("[CHARACTER_KILLS] Starting batch kill fetch for all tracked characters",
      limit: limit,
      page: page
    )

    tracked_characters = deps.repository.get_tracked_characters()

    if Enum.empty?(tracked_characters) do
      AppLogger.kill_warn("[CHARACTER_KILLS] No tracked characters found")
      {:error, :no_tracked_characters}
    else
      log_tracked_characters_info(tracked_characters)
      process_tracked_characters_batch(tracked_characters, deps)
    end
  end

  defp log_tracked_characters_info(tracked_characters) do
    debug_char = Enum.find(tracked_characters, &(&1.character_id == @debug_character_id))

    if debug_char do
      AppLogger.kill_info("[DEBUG_KILLS] Debug character found in tracked characters",
        character: debug_char
      )
    else
      AppLogger.kill_warn("[DEBUG_KILLS] Debug character not found in tracked characters",
        character_id: @debug_character_id,
        tracked_count: length(tracked_characters),
        sample_tracked: List.first(tracked_characters)
      )
    end

    AppLogger.kill_info("[CHARACTER_KILLS] Found tracked characters", %{
      character_count: length(tracked_characters),
      sample_characters:
        Enum.take(tracked_characters, 3)
        |> Enum.map(&Map.take(&1, [:character_id, :character_name]))
    })
  end

  @doc """
  Process tracked characters' kills in batches.
  """
  def process_tracked_characters_batch(characters, _opts \\ []) do
    character_count = length(characters)
    AppLogger.kill_info("👥 Processing #{character_count} tracked characters")

    character_ids = Enum.map(characters, & &1["character_id"])

    results =
      character_ids
      |> Task.async_stream(
        fn character_id ->
          process_character_kills(character_id, skip_notification: true)
        end,
        max_concurrency: 5,
        timeout: 60_000,
        on_timeout: :exit
      )
      |> Enum.reduce({0, 0, []}, fn
        {:ok, {:ok, %{processed: p, persisted: s}}}, {total_proc, total_succ, errs} ->
          {total_proc + p, total_succ + s, errs}

        {:ok, {:error, reason}}, {total_proc, total_succ, errs} ->
          {total_proc, total_succ, [reason | errs]}

        {:exit, reason}, {total_proc, total_succ, errs} ->
          {total_proc, total_succ, [reason | errs]}
      end)

    {processed, succeeded, errors} = results

    if errors != [] do
      AppLogger.kill_warn("⚠️ Some characters failed processing", %{
        processed: processed,
        succeeded: succeeded,
        sample_errors: Enum.take(errors, 3)
      })
    else
      AppLogger.kill_info("✅ All characters processed successfully", %{
        processed: processed,
        succeeded: succeeded
      })
    end

    {:ok, %{processed: processed, persisted: succeeded}}
  end

  @doc """
  Fetches and persists kills for a single character.
  """
  @spec fetch_and_persist_character_kills(integer(), String.t(), map()) ::
          {:ok, %{processed: integer(), persisted: integer()}}
          | {:error, term()}
  def fetch_and_persist_character_kills(character_id, character_name, ctx) do
    if character_tracked?(character_id, @default_deps) do
      case fetch_character_kills(character_id, 25, 1, @default_deps) do
        {:ok, kills} -> process_character_kills_result(kills, character_id, character_name, ctx)
        {:error, reason} -> handle_fetch_error(reason, character_id, character_name)
      end
    else
      handle_untracked_character(character_id)
    end
  end

  defp process_character_kills_result(kills, character_id, character_name, ctx) do
    case process_kills_batch(kills, ctx) do
      {:ok, stats} -> {:ok, Map.put(stats, :character_name, character_name)}
      {:error, reason} -> handle_process_error(reason, character_id, character_name)
    end
  end

  defp handle_fetch_error(reason, character_id, character_name) do
    AppLogger.kill_error("[CHARACTER_KILLS] Failed to fetch kills", %{
      character_id: character_id,
      character_name: character_name,
      error: inspect(reason)
    })

    {:error, reason}
  end

  defp handle_process_error(reason, character_id, character_name) do
    AppLogger.kill_error("[CHARACTER_KILLS] Failed to process kills", %{
      character_id: character_id,
      character_name: character_name,
      error: inspect(reason)
    })

    {:error, reason}
  end

  defp handle_untracked_character(character_id) do
    AppLogger.kill_info("[CHARACTER_KILLS] Skipping untracked character", %{
      character_id: character_id
    })

    {:ok, %{total: 0, processed: 0, skipped: 1, duplicates: 0, errors: 0}}
  end

  defp character_tracked?(character_id, deps) do
    tracked_characters = deps.repository.get_tracked_characters()

    Enum.any?(tracked_characters, fn char ->
      char_id =
        if is_map(char) do
          Map.get(char, :character_id) || Map.get(char, "character_id")
        else
          nil
        end

      to_string(char_id) == to_string(character_id)
    end)
  end

  defp process_kills_batch(kills, character_id) when is_integer(character_id) do
    character_name = resolve_character_name(character_id, nil, @default_deps)

    ctx =
      Context.new_historical(
        character_id,
        character_name,
        :zkill_api,
        generate_batch_id(),
        []
      )

    process_kills_batch(kills, ctx)
  end

  defp process_kills_batch(kills, %Context{} = ctx) do
    start_time = System.monotonic_time()
    concurrency = ctx.options[:concurrency] || 2

    known_kill_ids =
      KillmailPersistence.get_already_processed_kill_ids(ctx.character_id)

    AppLogger.kill_debug("[KillsService] Filtering already processed kills", %{
      total_kills: length(kills),
      already_processed: MapSet.size(known_kill_ids),
      character_id: ctx.character_id
    })

    filtered_kills =
      Enum.reject(kills, fn kill ->
        kill_id = extract_killmail_id(kill)
        kill_id_int = parse_kill_id(kill_id)
        kill_id_int && MapSet.member?(known_kill_ids, kill_id_int)
      end)

    AppLogger.kill_info("[KillsService] Processing new kills", %{
      total_kills: length(kills),
      new_kills: length(filtered_kills),
      skipped_kills: length(kills) - length(filtered_kills),
      character_id: ctx.character_id
    })

    stats = %{
      total: length(filtered_kills),
      processed: 0,
      skipped: 0,
      duplicates: 0,
      errors: 0,
      duration: 0
    }

    result =
      filtered_kills
      |> Task.async_stream(
        fn kill ->
          process_single_kill(kill, ctx)
        end,
        max_concurrency: concurrency,
        timeout: 120_000,
        on_timeout: :kill_task
      )
      |> Enum.reduce(stats, fn
        {:ok, {:ok, :skipped}}, acc ->
          %{acc | skipped: acc.skipped + 1}

        {:ok, {:ok, :processed}}, acc ->
          %{acc | processed: acc.processed + 1}

        {:ok, :processed}, acc ->
          %{acc | processed: acc.processed + 1}

        {:ok, {:ok, _}}, acc ->
          %{acc | processed: acc.processed + 1}

        {:ok, {:error, :duplicate}}, acc ->
          %{acc | duplicates: acc.duplicates + 1}

        {:ok, {:error, _}}, acc ->
          %{acc | errors: acc.errors + 1}

        {:error, :timeout}, acc ->
          AppLogger.kill_error("[KILLS] Kill processing timeout", %{
            character_id: ctx.character_id,
            character_name: ctx.character_name,
            batch_id: ctx.batch_id
          })

          %{acc | errors: acc.errors + 1}

        {:error, error}, acc ->
          AppLogger.kill_error("[KILLS] Batch processing error", %{
            character_id: ctx.character_id,
            character_name: ctx.character_name,
            batch_id: ctx.batch_id,
            error: inspect(error)
          })

          %{acc | errors: acc.errors + 1}
      end)
      |> Map.put(:duration, System.monotonic_time() - start_time)
      |> then(fn stats ->
        duration_seconds = System.convert_time_unit(stats.duration, :native, :second)
        success_rate = if stats.total > 0, do: stats.processed / stats.total * 100, else: 0.0
        error_rate = if stats.total > 0, do: stats.errors / stats.total * 100, else: 0.0
        duplicate_rate = if stats.total > 0, do: stats.duplicates / stats.total * 100, else: 0.0

        AppLogger.kill_info("[KILLS] Batch processing complete", %{
          character_id: ctx.character_id,
          character_name: ctx.character_name,
          batch_id: ctx.batch_id,
          total_kills: stats.total,
          processed: stats.processed,
          skipped: stats.skipped,
          duplicates: stats.duplicates,
          errors: stats.errors,
          duration_seconds: duration_seconds,
          success_rate: success_rate,
          error_rate: error_rate,
          duplicate_rate: duplicate_rate
        })

        Stats.print_summary()
        stats
      end)

    {:ok, result}
  end

  defp process_single_kill(kill, ctx) do
    kill_id = extract_killmail_id(kill)

    AppLogger.kill_debug("[KillsService] Processing single kill", %{
      kill_id: kill_id,
      character_id: ctx.character_id,
      character_name: ctx.character_name,
      context_mode: ctx.mode && ctx.mode.mode
    })

    # First attempt - standard processing with new normalized model
    case process_killmail_with_retries(kill, ctx, 0) do
      {:ok, _} = _result ->
        AppLogger.kill_debug("[KillsService] Successfully processed kill", %{
          kill_id: kill_id
        })

        :processed

      {:error, {:enrichment_validation_failed, reasons}} = error ->
        # Log the specific reasons for enrichment failure
        AppLogger.kill_warn("[KillsService] Enrichment validation failed - attempting retry", %{
          kill_id: kill_id,
          character_id: ctx.character_id,
          reasons: inspect(reasons)
        })

        # Retry with pre-enrichment
        case pre_enrich_and_process(kill, ctx, reasons) do
          {:ok, _} = _result ->
            AppLogger.kill_info("[KillsService] Retry with pre-enrichment succeeded", %{
              kill_id: kill_id
            })

            :processed

          retry_error ->
            AppLogger.kill_error("[KillsService] Retry with pre-enrichment failed", %{
              kill_id: kill_id,
              character_id: ctx.character_id,
              error: inspect(retry_error)
            })

            error
        end

      error ->
        AppLogger.kill_error("[KillsService] Pipeline processing failed", %{
          kill_id: kill_id,
          character_id: ctx.character_id,
          error: inspect(error)
        })

        error
    end
  end

  # Attempt the killmail processing with retries for transient failures
  defp process_killmail_with_retries(kill, ctx, retry_count, max_retries \\ 2) do
    kill_id = extract_killmail_id(kill)

    if retry_count > 0 do
      AppLogger.kill_info("[KillsService] Retry attempt #{retry_count} for kill #{kill_id}")
    end

    case KillmailPipeline.process_killmail(kill, ctx) do
      {:ok, _} = result ->
        result

      {:error, {:enrichment_validation_failed, _}} = error when retry_count >= max_retries ->
        # Reached max retries for enrichment failures
        error

      {:error, {:enrichment_validation_failed, reasons}} ->
        # Only retry for system name validation errors
        retry_for_validation_error? =
          Enum.any?(reasons, fn reason ->
            String.contains?(reason, "system name") ||
              String.contains?(reason, "Solar system name")
          end)

        if retry_for_validation_error? do
          # Add an exponential backoff delay
          backoff_ms = (:math.pow(2, retry_count) * 500) |> round()
          :timer.sleep(backoff_ms)

          # Retry the process
          process_killmail_with_retries(kill, ctx, retry_count + 1)
        else
          # Not a retriable validation error
          {:error, {:enrichment_validation_failed, reasons}}
        end

      error ->
        # Other errors are not retried
        error
    end
  end

  # Pre-enrich the killmail data with critical fields before processing
  defp pre_enrich_and_process(kill, ctx, reasons) do
    kill_id = extract_killmail_id(kill)

    # Extract the solar system ID to pre-fetch system name
    system_id = Map.get(kill, "solar_system_id")

    AppLogger.kill_info("[KillsService] Pre-enriching kill data", %{
      kill_id: kill_id,
      system_id: system_id
    })

    # Pre-fetch the system name if that's an issue - this is the only validation we still need
    enriched_kill =
      if system_id && Enum.any?(reasons, &String.contains?(&1, "system name")) do
        case get_system_name_with_cache(system_id) do
          {:ok, system_name} ->
            AppLogger.kill_info("[KillsService] Pre-enriched system name", %{
              kill_id: kill_id,
              system_id: system_id,
              system_name: system_name
            })

            Map.put(kill, "solar_system_name", system_name)

          _error ->
            kill
        end
      else
        kill
      end

    # Process the pre-enriched killmail with a fresh attempt
    process_killmail_with_retries(enriched_kill, ctx, 0)
  end

  defp extract_killmail_id(kill) when is_map(kill) do
    cond do
      Map.has_key?(kill, "killmail_id") -> kill["killmail_id"]
      Map.has_key?(kill, :killmail_id) -> kill.killmail_id
      true -> "unknown"
    end
  end

  defp extract_killmail_id(_), do: "unknown"

  defp fetch_character_kills(character_id, _limit, _page, deps) do
    Process.put(:current_character_id, character_id)

    case deps.zkill_client.get_character_kills(character_id, %{start: nil, end: nil}, @max_kills) do
      {:ok, kills} = result when is_list(kills) ->
        if length(kills) > 0 do
          AppLogger.kill_debug("📥 Retrieved #{length(kills)} kills", %{
            character_id: character_id
          })
        end

        result

      result ->
        result
    end
  end

  # Improved date filter that gracefully handles nil `from` and `to`
  defp filter_kills_by_date(kills, from, to) do
    Enum.filter(kills, fn kill ->
      case DateTime.from_iso8601(kill["killmail_time"]) do
        {:ok, kill_time, _offset} ->
          kill_date = DateTime.to_date(kill_time)

          no_lower_bound = is_nil(from) or Date.compare(kill_date, from) != :lt
          no_upper_bound = is_nil(to) or Date.compare(kill_date, to) != :gt

          no_lower_bound and no_upper_bound

        _ ->
          false
      end
    end)
  end

  defp transform_kill(kill, deps) do
    kill_id = kill["killmail_id"]

    AppLogger.kill_debug("[KillsService] Transforming kill", %{
      kill_id: kill_id,
      victim_id: get_in(kill, ["victim", "character_id"]),
      ship_id: get_in(kill, ["victim", "ship_type_id"])
    })

    with victim_id when is_integer(victim_id) <- get_in(kill, ["victim", "character_id"]),
         ship_id when is_integer(ship_id) <- get_in(kill, ["victim", "ship_type_id"]),
         {:ok, victim} <- deps.esi_service.get_character(victim_id),
         {:ok, ship} <- deps.esi_service.get_type(ship_id) do
      AppLogger.kill_debug("[KillsService] Successfully retrieved victim and ship data", %{
        kill_id: kill_id,
        victim_id: victim_id,
        victim_name: victim["name"],
        ship_id: ship_id,
        ship_name: ship["name"]
      })

      {:ok,
       %{
         id: kill["killmail_id"],
         time: kill["killmail_time"],
         victim_name: victim["name"],
         ship_name: ship["name"],
         victim_id: victim_id,
         ship_id: ship_id
       }}
    else
      {:error, reason} ->
        AppLogger.kill_error("[CHARACTER_KILLS] Failed to enrich kill", %{
          kill_id: kill_id,
          error: inspect(reason),
          victim_id: get_in(kill, ["victim", "character_id"]),
          ship_id: get_in(kill, ["victim", "ship_type_id"])
        })

        {:error, :api_error}

      nil ->
        # This could happen if either victim_id or ship_id is not integer
        AppLogger.kill_error("[CHARACTER_KILLS] Failed to extract victim/ship ID", %{
          kill_id: kill_id,
          raw_data_sample: inspect(kill, limit: 200)
        })

        {:error, :invalid_kill_data}

      _ ->
        # Any other unexpected pattern
        AppLogger.kill_error("[CHARACTER_KILLS] Unexpected data in kill", %{
          kill_id: kill_id,
          raw_data_sample: inspect(kill, limit: 200)
        })

        {:error, :invalid_kill_data}
    end
  end

  @doc """
  Fetches and processes kills for a character.

  ## Parameters
    - character_id: The character ID to fetch kills for
    - opts: Additional options (e.g., skip_notification: true)

  ## Returns
    - {:ok, processed_kills} on success
    - {:error, reason} on failure
  """
  def process_character_kills(character_id, _opts \\ []) do
    start_time = System.monotonic_time()

    character_name =
      case Repository.get_character_name(character_id) do
        {:ok, name} -> name
        _ -> "Unknown"
      end

    AppLogger.kill_info("👥 Processing character", %{
      character_id: character_id,
      character_name: character_name
    })

    case fetch_kills(character_id, %{start: nil, end: nil}) do
      {:ok, kills} ->
        total_kills = length(kills)

        AppLogger.kill_info("📥 Retrieved kills for processing", %{
          character_id: character_id,
          character_name: character_name,
          total_kills: total_kills,
          sample_kill:
            if total_kills > 0 do
              %{
                id: List.first(kills)["killmail_id"],
                time: List.first(kills)["killmail_time"]
              }
            else
              nil
            end
        })

        {:ok, stats} = process_kills_batch(kills, character_id)
        end_time = System.monotonic_time()
        processing_time = System.convert_time_unit(end_time - start_time, :native, :millisecond)

        AppLogger.kill_info("📊 Batch processing metrics", %{
          character_id: character_id,
          character_name: character_name,
          total_kills: total_kills,
          processed_kills: stats.processed,
          success_rate: "#{Float.round(stats.processed / max(total_kills, 1) * 100, 2)}%",
          processing_time_ms: processing_time,
          average_time_per_kill: Float.round(processing_time / max(total_kills, 1), 2)
        })

        if stats.errors > 0 do
          {:error, :batch_processing_failed}
        else
          {:ok, stats}
        end

      {:error, reason} ->
        AppLogger.kill_error("❌ Failed to fetch kills", %{
          character_id: character_id,
          character_name: character_name,
          error: inspect(reason)
        })

        {:error, reason}
    end
  end

  @spec fetch_kills(pos_integer(), date_range()) :: {:ok, list(map())} | {:error, term()}
  defp fetch_kills(character_id, date_range) do
    debug_log(character_id, "Fetching kills from ZKill", %{
      date_range: date_range,
      limit: @max_kills
    })

    case ZKillClient.get_character_kills(character_id, date_range, @max_kills) do
      {:ok, kills} ->
        debug_log(character_id, "Retrieved #{length(kills)} kills", %{
          date_range: date_range,
          limit: @max_kills
        })

        {:ok, kills}

      error ->
        debug_log(character_id, "Failed to fetch kills", %{
          error: inspect(error),
          date_range: date_range,
          limit: @max_kills
        })

        error
    end
  end

  defp generate_batch_id do
    :crypto.strong_rand_bytes(16)
    |> Base.encode16()
    |> String.downcase()
  end

  defp parse_kill_id(kill_id) when is_integer(kill_id), do: kill_id

  defp parse_kill_id(kill_id) when is_binary(kill_id) do
    case Integer.parse(kill_id) do
      {id, _} -> id
      :error -> nil
    end
  end

  defp parse_kill_id(_), do: nil

  # Get ship type name from cache or from ESI with caching
  def get_ship_type_name_with_cache(ship_type_id) do
    alias WandererNotifier.Api.ESI.Service, as: ESIService
    alias WandererNotifier.Data.Cache.Keys, as: CacheKeys
    alias WandererNotifier.Data.Cache.Repository, as: CacheRepo

    cache_key = CacheKeys.ship_info(ship_type_id)

    # Try from cache first
    case CacheRepo.get(cache_key) do
      %{"name" => name} when is_binary(name) and name != "" ->
        AppLogger.kill_debug("[KillsService] Found ship name in cache", %{
          ship_type_id: ship_type_id,
          name: name
        })

        {:ok, name}

      _ ->
        fetch_and_cache_ship_name(ship_type_id, cache_key)
    end
  end

  defp fetch_and_cache_ship_name(ship_type_id, cache_key) do
    case ESIService.get_ship_type_name(ship_type_id) do
      {:ok, ship_info} ->
        name = Map.get(ship_info, "name")

        if is_binary(name) && name != "" do
          # Cache for 30 days (ship types don't change)
          CacheRepo.set(cache_key, ship_info, 30 * 86_400)

          AppLogger.kill_debug("[KillsService] Retrieved and cached ship name", %{
            ship_type_id: ship_type_id,
            name: name
          })

          {:ok, name}
        else
          {:error, :invalid_ship_data}
        end

      error ->
        AppLogger.kill_error("[KillsService] Failed to get ship name", %{
          ship_type_id: ship_type_id,
          error: inspect(error)
        })

        error
    end
  end

  # Get system name from cache or from ESI with caching
  defp get_system_name_with_cache(system_id) do
    cache_key = "system_info:#{system_id}"

    case CacheRepo.get(cache_key) do
      {:ok, system_info} when is_map(system_info) ->
        name = Map.get(system_info, "name")
        {:ok, name}

      _ ->
        fetch_and_cache_system_name(system_id, cache_key)
    end
  end

  defp fetch_and_cache_system_name(system_id, cache_key) do
    case ESIService.get_system_info(system_id) do
      {:ok, system_info} -> handle_system_info_response(system_info, system_id, cache_key)
      error -> handle_system_info_error(error, system_id)
    end
  end

  defp handle_system_info_response(system_info, system_id, cache_key) do
    name = Map.get(system_info, "name")

    if is_binary(name) && name != "" do
      # Cache for 30 days (system names don't change)
      CacheRepo.set(cache_key, system_info, 30 * 86_400)

      AppLogger.kill_debug("[KillsService] Retrieved and cached system name", %{
        system_id: system_id,
        name: name
      })

      {:ok, name}
    else
      {:error, :invalid_system_data}
    end
  end

  defp handle_system_info_error(error, system_id) do
    AppLogger.kill_error("[KillsService] Failed to get system name", %{
      system_id: system_id,
      error: inspect(error)
    })

    error
  end
end
