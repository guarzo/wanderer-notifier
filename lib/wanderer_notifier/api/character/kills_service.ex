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
  alias WandererNotifier.Data.Repository
  alias WandererNotifier.KillmailProcessing.Context
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

  # Add debug character ID constant
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

  # Helper for extracting and validating character IDs
  defp extract_valid_character_ids(characters) do
    characters
    |> Enum.map(&extract_character_id/1)
    |> Enum.reject(&is_nil/1)
    |> tap(fn ids ->
      AppLogger.kill_debug("[CHARACTER_KILLS] Extracted character IDs",
        extracted_count: length(ids),
        valid_ids: Enum.reject(ids, &is_nil/1),
        sample_id: List.first(ids)
      )
    end)
  end

  @type date_range :: %{start: DateTime.t(), end: DateTime.t()}
  @type batch_stats :: %{
          total: non_neg_integer(),
          processed: non_neg_integer(),
          skipped: non_neg_integer(),
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
      # Process kills in batches
      stats = process_kills_batch(kills, ctx)

      # Calculate total duration
      duration =
        System.convert_time_unit(System.monotonic_time() - start_time, :native, :millisecond)

      # Log completion
      AppLogger.kill_info("Completed historical kill processing", %{
        character_id: character_id,
        character_name: character_name,
        batch_id: batch_id,
        total_kills: stats.total,
        processed: stats.processed,
        skipped: stats.skipped,
        errors: stats.errors,
        duration_ms: duration
      })

      {:ok, %{stats | duration_ms: duration}}
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
      process_tracked_characters(tracked_characters, limit, page, deps)
    end
  end

  defp log_tracked_characters_info(tracked_characters) do
    # Log debug character status
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

  defp process_tracked_characters(tracked_characters, limit, page, deps) do
    AppLogger.kill_info("[CHARACTER_KILLS] Processing tracked characters",
      character_count: length(tracked_characters),
      sample_character: List.first(tracked_characters)
    )

    results =
      tracked_characters
      |> extract_valid_character_ids()
      |> Task.async_stream(
        fn character_id ->
          # Get character name for logging from the tracked_characters list
          name_from_tracked =
            Enum.find_value(tracked_characters, fn char ->
              if to_string(Map.get(char, "character_id", "")) == to_string(character_id) do
                Map.get(char, "character_name", nil)
              end
            end)

          # If name is unknown or missing, try to resolve before logging
          character_name =
            if is_nil(name_from_tracked) || name_from_tracked == "Unknown" do
              # First try repository
              case deps.repository.get_character_name(character_id) do
                {:ok, name} when is_binary(name) and name != "" and name != "Unknown" ->
                  name

                repo_error ->
                  # Only if repository fails, try ESI
                  case deps.esi_service.get_character(character_id) do
                    {:ok, %{"name" => name}} when is_binary(name) and name != "" ->
                      # Update the cache immediately
                      deps.cache_helpers.cache_character_info(%{
                        "character_id" => character_id,
                        "name" => name
                      })

                      name

                    esi_error ->
                      # Log the error but continue processing other characters
                      AppLogger.kill_error(
                        "[BATCH] Failed to resolve character name - BOTH tracked data and ESI failed",
                        %{
                          character_id: character_id,
                          from_tracked: name_from_tracked,
                          repo_error: inspect(repo_error),
                          esi_error: inspect(esi_error)
                        }
                      )

                      # Return error instead of using an unknown name
                      raise "Failed to resolve character name for ID #{character_id} in batch processing - both repository and ESI lookup failed"
                  end
              end
            else
              name_from_tracked
            end

          # Now log with the best name we have
          AppLogger.kill_info("[CHARACTER_KILLS] Processing character", %{
            character_id: character_id,
            character_name: character_name
          })

          result = fetch_and_persist_character_kills(character_id, limit, page, deps)

          # Log per-character summary
          case result do
            {:ok, stats} when is_map(stats) ->
              AppLogger.kill_info("[CHARACTER_KILLS] Character processing complete", %{
                character_id: character_id,
                total_kills: stats.total,
                processed: stats.processed,
                skipped: stats.skipped,
                duplicates: stats.duplicates,
                errors: stats.errors,
                success_rate: "#{Float.round(stats.processed / max(stats.total, 1) * 100, 2)}%"
              })

              {:ok, stats}

            {:error, reason} ->
              AppLogger.kill_error("[CHARACTER_KILLS] Character processing failed", %{
                character_id: character_id,
                error: inspect(reason)
              })

              {:error, reason}

            {:ok, :skipped} ->
              AppLogger.kill_debug("[CHARACTER_KILLS] Character processing skipped", %{
                character_id: character_id
              })

              {:ok, %{total: 0, processed: 0, skipped: 1, duplicates: 0, errors: 0}}

            other ->
              AppLogger.kill_debug("[CHARACTER_KILLS] Unexpected result", %{
                character_id: character_id,
                result: inspect(other)
              })

              {:error, :unexpected_result}
          end
        end,
        # 300 second timeout per character (5 minutes)
        timeout: 300_000,
        # Reduced concurrency to prevent overload
        max_concurrency: 2,
        # Allow partial success by returning error instead of killing task
        on_timeout: :exit
      )
      |> Enum.to_list()
      |> Enum.map(fn
        {:ok, result} ->
          result

        {:exit, :timeout} ->
          AppLogger.kill_warn("[CHARACTER_KILLS] Character processing timed out")
          {:error, :timeout}

        {:exit, reason} ->
          AppLogger.kill_warn("[CHARACTER_KILLS] Character processing exited", %{
            reason: inspect(reason)
          })

          {:error, reason}
      end)

    summarize_batch_results(results)
  end

  defp summarize_batch_results(results) do
    # Initialize totals
    initial_totals = %{
      total_kills: 0,
      processed: 0,
      persisted: 0,
      skipped: 0,
      errors: 0,
      timeouts: 0,
      characters: 0,
      successful_characters: 0,
      failed_characters: 0,
      # Track character names for better logging
      character_names: []
    }

    # Aggregate results from all characters
    totals =
      Enum.reduce(results, initial_totals, fn
        {:ok, stats}, acc ->
          # Get character name from stats if available
          character_name = Map.get(stats, :character_name, "Unknown")

          %{
            acc
            | total_kills: acc.total_kills + stats.total,
              processed: acc.processed + stats.processed,
              skipped: acc.skipped + stats.skipped,
              errors: acc.errors + stats.errors,
              characters: acc.characters + 1,
              successful_characters: acc.successful_characters + 1,
              character_names: acc.character_names ++ [{character_name, stats.processed}]
          }

        {:error, _}, acc ->
          %{
            acc
            | characters: acc.characters + 1,
              failed_characters: acc.failed_characters + 1
          }
      end)

    # Log individual character summaries
    Enum.each(totals.character_names, fn {character_name, processed_count} ->
      AppLogger.kill_info("📊 Character processing summary", %{
        character_name: character_name,
        processed_kills: processed_count
      })
    end)

    # Log overall summary
    AppLogger.kill_info("📊 Overall batch processing summary", %{
      total_characters: totals.characters,
      successful_characters: totals.successful_characters,
      failed_characters: totals.failed_characters,
      total_kills: totals.total_kills,
      processed_kills: totals.processed,
      skipped_kills: totals.skipped,
      errors: totals.errors,
      success_rate: "#{Float.round(totals.processed / max(totals.total_kills, 1) * 100, 2)}%",
      character_success_rate:
        "#{Float.round(totals.successful_characters / max(totals.characters, 1) * 100, 2)}%"
    })

    if totals.successful_characters > 0 do
      {:ok,
       %{
         processed: totals.processed,
         persisted: totals.persisted,
         characters: totals.successful_characters
       }}
    else
      {:error, :no_successful_results}
    end
  end

  @doc """
  Fetches and persists kills for a single character.
  """
  @spec fetch_and_persist_character_kills(integer(), integer(), integer(), map()) ::
          {:ok, %{processed: integer(), persisted: integer()}}
          | {:error, term()}
  def fetch_and_persist_character_kills(
        character_id,
        limit \\ 25,
        page \\ 1,
        deps \\ @default_deps
      ) do
    # First check if this character is actually tracked
    is_tracked = is_character_tracked?(character_id)

    # Skip processing for untracked characters
    if not is_tracked do
      # Don't include character_name in the log for untracked characters
      AppLogger.kill_info("[CHARACTER_KILLS] Skipping untracked character", %{
        character_id: character_id
      })

      return_stats = %{total: 0, processed: 0, skipped: 1, duplicates: 0, errors: 0}
      {:ok, return_stats}
    else
      # Get the most accurate character name before logging anything
      # Use direct repository lookup first (which should have cached data)
      character_name =
        case deps.repository.get_character_name(character_id) do
          {:ok, name} when is_binary(name) and name != "" and name != "Unknown" ->
            AppLogger.kill_debug("[FETCH_PERSIST] Found character name in repository", %{
              character_id: character_id,
              character_name: name
            })

            name

          repo_error ->
            # Only if repository lookup fails, try ESI as fallback
            AppLogger.kill_warn("[FETCH_PERSIST] Repository lookup failed for character name", %{
              character_id: character_id,
              repo_error: inspect(repo_error)
            })

            case deps.esi_service.get_character(character_id) do
              {:ok, %{"name" => name}} when is_binary(name) and name != "" ->
                # Update the cache immediately
                deps.cache_helpers.cache_character_info(%{
                  "character_id" => character_id,
                  "name" => name
                })

                name

              esi_error ->
                AppLogger.kill_error(
                  "[FETCH_PERSIST] Failed to resolve character name - BOTH repository and ESI failed",
                  %{
                    character_id: character_id,
                    repo_error: inspect(repo_error),
                    esi_error: inspect(esi_error)
                  }
                )

                # Throw a proper error instead of using an unknown name
                raise "Failed to resolve character name for ID #{character_id} during fetch and persist - both repository and ESI lookup failed"
            end
        end

      AppLogger.kill_info(
        "[CHARACTER_KILLS] Starting kill fetch and persist",
        %{
          character_id: character_id,
          character_name: character_name,
          limit: limit,
          page: page
        }
      )

      case fetch_character_kills(character_id, limit, page, deps) do
        {:ok, kills} when is_list(kills) ->
          kill_count = Enum.count(kills)

          AppLogger.kill_info(
            "[CHARACTER_KILLS] Processing kills batch for character",
            %{
              character_id: character_id,
              character_name: character_name,
              kill_count: kill_count
            }
          )

          # Create context with resolved name
          ctx =
            Context.new_historical(
              character_id,
              character_name,
              :zkill_api,
              generate_batch_id(),
              []
            )

          case process_kills_batch(kills, ctx) do
            {:ok, stats} ->
              # Add character_name to stats for proper logging in calling function
              stats = Map.put(stats, :character_name, character_name)
              {:ok, stats}

            {:error, reason} ->
              AppLogger.kill_error(
                "[CHARACTER_KILLS] Failed to process kills",
                %{
                  character_id: character_id,
                  character_name: character_name,
                  error: inspect(reason)
                }
              )

              {:error, reason}
          end

        {:error, reason} ->
          AppLogger.kill_error(
            "[CHARACTER_KILLS] Failed to fetch kills",
            %{
              character_id: character_id,
              character_name: character_name || "Unknown",
              error: inspect(reason)
            }
          )

          {:error, reason}
      end
    end
  end

  # Helper function to check if a character is tracked
  defp is_character_tracked?(character_id) do
    # Get the list of tracked characters
    tracked_characters = Repository.get_tracked_characters()

    # Check if the character is in the tracked list
    Enum.any?(tracked_characters, fn char ->
      char_id =
        if is_map(char),
          do: Map.get(char, :character_id) || Map.get(char, "character_id"),
          else: nil

      to_string(char_id) == to_string(character_id)
    end)
  end

  @doc """
  Process tracked characters' kills.
  """
  def process_tracked_characters(characters, _opts \\ []) do
    character_count = length(characters)
    AppLogger.kill_info("👥 Processing #{character_count} tracked characters")

    # Extract character IDs for processing
    character_ids = Enum.map(characters, & &1["character_id"])

    # Process each character's kills
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

    if length(errors) > 0 do
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

  defp process_kills_batch(kills, character_id) when is_integer(character_id) do
    # First try to get the character name from the cache, where it should be for tracked characters
    character_name =
      case Repository.get_character_name(character_id) do
        {:ok, name} when is_binary(name) and name != "" and name != "Unknown" ->
          AppLogger.kill_debug("[PROCESS_BATCH] Found character name in cache", %{
            character_id: character_id,
            character_name: name
          })

          name

        cache_error ->
          # Only if cache lookup fails, try ESI as fallback
          AppLogger.kill_warn("[PROCESS_BATCH] Cache miss for character name", %{
            character_id: character_id,
            cache_result: inspect(cache_error)
          })

          case ESIService.get_character(character_id) do
            {:ok, %{"name" => name}} when is_binary(name) and name != "" ->
              # Update the cache for future use
              WandererNotifier.Data.Cache.Helpers.cache_character_info(%{
                "character_id" => character_id,
                "name" => name
              })

              name

            esi_error ->
              AppLogger.kill_error(
                "[PROCESS_BATCH] Failed to resolve character name - BOTH cache and ESI failed",
                %{
                  character_id: character_id,
                  cache_error: inspect(cache_error),
                  esi_error: inspect(esi_error)
                }
              )

              # Throw a proper error instead of using an unknown name
              raise "Failed to resolve character name for ID #{character_id} - both cache and ESI lookup failed"
          end
      end

    # Create a context for processing with the properly resolved character name
    ctx =
      Context.new_historical(character_id, character_name, :zkill_api, generate_batch_id(), [])

    process_kills_batch(kills, ctx)
  end

  defp process_kills_batch(kills, %Context{} = ctx) do
    start_time = System.monotonic_time()

    # Get concurrency from context options
    concurrency = get_in(ctx.options, [:concurrency]) || 2

    # Create a set of known kill IDs that we've already processed
    # We'll skip these to avoid duplicate processing
    known_kill_ids =
      WandererNotifier.Resources.KillmailPersistence.get_already_processed_kill_ids(
        ctx.character_id
      )

    AppLogger.kill_debug("[KillsService] Filtering already processed kills", %{
      total_kills: length(kills),
      already_processed: MapSet.size(known_kill_ids),
      character_id: ctx.character_id
    })

    # Filter out already processed kills
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
        # 120 second timeout per kill
        timeout: 120_000,
        # Kill the task on timeout
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

        # Print stats summary
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

    # Directly use the same Pipeline module that the realtime processing uses
    case WandererNotifier.KillmailProcessing.Pipeline.process_killmail(kill, ctx) do
      {:ok, _} ->
        :processed

      error ->
        AppLogger.kill_error("[KillsService] Pipeline processing failed", %{
          kill_id: kill_id,
          character_id: ctx.character_id,
          error: inspect(error)
        })

        error
    end
  end

  # Safely extract killmail ID from various formats
  defp extract_killmail_id(kill) when is_map(kill) do
    cond do
      Map.has_key?(kill, "killmail_id") -> kill["killmail_id"]
      Map.has_key?(kill, :killmail_id) -> kill.killmail_id
      true -> "unknown"
    end
  end

  defp extract_killmail_id(_), do: "unknown"

  defp fetch_character_kills(character_id, _limit, _page, deps) do
    # Store the character ID in process dictionary for the persistence context
    Process.put(:current_character_id, character_id)

    case deps.zkill_client.get_character_kills(character_id, %{start: nil, end: nil}, @max_kills) do
      {:ok, kills} = result when is_list(kills) ->
        # Log only if we have kills
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

  defp extract_character_id(%{character_id: character_id}) when is_integer(character_id),
    do: character_id

  defp extract_character_id(%{character_id: character_id}) when is_binary(character_id) do
    case Integer.parse(character_id) do
      {id, _} -> id
      :error -> nil
    end
  end

  defp extract_character_id(%{"character_id" => character_id}) when is_integer(character_id),
    do: character_id

  defp extract_character_id(%{"character_id" => character_id}) when is_binary(character_id) do
    case Integer.parse(character_id) do
      {id, _} -> id
      :error -> nil
    end
  end

  defp extract_character_id(_), do: nil

  defp filter_kills_by_date(kills, from, to) do
    kills
    |> Enum.filter(fn kill ->
      case DateTime.from_iso8601(kill["killmail_time"]) do
        {:ok, kill_time, _} ->
          kill_date = DateTime.to_date(kill_time)
          Date.compare(kill_date, from) != :lt and Date.compare(kill_date, to) != :gt

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
      # Log the raw result from ESI API
      AppLogger.kill_debug("[KillsService] Raw ESI response data", %{
        kill_id: kill_id,
        victim_data: victim,
        ship_data: ship
      })

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
         # Include IDs for easier debugging
         victim_id: victim_id,
         ship_id: ship_id
       }}
    else
      {:error, reason} ->
        AppLogger.kill_error("[CHARACTER_KILLS] Failed to enrich kill: #{inspect(reason)}", %{
          kill_id: kill_id,
          victim_id: get_in(kill, ["victim", "character_id"]),
          ship_id: get_in(kill, ["victim", "ship_type_id"]),
          error: inspect(reason)
        })

        {:error, :api_error}

      nil ->
        AppLogger.kill_error("[CHARACTER_KILLS] Failed to extract victim or ship ID", %{
          kill_id: kill_id,
          victim: get_in(kill, ["victim"]),
          raw_data_sample: inspect(kill, limit: 200)
        })

        {:error, :invalid_kill_data}

      _ ->
        AppLogger.kill_error("[CHARACTER_KILLS] Failed to extract kill data", %{
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

    # Get character name from repository
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

        # Log initial kill count
        AppLogger.kill_info("📥 Retrieved kills for processing", %{
          character_id: character_id,
          character_name: character_name,
          total_kills: total_kills,
          sample_kill:
            if(total_kills > 0,
              do: %{
                id: List.first(kills)["killmail_id"],
                time: List.first(kills)["killmail_time"]
              },
              else: nil
            )
        })

        stats = process_kills_batch(kills, character_id)
        end_time = System.monotonic_time()
        processing_time = System.convert_time_unit(end_time - start_time, :native, :millisecond)

        # Log batch processing metrics with more detail
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

      {:error, reason} = error ->
        AppLogger.kill_error("❌ Failed to fetch kills", %{
          character_id: character_id,
          character_name: character_name,
          error: inspect(reason)
        })

        error
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

  @spec generate_batch_id() :: String.t()
  defp generate_batch_id do
    :crypto.strong_rand_bytes(16)
    |> Base.encode16()
    |> String.downcase()
  end

  # Helper function to convert kill ID to integer for consistency
  defp parse_kill_id(kill_id) when is_integer(kill_id), do: kill_id

  defp parse_kill_id(kill_id) when is_binary(kill_id) do
    case Integer.parse(kill_id) do
      {id, _} -> id
      :error -> nil
    end
  end

  defp parse_kill_id(_), do: nil
end
