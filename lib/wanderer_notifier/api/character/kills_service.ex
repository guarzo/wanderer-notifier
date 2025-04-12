defmodule WandererNotifier.Api.Character.KillsService do
  @moduledoc """
  Service for fetching and processing character kills from ESI.
  """

  # Maximum number of kills to fetch in a single operation
  @max_kills 100

  alias WandererNotifier.Api.ESI.Service, as: ESIService
  alias WandererNotifier.Api.ZKill.Client, as: ZKillClient
  alias WandererNotifier.Data.Cache.Helpers, as: CacheHelpers
  alias WandererNotifier.Data.Cache.Repository, as: CacheRepo
  alias WandererNotifier.Data.Repository
  alias WandererNotifier.KillmailProcessing.Context
  alias WandererNotifier.Processing.Killmail.KillmailProcessor
  alias WandererNotifier.Logger.Logger, as: AppLogger
  alias WandererNotifier.Processing.Killmail.Persistence
  alias WandererNotifier.Data.Repository

  # Default implementations
  @default_deps %{
    logger: AppLogger,
    repository: Repository,
    esi_service: ESIService,
    persistence: Persistence,
    zkill_client: ZKillClient,
    cache_helpers: CacheHelpers
  }

  # A special character ID to enable debug logs
  @debug_character_id 640_170_087

  # Debug logging helper
  defp debug_log(character_id, message, metadata \\ %{}) do
    if character_id == @debug_character_id do
      AppLogger.kill_debug(
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
    deps.cache_helpers.cache_character_debug(%{
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

    AppLogger.kill_debug("Starting historical kill processing", %{
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

      AppLogger.kill_debug("Completed historical kill processing", %{
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
    AppLogger.kill_debug("[CHARACTER_KILLS] Starting batch kill fetch for all tracked characters",
      limit: limit,
      page: page
    )

    tracked_characters = deps.repository.get_tracked_characters()

    if Enum.empty?(tracked_characters) do
      AppLogger.kill_warn("[CHARACTER_KILLS] No tracked characters found")
      {:error, :no_tracked_characters}
    else
      log_tracked_characters_debug(tracked_characters)
      process_tracked_characters_batch(tracked_characters, deps)
    end
  end

  defp log_tracked_characters_debug(tracked_characters) do
    debug_char = Enum.find(tracked_characters, &(&1.character_id == @debug_character_id))

    if debug_char do
      AppLogger.kill_debug("[DEBUG_KILLS] Debug character found in tracked characters",
        character: debug_char
      )
    else
      AppLogger.kill_warn("[DEBUG_KILLS] Debug character not found in tracked characters",
        character_id: @debug_character_id,
        tracked_count: length(tracked_characters),
        sample_tracked: List.first(tracked_characters)
      )
    end

    AppLogger.kill_debug("[CHARACTER_KILLS] Found tracked characters", %{
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
    AppLogger.kill_debug("👥 Processing #{character_count} tracked characters")

    # Add timestamp for performance tracking
    start_time = System.monotonic_time(:millisecond)
    AppLogger.kill_debug("[TIMING] Starting batch processing at #{start_time}")

    # Extract character IDs and ensure they are properly formatted
    character_ids =
      Enum.map(characters, fn char ->
        cond do
          # For map with atom keys
          is_map(char) && Map.has_key?(char, :character_id) ->
            char.character_id

          # For map with string keys
          is_map(char) && Map.has_key?(char, "character_id") ->
            char["character_id"]

          # For any other structure, try to get a value that might be a character ID
          true ->
            AppLogger.kill_warn("Unexpected character data structure", %{
              character: inspect(char, limit: 100)
            })

            # Return some sensible value or nil
            nil
        end
      end)
      # Filter out nil values
      |> Enum.reject(&is_nil/1)

    AppLogger.kill_debug("Extracted character IDs for processing", %{
      original_count: character_count,
      extracted_count: length(character_ids),
      sample_ids: Enum.take(character_ids, 3)
    })

    results =
      character_ids
      |> Task.async_stream(
        fn character_id ->
          # Add timestamp for tracking individual character processing
          char_start_time = System.monotonic_time(:millisecond)

          AppLogger.kill_debug(
            "[TIMING] Starting processing for character #{character_id} at #{char_start_time}"
          )

          # Wrap each character process in a try/rescue to prevent one failure from breaking all
          try do
            result = process_character_kills(character_id, skip_notification: true)

            # Log completion time
            char_end_time = System.monotonic_time(:millisecond)
            duration = char_end_time - char_start_time

            AppLogger.kill_debug(
              "[TIMING] Completed processing for character #{character_id} in #{duration}ms"
            )

            result
          rescue
            e ->
              stacktrace = __STACKTRACE__

              AppLogger.kill_error("Character processing failed with exception", %{
                character_id: character_id,
                error: Exception.message(e),
                stacktrace: Exception.format_stacktrace(stacktrace)
              })

              {:error, {:exception, Exception.message(e)}}
          catch
            kind, reason ->
              AppLogger.kill_error("Character processing failed with #{kind}", %{
                character_id: character_id,
                kind: kind,
                reason: inspect(reason)
              })

              {:error, {:uncaught, "#{kind}: #{inspect(reason)}"}}
          end
        end,
        max_concurrency: 5,
        # 3 minutes
        timeout: 180_000,
        on_timeout: :exit
      )
      |> Enum.reduce({0, 0, []}, fn
        # Handle the case with processed/persisted fields
        {:ok, {:ok, %{processed: p, persisted: s}}}, {total_proc, total_succ, errs} ->
          {total_proc + p, total_succ + s, errs}

        # Handle the case with just a generic stats map
        {:ok, {:ok, stats}}, {total_proc, total_succ, errs} ->
          processed = Map.get(stats, :processed, 0)
          # Some stats maps might not have persisted, so default to processed
          persisted = Map.get(stats, :persisted, processed)
          {total_proc + processed, total_succ + persisted, errs}

        {:ok, {:error, reason}}, {total_proc, total_succ, errs} ->
          {total_proc, total_succ, [reason | errs]}

        {:exit, reason}, {total_proc, total_succ, errs} ->
          AppLogger.kill_error("[TIMEOUT] Character processing timed out", %{
            reason: inspect(reason)
          })

          {total_proc, total_succ, [reason | errs]}

        unexpected, acc ->
          # Log any unexpected format to help debug
          AppLogger.kill_warn("Unexpected result format in process_tracked_characters_batch", %{
            result: inspect(unexpected)
          })

          acc
      end)

    # Log total time
    end_time = System.monotonic_time(:millisecond)
    duration = end_time - start_time
    AppLogger.kill_debug("[TIMING] Completed batch processing in #{duration}ms")

    {processed, succeeded, errors} = results

    if errors != [] do
      AppLogger.kill_warn("⚠️ Some characters failed processing", %{
        processed: processed,
        succeeded: succeeded,
        sample_errors: Enum.take(errors, 3)
      })
    else
      AppLogger.kill_debug("✅ All characters processed successfully", %{
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
    AppLogger.kill_debug("[CHARACTER_KILLS] Skipping untracked character", %{
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

  # Handle string character IDs by converting to integer
  defp process_kills_batch(kills, character_id) when is_binary(character_id) do
    case Integer.parse(character_id) do
      {int_id, ""} ->
        # Successfully parsed the string to an integer
        process_kills_batch(kills, int_id)

      _ ->
        # Failed to parse the string as an integer
        AppLogger.kill_error("[KillsService] Invalid character ID format", %{
          character_id: character_id
        })

        {:error, :invalid_character_id}
    end
  end

  defp process_kills_batch(kills, %Context{} = ctx) do
    __total_kills = length(kills)
    # Get character name for better context in logs
    _character_name =
      case Repository.get_character_name(ctx.character_id) do
        {:ok, name} -> name
        _ -> "Unknown"
      end

    # Process a batch of kills
    result =
      kills
      |> Enum.reduce(%{processed: 0, skipped: 0}, fn kill, acc ->
        case process_single_kill(kill, ctx) do
          {:ok, _} -> %{acc | processed: acc.processed + 1}
          _ -> %{acc | skipped: acc.skipped + 1}
        end
      end)

    {:ok, result}
  end

  defp process_single_kill(kill, ctx) do
    kill_id = extract_killmail_id(kill)
    start_time = System.monotonic_time(:millisecond)

    # Create a standardized killmail data structure
    standardized_kill = ensure_standardized_killmail(kill)

    AppLogger.kill_debug("[KillsService] Processing single kill", %{
      kill_id: kill_id,
      character_id: ctx.character_id,
      character_name: ctx.character_name,
      context_mode: ctx.mode && ctx.mode.mode,
      processing_start: start_time
    })

    # First attempt - standard processing with new normalized model
    result =
      case KillmailProcessor.process_killmail(standardized_kill, ctx) do
        {:ok, _} = _result ->
          end_time = System.monotonic_time(:millisecond)
          duration_ms = end_time - start_time

          AppLogger.kill_debug("[KillsService] Successfully processed kill", %{
            kill_id: kill_id,
            duration_ms: duration_ms
          })

          :processed

        {:error, {:enrichment_validation_failed, reasons}} = error ->
          # Log the specific reasons for enrichment failure
          mid_time = System.monotonic_time(:millisecond)
          duration_so_far = mid_time - start_time

          AppLogger.kill_warn("[KillsService] Enrichment validation failed - attempting retry", %{
            kill_id: kill_id,
            character_id: ctx.character_id,
            reasons: inspect(reasons),
            duration_so_far_ms: duration_so_far
          })

          # Retry with pre-enrichment
          case pre_enrich_and_process(standardized_kill, ctx, reasons) do
            {:ok, _} = _result ->
              end_time = System.monotonic_time(:millisecond)
              duration_ms = end_time - start_time

              AppLogger.kill_debug("[KillsService] Retry with pre-enrichment succeeded", %{
                kill_id: kill_id,
                total_duration_ms: duration_ms
              })

              :processed

            retry_error ->
              end_time = System.monotonic_time(:millisecond)
              duration_ms = end_time - start_time

              AppLogger.kill_error("[KillsService] Retry with pre-enrichment failed", %{
                kill_id: kill_id,
                character_id: ctx.character_id,
                error: inspect(retry_error),
                total_duration_ms: duration_ms
              })

              error
          end

        error ->
          end_time = System.monotonic_time(:millisecond)
          duration_ms = end_time - start_time

          AppLogger.kill_error("[KillsService] Pipeline processing failed", %{
            kill_id: kill_id,
            character_id: ctx.character_id,
            error: inspect(error),
            duration_ms: duration_ms
          })

          error
      end

    # Return the result
    result
  end

  # Helper to ensure killmail is in standardized format
  defp ensure_standardized_killmail(kill) when is_map(kill) do
    alias WandererNotifier.KillmailProcessing.KillmailData
    alias WandererNotifier.KillmailProcessing.Transformer

    # First extract the kill_id to ensure we don't lose it
    kill_id = extract_killmail_id(kill)

    # Log the pre-transformation data with direct string interpolation
    AppLogger.kill_debug("""
    [KillsService] Pre-transformation killmail data:
    * Kill ID: #{inspect(kill_id)}
    * Is struct: #{is_struct(kill)}
    * Struct type: #{if is_struct(kill), do: kill.__struct__, else: "not a struct"}
    * Top-level keys: #{inspect(if is_map(kill), do: Map.keys(kill), else: "not a map")}
    * Has zkb data: #{if is_map(kill), do: Map.has_key?(kill, "zkb") || Map.has_key?(kill, :zkb), else: false}
    * ZKB data: #{if is_map(kill) && Map.has_key?(kill, "zkb"), do: inspect(kill["zkb"], limit: 200), else: "none"}
    * Raw data (excerpt): #{inspect(kill, limit: 300)}
    """)

    # Try to convert to standardized format
    data = Transformer.to_killmail_data(kill)

    case data do
      %KillmailData{} = killmail_data ->
        # Verify the ID was preserved during conversion
        if killmail_data.killmail_id do
          # Success - correctly formatted KillmailData
          # AppLogger.kill_debug("""
          # [KillsService] Transformation successful:
          # * Original kill_id: #{inspect(kill_id)}
          # * Transformed kill_id: #{inspect(killmail_data.killmail_id)}
          # * Struct type: #{killmail_data.__struct__}
          # * Has zkb_data: #{not is_nil(killmail_data.zkb_data) && killmail_data.zkb_data != %{}}
          # """)
          killmail_data
        else
          # ID was lost during conversion
          AppLogger.kill_warn("""
          [KillsService] KillmailData conversion lost ID - fixing
          * Original kill_id: #{inspect(kill_id)}
          * Transformed data keys: #{inspect(Map.keys(killmail_data))}
          * Transformed zkb_data: #{inspect(killmail_data.zkb_data, limit: 100)}
          """)

          # Manually set the killmail_id field
          %{killmail_data | killmail_id: kill_id}
        end

      nil ->
        # If conversion fails, we need to build a minimal valid map
        # that can be processed by the pipeline
        AppLogger.kill_warn("""
        [KillsService] Failed to convert killmail to KillmailData, building compatible format
        * Original kill_id: #{inspect(kill_id)}
        * Original keys: #{inspect(Map.keys(kill))}
        * Original data (excerpt): #{inspect(kill, limit: 200)}
        """)

        # Extract zkb data if available
        zkb_data =
          cond do
            Map.has_key?(kill, "zkb") -> Map.get(kill, "zkb", %{})
            Map.has_key?(kill, :zkb) -> Map.get(kill, :zkb, %{})
            Map.has_key?(kill, "zkb_data") -> Map.get(kill, "zkb_data", %{})
            Map.has_key?(kill, :zkb_data) -> Map.get(kill, :zkb_data, %{})
            true -> %{}
          end

        # Create a minimal map that the pipeline can work with
        minimal_map = %{
          "killmail_id" => kill_id,
          "zkb" => %{
            "hash" => Map.get(zkb_data, "hash", Map.get(zkb_data, :hash))
          }
        }

        AppLogger.kill_debug(
          "[KillsService] Created minimal compatible map: #{inspect(minimal_map)}"
        )

        minimal_map
    end
  end

  defp ensure_standardized_killmail(kill), do: kill

  # Attempt the killmail processing with retries for transient failures
  defp process_killmail_with_retries(kill, ctx, retry_count, max_retries \\ 2) do
    kill_id = extract_killmail_id(kill)

    # Log the full structure of the killmail data for debugging
    # AppLogger.kill_debug("""
    # [KillsService] Processing killmail data:
    # * Kill ID from extraction: #{inspect(kill_id)}
    # * Is struct: #{is_struct(kill)}
    # * Struct type: #{if is_struct(kill), do: kill.__struct__, else: "not a struct"}
    # * Top-level keys: #{inspect(if is_map(kill), do: Map.keys(kill), else: [])}
    # * Raw killmail data sample: #{inspect(kill, limit: 500)}
    # """)

    if retry_count > 0 do
      AppLogger.kill_debug("[KillsService] Retry attempt #{retry_count} for kill #{kill_id}")
    end

    case KillmailProcessor.process_killmail(kill, ctx) do
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
    system_id =
      cond do
        # KillmailData struct
        is_map(kill) && Map.has_key?(kill, :solar_system_id) && not is_nil(kill.solar_system_id) ->
          kill.solar_system_id

        # Raw map with string key
        is_map(kill) && Map.has_key?(kill, "solar_system_id") ->
          kill["solar_system_id"]

        # Raw map with atom key
        is_map(kill) && Map.has_key?(kill, :solar_system_id) ->
          kill.solar_system_id

        # ESI data nested map
        is_map(kill) && Map.has_key?(kill, :esi_data) &&
          is_map(kill.esi_data) && Map.has_key?(kill.esi_data, "solar_system_id") ->
          kill.esi_data["solar_system_id"]

        # Default case
        true ->
          nil
      end

    AppLogger.kill_debug("[KillsService] Pre-enriching kill data", %{
      kill_id: kill_id,
      system_id: system_id,
      kill_type: inspect_kill_type(kill)
    })

    # Pre-fetch the system name if that's an issue - this is the only validation we still need
    enriched_kill =
      if system_id && Enum.any?(reasons, &String.contains?(&1, "system name")) do
        case get_system_name_with_cache(system_id) do
          {:ok, system_name} ->
            AppLogger.kill_debug("[KillsService] Pre-enriched system name", %{
              kill_id: kill_id,
              system_id: system_id,
              system_name: system_name
            })

            # Add system name to the appropriate location based on the type of kill data
            add_system_name_to_kill(kill, system_id, system_name)

          _error ->
            kill
        end
      else
        kill
      end

    # Process the pre-enriched killmail with a fresh attempt
    process_killmail_with_retries(enriched_kill, ctx, 0)
  end

  # Helper to get info about the kill data type for logging
  defp inspect_kill_type(kill) do
    cond do
      is_struct(kill, WandererNotifier.KillmailProcessing.KillmailData) ->
        "KillmailData struct"

      is_struct(kill, WandererNotifier.Resources.Killmail) ->
        "Killmail resource"

      is_map(kill) && Map.has_key?(kill, :__struct__) ->
        "#{inspect(kill.__struct__)} struct"

      is_map(kill) ->
        "map with keys: #{inspect(Map.keys(kill))}"

      true ->
        "#{typeof(kill)}"
    end
  end

  # Helper to add system name to the appropriate location in the kill data
  defp add_system_name_to_kill(
         kill = %WandererNotifier.KillmailProcessing.KillmailData{},
         _system_id,
         system_name
       ) do
    # For KillmailData struct, set the solar_system_name field
    %{kill | solar_system_name: system_name}
  end

  defp add_system_name_to_kill(
         kill = %WandererNotifier.Resources.Killmail{},
         _system_id,
         system_name
       ) do
    # For Killmail resource, set the solar_system_name field
    %{kill | solar_system_name: system_name}
  end

  defp add_system_name_to_kill(kill, _system_id, system_name) when is_map(kill) do
    cond do
      # For maps with esi_data field, add to both top level and esi_data
      Map.has_key?(kill, :esi_data) && is_map(kill.esi_data) ->
        updated_esi = Map.put(kill.esi_data, "solar_system_name", system_name)

        kill
        |> Map.put(:esi_data, updated_esi)
        |> Map.put(:solar_system_name, system_name)

      # For maps with string esi_data key
      Map.has_key?(kill, "esi_data") && is_map(kill["esi_data"]) ->
        updated_esi = Map.put(kill["esi_data"], "solar_system_name", system_name)

        kill
        |> Map.put("esi_data", updated_esi)
        |> Map.put("solar_system_name", system_name)

      # For regular maps, just add the top-level solar_system_name
      true ->
        Map.put(kill, "solar_system_name", system_name)
    end
  end

  defp add_system_name_to_kill(kill, _system_id, _system_name) do
    # For non-maps, return as is
    kill
  end

  # Helper to get type of a value
  defp typeof(value) when is_binary(value), do: "string"
  defp typeof(value) when is_integer(value), do: "integer"
  defp typeof(value) when is_float(value), do: "float"
  defp typeof(value) when is_list(value), do: "list"
  defp typeof(value) when is_map(value), do: "map"
  defp typeof(value) when is_atom(value), do: "atom"
  defp typeof(_value), do: "unknown"

  defp extract_killmail_id(kill) when is_map(kill) do
    # Try multiple approaches to extract the ID
    kill_id =
      cond do
        # String key
        Map.has_key?(kill, "killmail_id") && not is_nil(kill["killmail_id"]) ->
          extracted_id = kill["killmail_id"]
          extracted_id

        # Atom key
        Map.has_key?(kill, :killmail_id) && not is_nil(kill.killmail_id) ->
          extracted_id = kill.killmail_id
          extracted_id

        # String ZKB nested
        Map.has_key?(kill, "zkb") && is_map(kill["zkb"]) &&
            Map.has_key?(kill["zkb"], "killmail_id") ->
          extracted_id = kill["zkb"]["killmail_id"]
          extracted_id

        # Atom ZKB nested
        Map.has_key?(kill, :zkb) && is_map(kill.zkb) && Map.has_key?(kill.zkb, "killmail_id") ->
          extracted_id = kill.zkb["killmail_id"]
          extracted_id

        # String ZKB data nested
        Map.has_key?(kill, "zkb_data") && is_map(kill["zkb_data"]) &&
            Map.has_key?(kill["zkb_data"], "killmail_id") ->
          extracted_id = kill["zkb_data"]["killmail_id"]
          extracted_id

        # Atom ZKB data nested
        Map.has_key?(kill, :zkb_data) && is_map(kill.zkb_data) &&
            Map.has_key?(kill.zkb_data, "killmail_id") ->
          extracted_id = kill.zkb_data["killmail_id"]
          extracted_id

        true ->
          "unknown"
      end

    kill_id
  end

  defp extract_killmail_id(_), do: "unknown"

  defp fetch_character_kills(character_id, _limit, _page, deps) do
    # Ensure character_id is an integer
    character_id_int = ensure_integer_id(character_id)

    Process.put(:current_character_id, character_id_int)

    case deps.zkill_client.get_character_kills(
           character_id_int,
           %{start: nil, end: nil},
           @max_kills
         ) do
      {:ok, kills} = result when is_list(kills) ->
        if length(kills) > 0 do
          AppLogger.kill_debug("📥 Retrieved #{length(kills)} kills", %{
            character_id: character_id_int
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

    # Wrap the entire function in a try/rescue block to catch any uncaught exceptions
    try do
      # Ensure character_id is an integer
      character_id_int = ensure_integer_id(character_id)

      character_name =
        case Repository.get_character_name(character_id_int) do
          {:ok, name} -> name
          _ -> "Unknown"
        end

      AppLogger.kill_debug("👥 Processing character", %{
        character_id: character_id_int,
        character_name: character_name
      })

      case fetch_kills(character_id_int, %{start: nil, end: nil}) do
        {:ok, kills} ->
          total_kills = length(kills)

          AppLogger.kill_debug("📥 Retrieved kills for processing", %{
            character_id: character_id_int,
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

          {:ok, stats} = process_kills_batch(kills, character_id_int)
          end_time = System.monotonic_time()
          processing_time = System.convert_time_unit(end_time - start_time, :native, :millisecond)

          AppLogger.kill_debug("📊 Batch processing metrics", %{
            character_id: character_id_int,
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
            character_id: character_id_int,
            character_name: character_name,
            error: inspect(reason)
          })

          {:error, reason}
      end
    rescue
      e ->
        # Catch any uncaught exception
        stacktrace = __STACKTRACE__

        AppLogger.kill_error("💥 Unhandled exception in process_character_kills", %{
          character_id: character_id,
          error: Exception.message(e),
          stacktrace: Exception.format_stacktrace(stacktrace)
        })

        # Return error with exception details
        {:error, {:exception, Exception.message(e)}}
    catch
      kind, value ->
        # Catch any throws or exits
        AppLogger.kill_error("💥 Uncaught #{kind} in process_character_kills", %{
          character_id: character_id,
          kind: kind,
          value: inspect(value)
        })

        # Return error with details
        {:error, {:uncaught, "#{kind}: #{inspect(value)}"}}
    end
  end

  # Helper function to ensure character_id is an integer
  defp ensure_integer_id(id) when is_integer(id), do: id

  defp ensure_integer_id(id) when is_binary(id) do
    case Integer.parse(id) do
      {int_id, ""} ->
        int_id

      _ ->
        AppLogger.kill_warn("[CHARACTER_KILLS] Invalid character ID format", %{
          character_id: id
        })

        # Return the original id to let the downstream functions handle the error
        id
    end
  end

  defp ensure_integer_id(id), do: id

  @spec fetch_kills(pos_integer() | String.t(), date_range()) ::
          {:ok, list(map())} | {:error, term()}
  defp fetch_kills(character_id, date_range) do
    # Start timing
    fetch_start_time = System.monotonic_time(:millisecond)

    AppLogger.kill_debug("[TIMING] Starting fetch_kills for character_id=#{character_id}", %{
      timestamp: fetch_start_time,
      date_range: date_range
    })

    # Ensure character_id is an integer
    character_id_int = ensure_integer_id(character_id)

    debug_log(character_id_int, "Fetching kills from ZKill", %{
      date_range: date_range,
      limit: @max_kills
    })

    # Time the ZKill client call
    zkill_start_time = System.monotonic_time(:millisecond)

    AppLogger.kill_debug(
      "[TIMING] Starting ZKillClient.get_character_kills for character_id=#{character_id_int}",
      %{
        timestamp: zkill_start_time
      }
    )

    result = ZKillClient.get_character_kills(character_id_int, date_range, @max_kills)

    # Calculate time spent in ZKill client
    zkill_end_time = System.monotonic_time(:millisecond)
    zkill_duration = zkill_end_time - zkill_start_time

    AppLogger.kill_debug(
      "[TIMING] ZKillClient.get_character_kills completed in #{zkill_duration}ms",
      %{
        duration_ms: zkill_duration,
        character_id: character_id_int
      }
    )

    case result do
      {:ok, kills} ->
        # Log details about retrieved kills
        kill_count = length(kills)

        # Calculate average kill size if there are kills
        avg_kill_size =
          if kill_count > 0 do
            total_size =
              Enum.reduce(kills, 0, fn kill, acc ->
                acc + byte_size(inspect(kill))
              end)

            total_size / kill_count
          else
            0
          end

        debug_log(character_id_int, "Retrieved #{kill_count} kills", %{
          date_range: date_range,
          limit: @max_kills,
          avg_kill_size_bytes: avg_kill_size
        })

        # Total time spent in fetch_kills
        fetch_end_time = System.monotonic_time(:millisecond)
        fetch_duration = fetch_end_time - fetch_start_time

        AppLogger.kill_debug("[TIMING] fetch_kills completed in #{fetch_duration}ms", %{
          duration_ms: fetch_duration,
          kill_count: kill_count,
          character_id: character_id_int
        })

        {:ok, kills}

      error ->
        debug_log(character_id_int, "Failed to fetch kills", %{
          error: inspect(error),
          date_range: date_range,
          limit: @max_kills
        })

        # Total time spent in fetch_kills (error case)
        fetch_end_time = System.monotonic_time(:millisecond)
        fetch_duration = fetch_end_time - fetch_start_time

        AppLogger.kill_debug("[TIMING] fetch_kills failed in #{fetch_duration}ms", %{
          duration_ms: fetch_duration,
          character_id: character_id_int,
          error: inspect(error)
        })

        error
    end
  end

  defp generate_batch_id do
    :crypto.strong_rand_bytes(16)
    |> Base.encode16()
    |> String.downcase()
  end

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
      {:ok, ship_debug} ->
        name = Map.get(ship_debug, "name")

        if is_binary(name) && name != "" do
          # Cache for 30 days (ship types don't change)
          CacheRepo.set(cache_key, ship_debug, 30 * 86_400)

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
    cache_key = "system_debug:#{system_id}"

    case CacheRepo.get(cache_key) do
      {:ok, system_debug} when is_map(system_debug) ->
        name = Map.get(system_debug, "name")
        {:ok, name}

      _ ->
        fetch_and_cache_system_name(system_id, cache_key)
    end
  end

  defp fetch_and_cache_system_name(system_id, cache_key) do
    case ESIService.get_system_info(system_id) do
      {:ok, system_debug} -> handle_system_debug_response(system_debug, system_id, cache_key)
      error -> handle_system_debug_error(error, system_id)
    end
  end

  defp handle_system_debug_response(system_debug, system_id, cache_key) do
    name = Map.get(system_debug, "name")

    if is_binary(name) && name != "" do
      # Cache for 30 days (system names don't change)
      CacheRepo.set(cache_key, system_debug, 30 * 86_400)

      AppLogger.kill_debug("[KillsService] Retrieved and cached system name", %{
        system_id: system_id,
        name: name
      })

      {:ok, name}
    else
      {:error, :invalid_system_data}
    end
  end

  defp handle_system_debug_error(error, system_id) do
    AppLogger.kill_error("[KillsService] Failed to get system name", %{
      system_id: system_id,
      error: inspect(error)
    })

    error
  end
end
