defmodule WandererNotifier.Services.CharacterKillsService do
  @moduledoc """
  Service for fetching and processing character kills from ZKillboard.
  This service provides functions to retrieve character kills and persist them.
  """

  # Default modules
  @zkill_client Application.compile_env(:wanderer_notifier, :zkill_client)
  @esi_service Application.compile_env(:wanderer_notifier, :esi_service)
  @cache_repo Application.compile_env(
                :wanderer_notifier,
                :cache_repo_module,
                WandererNotifier.Data.Cache.Repository
              )
  @cache_helpers Application.compile_env(:wanderer_notifier, :cache_helpers)
  @killmail_persistence Application.compile_env(:wanderer_notifier, :killmail_persistence)
  @repository Application.compile_env(:wanderer_notifier, :repository)
  @logger Application.compile_env(:wanderer_notifier, :logger, WandererNotifier.Logger)

  # Caching and throttling settings
  # 5 minutes
  @cache_ttl_seconds 300
  # Slightly over 1 second to respect API rate limits
  @rate_limit_ms 1100

  @doc """
  Fetches and persists recent kills for a tracked character.

  ## Parameters
    - character_id: The character ID to fetch kills for
    - limit: The maximum number of kills to retrieve (default: 25)
    - page: The page of results to fetch (default: 1)

  ## Returns
    - {:ok, %{processed: number_processed, persisted: number_persisted}} on success
    - {:error, reason} if fetching or processing fails
  """
  @spec fetch_and_persist_character_kills(integer(), integer(), integer()) ::
          {:ok, %{processed: integer(), persisted: integer()}} | {:error, term()}
  def fetch_and_persist_character_kills(character_id, limit \\ 25, page \\ 1) do
    @logger.debug("[CHARACTER_KILLS] Fetching and persisting kills for character #{character_id}")

    case @cache_helpers.get_cached_kills(character_id) do
      {:ok, cached_kills} when length(cached_kills) > 0 ->
        @logger.debug("[CHARACTER_KILLS] Found #{length(cached_kills)} cached kills")
        process_kills_batch(cached_kills, character_id)

      {:ok, _} ->
        @logger.debug("[CHARACTER_KILLS] No cached kills found, fetching from API")
        fetch_fresh_kills(character_id, limit, page)

      error ->
        error
    end
  end

  defp process_and_persist_kills([]), do: {:ok, %{processed: 0, persisted: 0}}

  defp process_and_persist_kills(kills) do
    @logger.debug("[CHARACTER_KILLS] Processing and persisting #{length(kills)} kills")

    processed_kills =
      Enum.reduce_while(kills, [], fn kill, acc ->
        case process_single_kill(kill) do
          {:ok, processed_kill} ->
            {:cont, [processed_kill | acc]}

          {:error, :api_error} ->
            {:halt, :api_error}

          {:error, reason} ->
            @logger.warn("[CHARACTER_KILLS] Failed to process kill: #{inspect(reason)}")
            {:cont, acc}
        end
      end)

    case processed_kills do
      :api_error ->
        {:error, :api_error}

      kills when is_list(kills) ->
        persisted = persist_kills(kills)
        {:ok, %{processed: length(kills), persisted: length(persisted)}}
    end
  end

  defp persist_kills(kills) do
    @logger.debug("[CHARACTER_KILLS] Persisting #{length(kills)} kills")

    Enum.filter(kills, fn kill ->
      case @killmail_persistence.maybe_persist_killmail(kill) do
        {:ok, _} ->
          true

        {:error, reason} ->
          @logger.warn("[CHARACTER_KILLS] Failed to persist kill: #{inspect(reason)}")
          false
      end
    end)
  end

  # Handle nil or invalid character IDs
  def fetch_and_persist_character_kills(nil, _limit, _page) do
    @logger.api_error("Invalid character ID", value: nil)
    {:error, "Invalid character ID: nil"}
  end

  # Handle string character IDs by converting them to integers
  def fetch_and_persist_character_kills(character_id, limit, page) when is_binary(character_id) do
    @logger.processor_debug("Converting string character ID to integer",
      character_id: character_id
    )

    case Integer.parse(character_id) do
      {int_id, ""} ->
        # Successfully parsed, call the function again with integer ID
        fetch_and_persist_character_kills(int_id, limit, page)

      _ ->
        @logger.api_error("Invalid character ID string", character_id: character_id)
        {:error, "Invalid character ID string: #{character_id}"}
    end
  end

  def fetch_and_persist_character_kills(character_id, limit, page)
      when is_integer(character_id) and character_id > 0 do
    @logger.processor_info("Fetching kills for character", character_id: character_id)
    character_id_str = to_string(character_id)
    cache_key = "zkill:character_kills:#{character_id_str}:#{page}"

    result =
      if @cache_repo.exists?(cache_key) do
        @logger.processor_info("Using cached kills for character", character_id: character_id)
        cached_response = @cache_repo.get(cache_key)

        case cached_response do
          kills when is_list(kills) ->
            process_kills_batch(kills, character_id)

          _ ->
            @logger.processor_warn(
              "Cached data not in expected format",
              character_id: character_id,
              action: "fetching_fresh_data"
            )

            @cache_repo.delete(cache_key)
            fetch_fresh_kills(character_id, limit, page, cache_key)
        end
      else
        fetch_fresh_kills(character_id, limit, page, cache_key)
      end

    case result do
      {:ok, stats} -> {:ok, stats}
      {:error, :api_error} = error -> error
      {:error, _reason} -> {:error, :api_error}
    end
  end

  # Handle any other invalid character ID type
  def fetch_and_persist_character_kills(character_id, _limit, _page) do
    @logger.api_error("Invalid character ID", character_id: inspect(character_id))
    {:error, "Invalid character ID: #{inspect(character_id)}"}
  end

  # Extract the logic to fetch fresh data into a separate function
  defp fetch_fresh_kills(character_id, limit, page, retry_count \\ 0) do
    case @zkill_client.get_character_kills(character_id, limit, page) do
      {:ok, kills} when is_list(kills) ->
        process_kills_batch(kills, character_id)

      {:error, _reason} ->
        {:error, :api_error}
    end
  end

  defp process_kills_batch(kills, character_id) do
    @logger.processor_info("Processing kills batch", count: length(kills))

    {processed, persisted} =
      Enum.reduce(kills, {0, 0}, fn kill, {processed_acc, persisted_acc} ->
        case process_single_kill(kill, character_id) do
          {:ok, killmail_data} ->
            case @killmail_persistence.maybe_persist_killmail(killmail_data) do
              {:ok, :persisted} -> {processed_acc + 1, persisted_acc + 1}
              {:ok, :not_persisted} -> {processed_acc + 1, persisted_acc}
              {:error, _reason} -> {processed_acc + 1, persisted_acc}
            end

          {:error, _reason} ->
            {processed_acc, persisted_acc}
        end
      end)

    {:ok, %{processed: processed, persisted: persisted}}
  end

  defp process_single_kill(kill, character_id) do
    @logger.debug("[CHARACTER_KILLS] Processing kill: #{inspect(kill["killmail_id"])}")

    with {:ok, victim} <- @esi_service.get_character(kill["victim"]["character_id"]),
         {:ok, ship} <- @esi_service.get_type(kill["victim"]["ship_type_id"]) do
      {:ok,
       %{
         id: kill["killmail_id"],
         time: kill["killmail_time"],
         victim_name: victim["name"],
         ship_name: ship["name"]
       }}
    else
      {:error, reason} ->
        @logger.error("[CHARACTER_KILLS] ESI API error: #{inspect(reason)}")
        {:error, :api_error}
    end
  end

  @doc """
  Fetches and persists recent kills for all tracked characters.

  ## Parameters
    - limit: The maximum number of kills to retrieve per character (default: 25)
    - page: The page of results to fetch (default: 1)

  ## Returns
    - {:ok, %{processed: total_processed, persisted: total_persisted, characters: num_characters}} on success
    - {:error, reason} if fetching or processing fails
  """
  @spec fetch_and_persist_all_tracked_character_kills(integer(), integer()) ::
          {:ok, %{processed: integer(), persisted: integer(), characters: integer()}}
          | {:error, String.t()}
  def fetch_and_persist_all_tracked_character_kills(limit \\ 25, page \\ 1) do
    @logger.debug("[CHARACTER_KILLS] Fetching and persisting kills for all tracked characters")

    case @repository.get_tracked_characters() do
      [] ->
        @logger.warn("[CHARACTER_KILLS] No tracked characters found")
        {:ok, %{processed: 0, persisted: 0, characters: 0}}

      tracked_characters ->
        @logger.debug(
          "[CHARACTER_KILLS] Processing #{length(tracked_characters)} tracked characters"
        )

        results =
          Enum.map(tracked_characters, fn character ->
            case extract_character_id(character) do
              {:ok, character_id} ->
                case fetch_and_persist_character_kills(character_id, limit, page) do
                  {:ok, result} ->
                    {:ok, result}

                  {:error, reason} ->
                    @logger.error(
                      "[CHARACTER_KILLS] Failed to process character #{character_id}: #{inspect(reason)}"
                    )

                    {:error, reason}
                end

              {:error, reason} ->
                @logger.error("[CHARACTER_KILLS] Invalid character ID: #{inspect(reason)}")
                {:error, reason}
            end
          end)

        successful_results = Enum.filter(results, &match?({:ok, _}, &1))

        if Enum.empty?(successful_results) do
          {:error, "No characters processed successfully"}
        else
          total_processed = Enum.sum(for {:ok, %{processed: p}} <- successful_results, do: p)
          total_persisted = Enum.sum(for {:ok, %{persisted: p}} <- successful_results, do: p)

          {:ok,
           %{
             processed: total_processed,
             persisted: total_persisted,
             characters: length(successful_results)
           }}
        end
    end
  end

  defp extract_character_id(%{character_id: id}) when is_integer(id), do: {:ok, id}

  defp extract_character_id(%{character_id: id}) when is_binary(id) do
    case Integer.parse(id) do
      {int_id, ""} -> {:ok, int_id}
      _ -> {:error, "Invalid character ID format"}
    end
  end

  defp extract_character_id(_), do: {:error, "Missing character ID"}

  # Process a single character and return the result
  defp process_single_character(character, limit, page) do
    # Extract the character ID
    character_id = extract_character_id(character)

    # Skip invalid character IDs
    if is_nil(character_id) do
      @logger.processor_warn(
        "Skipping character with invalid ID",
        character: inspect(character)
      )

      {:error, :invalid_character_id}
    else
      # Add log to track individual character progress
      @logger.processor_info("Fetching kills for individual character in batch",
        character_id: character_id,
        limit: limit,
        page: page,
        cache_ttl: @cache_ttl_seconds
      )

      result = fetch_character_kills_safely(character_id, limit, page)

      # Log the result of this individual character's processing
      case result do
        {:ok, stats} ->
          @logger.processor_info("Completed processing character in batch",
            character_id: character_id,
            processed: stats.processed,
            persisted: stats.persisted
          )

        {:error, reason} ->
          @logger.processor_warn("Failed to process character in batch",
            character_id: character_id,
            reason: inspect(reason)
          )
      end

      result
    end
  end

  # Extract character ID from various character formats
  defp extract_character_id(character) do
    case character do
      # Handle struct with character_id key
      %{character_id: id} -> id
      # Handle map with string keys
      %{"character_id" => id} -> id
      # If the character is a string directly
      id when is_binary(id) -> id
      id when is_integer(id) -> id
      _ -> nil
    end
  end

  # Safely fetch kills for a character with error handling
  defp fetch_character_kills_safely(character_id, limit, page) do
    @logger.processor_info("Processing character ID", character_id: character_id)
    throttle_request()

    try do
      fetch_and_persist_character_kills(character_id, limit, page)
    rescue
      e ->
        @logger.processor_error(
          "Error processing character",
          character_id: character_id,
          error: inspect(e)
        )

        {:error, {:exception, e}}
    catch
      kind, reason ->
        @logger.processor_error(
          "Caught error while processing character",
          character_id: character_id,
          kind: kind,
          reason: inspect(reason)
        )

        {:error, {kind, reason}}
    end
  end

  # Find API errors in results
  defp find_api_errors(results) do
    Enum.filter(results, fn
      {:error, {:domain_error, :zkill, {:api_error, _}}} -> true
      _ -> false
    end)
  end

  # Aggregate successful results
  defp aggregate_successful_results(results, tracked_characters) do
    # Filter successful results
    successes =
      Enum.filter(results, fn
        {:ok, _} -> true
        _ -> false
      end)

    if Enum.empty?(successes) do
      {:error, "No characters processed successfully"}
    else
      # Calculate totals from successful results
      total_processed = Enum.reduce(successes, 0, fn {:ok, %{processed: p}}, acc -> acc + p end)
      total_persisted = Enum.reduce(successes, 0, fn {:ok, %{persisted: p}}, acc -> acc + p end)

      # Calculate percentage of processed kills that were actually persisted (new)
      persisted_percentage =
        if total_processed > 0 do
          Float.round(total_persisted / total_processed * 100, 1)
        else
          0.0
        end

      successful_characters = length(successes)
      failed_characters = length(tracked_characters) - successful_characters

      # Add intermediate progress info
      @logger.processor_info(
        "Character processing completed",
        success_rate:
          "#{Float.round(successful_characters / length(tracked_characters) * 100, 1)}%",
        successful: successful_characters,
        failed: failed_characters,
        total: length(tracked_characters)
      )

      # Log summary of success with more details
      @logger.processor_info(
        "Summary of killmail fetch process",
        characters_processed: successful_characters,
        characters_attempted: length(tracked_characters),
        kills_processed: total_processed,
        new_kills_persisted: total_persisted,
        already_existing_kills: total_processed - total_persisted,
        new_kills_percentage: "#{persisted_percentage}%"
      )

      {:ok,
       %{
         processed: total_processed,
         persisted: total_persisted,
         characters: successful_characters
       }}
    end
  end

  # Private helper functions

  # Process kills returned from ZKill API
  defp process_kills({:ok, kills}, character_id) when is_list(kills) do
    @logger.processor_info("Processing kills for character",
      character_id: character_id,
      kill_count: length(kills)
    )

    processed_results =
      kills
      |> Enum.map(fn kill ->
        process_single_kill(kill, character_id)
      end)
      |> Enum.filter(&match?({:ok, _}, &1))

    processed_count = length(processed_results)
    persisted_count = processed_count

    @logger.processor_info("Completed processing kills for character",
      character_id: character_id,
      processed: processed_count,
      persisted: persisted_count
    )

    {:ok, %{processed: processed_count, persisted: persisted_count}}
  end

  defp process_kills({:error, reason}, character_id) do
    @logger.processor_error("Failed to process kills for character",
      character_id: character_id,
      reason: inspect(reason)
    )

    {:error, reason}
  end

  # Get ESI data for a killmail using shared ESI service
  defp get_esi_data(kill_id, kill_hash) do
    # Return error if kill_hash is nil
    if is_nil(kill_hash) do
      @logger.processor_warn("Kill is missing hash", kill_id: kill_id)
      {:error, :missing_kill_hash}
    else
      get_esi_data_with_hash(kill_id, kill_hash)
    end
  end

  # Get ESI data when we have a valid hash
  defp get_esi_data_with_hash(kill_id, kill_hash) do
    cache_key = "esi:killmail:#{kill_id}"

    if @cache_repo.exists?(cache_key) do
      # Use cached data
      @logger.processor_debug("Using cached ESI data for kill", kill_id: kill_id)
      {:ok, @cache_repo.get(cache_key)}
    else
      # Fetch data from ESI
      fetch_esi_data(kill_id, kill_hash, cache_key)
    end
  end

  # Fetch ESI data from the API
  defp fetch_esi_data(kill_id, kill_hash, cache_key) do
    # Throttle ESI requests
    throttle_request()

    # Use the shared ESI service
    @logger.processor_debug("Fetching ESI data for kill", kill_id: kill_id)

    case @esi_service.get_killmail(kill_id, kill_hash) do
      {:ok, esi_data} ->
        # Cache the ESI data
        @cache_repo.set(cache_key, esi_data, @cache_ttl_seconds)
        {:ok, esi_data}

      {:error, reason} = error ->
        @logger.api_error(
          "Failed to get ESI data for kill",
          kill_id: kill_id,
          error: inspect(reason)
        )

        error
    end
  end

  # Apply rate limiting between requests
  defp throttle_request do
    Process.sleep(@rate_limit_ms)
  end

  @doc """
  Gets kills for a character within a specified date range.

  ## Parameters
    - character_id: The character ID to fetch kills for
    - opts: Keyword list of options
      - :from - Start date (required)
      - :to - End date (required)

  ## Returns
    - {:ok, [kills]} on success where kills is a list of processed killmail data
    - {:error, reason} if fetching or processing fails
  """
  @spec get_kills_for_character(integer(), Keyword.t()) :: {:ok, list(map())} | {:error, term()}
  def get_kills_for_character(character_id, opts \\ []) do
    from = Keyword.get(opts, :from, Date.utc_today())
    to = Keyword.get(opts, :to, Date.utc_today())

    @logger.debug(
      "[CHARACTER_KILLS] Fetching kills for character #{character_id} from #{from} to #{to}"
    )

    case @zkill_client.get_character_kills(character_id, 25, 1) do
      {:error, error} ->
        @logger.error("[CHARACTER_KILLS] ZKillboard API error: #{inspect(error)}")
        {:error, :api_error}

      {:ok, kills} when is_list(kills) ->
        @logger.debug("[CHARACTER_KILLS] Got #{length(kills)} kills from ZKillboard")
        filtered_kills = filter_kills_by_date_range(kills, from, to)

        @logger.debug(
          "[CHARACTER_KILLS] Filtered to #{length(filtered_kills)} kills within date range"
        )

        case process_character_kills(filtered_kills) do
          {:ok, processed_kills} -> {:ok, processed_kills}
          {:error, :api_error} -> {:error, :api_error}
        end
    end
  end

  defp filter_kills_by_date_range(kills, from, to) do
    @logger.debug("[CHARACTER_KILLS] Filtering #{length(kills)} kills between #{from} and #{to}")

    kills
    |> Enum.filter(fn kill ->
      case DateTime.from_iso8601(kill["killmail_time"]) do
        {:ok, kill_time, _} ->
          kill_date = DateTime.to_date(kill_time)

          Date.compare(kill_date, from) in [:eq, :gt] and
            Date.compare(kill_date, to) in [:eq, :lt]

        error ->
          @logger.warn("[CHARACTER_KILLS] Invalid kill time format: #{inspect(error)}")
          false
      end
    end)
  end

  defp process_character_kills([]), do: {:ok, []}

  defp process_character_kills(kills) do
    @logger.debug("[CHARACTER_KILLS] Processing #{length(kills)} kills")

    processed_kills =
      Enum.reduce_while(kills, [], fn kill, acc ->
        case process_single_kill(kill) do
          {:ok, processed_kill} ->
            {:cont, [processed_kill | acc]}

          {:error, :api_error} ->
            {:halt, :api_error}

          {:error, reason} ->
            @logger.warn("[CHARACTER_KILLS] Failed to process kill: #{inspect(reason)}")
            {:cont, acc}
        end
      end)

    case processed_kills do
      :api_error -> {:error, :api_error}
      kills when is_list(kills) -> {:ok, Enum.reverse(kills)}
    end
  end

  defp process_single_kill(kill) do
    @logger.debug("[CHARACTER_KILLS] Processing kill: #{inspect(kill["killmail_id"])}")

    with {:ok, victim} <- @esi_service.get_character(kill["victim"]["character_id"]),
         {:ok, ship} <- @esi_service.get_type(kill["victim"]["ship_type_id"]) do
      {:ok,
       %{
         id: kill["killmail_id"],
         time: kill["killmail_time"],
         victim_name: victim["name"],
         ship_name: ship["name"]
       }}
    else
      {:error, reason} ->
        @logger.error("[CHARACTER_KILLS] ESI API error: #{inspect(reason)}")
        {:error, :api_error}
    end
  end
end
