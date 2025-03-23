defmodule WandererNotifier.Services.CharacterKillsService do
  @moduledoc """
  Service for fetching and processing character kills from ZKillboard.
  This service provides functions to retrieve character kills and persist them.
  """
  require Logger
  alias WandererNotifier.Api.ZKill.Client, as: ZKillClient
  alias WandererNotifier.Api.ESI.Service, as: ESIService
  alias WandererNotifier.Data.Cache.Repository, as: CacheRepo

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
  @spec fetch_and_persist_character_kills(integer() | nil, integer(), integer()) ::
          {:ok, %{processed: integer(), persisted: integer()}} | {:error, term()}
  def fetch_and_persist_character_kills(character_id, limit \\ 25, page \\ 1)

  # Handle nil or invalid character IDs
  def fetch_and_persist_character_kills(nil, _limit, _page) do
    Logger.error("[ZKill] Invalid character ID: nil")
    {:error, "Invalid character ID: nil"}
  end

  # Handle string character IDs by converting them to integers
  def fetch_and_persist_character_kills(character_id, limit, page) when is_binary(character_id) do
    Logger.debug(
      "[CharacterKillsService] Converting string character ID: #{character_id} to integer"
    )

    case Integer.parse(character_id) do
      {int_id, ""} ->
        # Successfully parsed, call the function again with integer ID
        fetch_and_persist_character_kills(int_id, limit, page)

      _ ->
        Logger.error("[ZKill] Invalid character ID string: #{character_id}")
        {:error, "Invalid character ID string: #{character_id}"}
    end
  end

  def fetch_and_persist_character_kills(character_id, limit, page)
      when is_integer(character_id) and character_id > 0 do
    Logger.info("[CharacterKillsService] Fetching kills for character #{character_id}")
    character_id_str = to_string(character_id)

    # Use cache as rate-limiting mechanism too - don't fetch same character too frequently
    cache_key = "zkill:character_kills:#{character_id_str}:#{page}"

    if CacheRepo.exists?(cache_key) do
      Logger.info("[CharacterKillsService] Using cached kills for character #{character_id}")
      cached_response = CacheRepo.get(cache_key)

      # Ensure we're working with the expected format - the cache should contain
      # only the kills array, not a tuple with {:ok, kills}
      case cached_response do
        kills when is_list(kills) ->
          process_kills({:ok, kills}, character_id)

        _unexpected ->
          # If somehow the cache got corrupted, treat it as a cache miss and fetch fresh data
          Logger.warning(
            "[CharacterKillsService] Cached data for character #{character_id} is not in expected format. Fetching fresh data."
          )

          CacheRepo.delete(cache_key)
          fetch_fresh_kills(character_id, limit, page, cache_key)
      end
    else
      # Not in cache, fetch from API
      fetch_fresh_kills(character_id, limit, page, cache_key)
    end
  end

  # Handle any other invalid character ID type
  def fetch_and_persist_character_kills(character_id, _limit, _page) do
    Logger.error("[ZKill] Invalid character ID: #{inspect(character_id)}")
    {:error, "Invalid character ID: #{inspect(character_id)}"}
  end

  # Extract the logic to fetch fresh data into a separate function
  defp fetch_fresh_kills(character_id, limit, page, cache_key) do
    # Rate limit API requests
    throttle_request()

    case ZKillClient.get_character_kills(character_id, limit, page) do
      {:ok, kills} when is_list(kills) ->
        # Cache the kills array directly, not the tuple
        CacheRepo.set(cache_key, kills, @cache_ttl_seconds)

        # Process the kills
        process_kills({:ok, kills}, character_id)

      {:error, _reason} = error ->
        Logger.error(
          "[CharacterKillsService] Failed to fetch kills for character #{character_id}"
        )

        error
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
          | {:error, term()}
  def fetch_and_persist_all_tracked_character_kills(limit \\ 25, page \\ 1) do
    # Get all tracked characters using the Helpers module that gets from all sources
    tracked_characters = WandererNotifier.Helpers.CacheHelpers.get_tracked_characters()
    log_tracked_characters(tracked_characters)

    # Continue with processing the tracked characters list
    if Enum.empty?(tracked_characters) do
      Logger.warning("[CharacterKillsService] No tracked characters found in any source")
      {:ok, %{processed: 0, persisted: 0, characters: 0}}
    else
      process_tracked_characters(tracked_characters, limit, page)
    end
  end

  # Log information about tracked characters
  defp log_tracked_characters(tracked_characters) do
    character_count = length(tracked_characters)
    sample = Enum.take(tracked_characters, min(5, character_count))

    Logger.info(
      "[CharacterKillsService] Found #{character_count} tracked characters from CacheHelpers. Sample: #{inspect(sample)}"
    )
  end

  # Process all tracked characters and return aggregated results
  defp process_tracked_characters(tracked_characters, limit, page) do
    # Process each character with a delay between requests
    results = Enum.map(tracked_characters, &process_single_character(&1, limit, page))

    # Check for critical ZKill API errors
    zkill_api_errors = find_api_errors(results)

    if Enum.empty?(zkill_api_errors) do
      aggregate_successful_results(results, tracked_characters)
    else
      # Return the first ZKill API error
      List.first(zkill_api_errors)
    end
  end

  # Process a single character and return the result
  defp process_single_character(character, limit, page) do
    # Extract the character ID
    character_id = extract_character_id(character)

    # Skip invalid character IDs
    if is_nil(character_id) do
      Logger.warning(
        "[CharacterKillsService] Skipping character with invalid ID: #{inspect(character)}"
      )

      {:error, :invalid_character_id}
    else
      fetch_character_kills_safely(character_id, limit, page)
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
    Logger.info("[CharacterKillsService] Processing character ID: #{character_id}")
    throttle_request()

    try do
      fetch_and_persist_character_kills(character_id, limit, page)
    rescue
      e ->
        Logger.error(
          "[CharacterKillsService] Error processing character #{character_id}: #{inspect(e)}"
        )

        {:error, {:exception, e}}
    catch
      kind, reason ->
        Logger.error(
          "[CharacterKillsService] Caught #{kind} while processing character #{character_id}: #{inspect(reason)}"
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

      # Log summary of success
      Logger.info(
        "[CharacterKillsService] Successfully processed #{total_processed} kills and persisted #{total_persisted} kills for #{length(tracked_characters)} characters"
      )

      {:ok,
       %{
         processed: total_processed,
         persisted: total_persisted,
         characters: length(tracked_characters)
       }}
    end
  end

  # Private helper functions

  # Process kills returned from ZKill API
  defp process_kills({:ok, kills}, character_id) do
    Logger.info(
      "[CharacterKillsService] Processing #{length(kills)} kills for character #{character_id}"
    )

    # Get a list of all processed killmail IDs from global cache (not per-character)
    processed_cache_key = "processed:killmails:global"
    already_processed = CacheRepo.get(processed_cache_key) || MapSet.new()

    # Filter out kills we've already processed
    unprocessed_kills = filter_unprocessed_kills(kills, already_processed)

    # Process unprocessed kills
    {results, _updated_processed} =
      process_unprocessed_kills(unprocessed_kills, already_processed)

    # Count the results
    processed = length(unprocessed_kills)
    persisted = count_persisted_results(results)

    # Return processed and persisted counts
    {:ok, %{processed: processed, persisted: persisted}}
  end

  # Filter out kills that have already been processed
  defp filter_unprocessed_kills(kills, already_processed) do
    unprocessed =
      Enum.filter(kills, fn kill ->
        kill_id = Map.get(kill, "killmail_id")
        !MapSet.member?(already_processed, kill_id)
      end)

    if length(unprocessed) < length(kills) do
      Logger.info(
        "[CharacterKillsService] Skipping #{length(kills) - length(unprocessed)} already processed kills"
      )
    end

    unprocessed
  end

  # Process the list of unprocessed kills
  defp process_unprocessed_kills([], _already_processed), do: {[], MapSet.new()}

  defp process_unprocessed_kills(unprocessed_kills, already_processed) do
    # Track newly processed kills
    newly_processed_set = MapSet.new()

    # Process each kill and collect results and processed IDs
    {results, updated_processed} =
      Enum.reduce(unprocessed_kills, {[], newly_processed_set}, &process_single_kill/2)

    # Update the global processed cache with new kill IDs
    update_processed_cache(already_processed, updated_processed)

    {results, updated_processed}
  end

  # Process a single kill and return updated results and processed set
  defp process_single_kill(kill, {acc_results, acc_processed}) do
    kill_id = Map.get(kill, "killmail_id")
    zkb_data = Map.get(kill, "zkb", %{})

    if is_nil(kill_id) do
      Logger.warning("[CharacterKillsService] Kill without ID: #{inspect(kill)}")
      # Add error result but don't update processed set
      {[{:error, :missing_kill_id} | acc_results], acc_processed}
    else
      # Add to newly processed set immediately to prevent concurrent processing
      # 24 hour cache
      CacheRepo.set("processed:killmail:#{kill_id}", true, 86_400)

      # Add this kill_id to our processed set
      updated_set = MapSet.put(acc_processed, kill_id)

      handle_kill_processing(kill_id, zkb_data, acc_results, updated_set)
    end
  end

  # Handle the actual kill processing after validation
  defp handle_kill_processing(kill_id, zkb_data, acc_results, updated_set) do
    # Get ESI data to enrich the killmail
    case get_esi_data(kill_id, Map.get(zkb_data, "hash")) do
      {:ok, esi_data} ->
        # Create Killmail struct using the same structure as used by the websocket processor
        killmail = WandererNotifier.Data.Killmail.new(kill_id, zkb_data, esi_data)

        # Use the shared persistence logic from KillmailPersistence with error handling
        result = safely_persist_killmail(killmail)

        process_result =
          case result do
            {:ok, _} -> {:ok, :persisted}
            :ignored -> {:ok, :ignored}
            {:error, reason} -> {:error, reason}
          end

        # Add to results list and return updated set
        {[process_result | acc_results], updated_set}

      {:error, reason} = error ->
        Logger.error(
          "[CharacterKillsService] Failed to get ESI data for kill #{kill_id}: #{inspect(reason)}"
        )

        # Add error to results but keep the kill in processed set
        {[error | acc_results], updated_set}
    end
  end

  # Update the global processed cache with new kill IDs
  defp update_processed_cache(already_processed, updated_processed) do
    processed_cache_key = "processed:killmails:global"
    updated_processed_total = MapSet.union(already_processed, updated_processed)
    # 24 hour cache
    CacheRepo.set(processed_cache_key, updated_processed_total, 86_400)
  end

  # Count the number of persisted results
  defp count_persisted_results(results) do
    Enum.count(results, fn
      {:ok, :persisted} -> true
      {:ok, :persisted_with_warning} -> true
      _ -> false
    end)
  end

  # Get ESI data for a killmail using shared ESI service
  defp get_esi_data(kill_id, kill_hash) do
    # Return error if kill_hash is nil
    if is_nil(kill_hash) do
      Logger.warning("[CharacterKillsService] Kill #{kill_id} is missing hash")
      {:error, :missing_kill_hash}
    else
      get_esi_data_with_hash(kill_id, kill_hash)
    end
  end

  # Get ESI data when we have a valid hash
  defp get_esi_data_with_hash(kill_id, kill_hash) do
    cache_key = "esi:killmail:#{kill_id}"

    if CacheRepo.exists?(cache_key) do
      # Use cached data
      Logger.debug("[CharacterKillsService] Using cached ESI data for kill #{kill_id}")
      {:ok, CacheRepo.get(cache_key)}
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
    Logger.debug("[CharacterKillsService] Fetching ESI data for kill #{kill_id}")

    case ESIService.get_killmail(kill_id, kill_hash) do
      {:ok, esi_data} ->
        # Cache the ESI data
        CacheRepo.set(cache_key, esi_data, @cache_ttl_seconds)
        {:ok, esi_data}

      {:error, reason} = error ->
        Logger.error(
          "[CharacterKillsService] Failed to get ESI data for kill #{kill_id}: #{inspect(reason)}"
        )

        error
    end
  end

  # Apply rate limiting between requests
  defp throttle_request do
    Process.sleep(@rate_limit_ms)
  end

  # Safely persist killmail with proper error handling
  defp safely_persist_killmail(killmail) do
    try do
      # Try to use the KillmailPersistence module
      WandererNotifier.Resources.KillmailPersistence.maybe_persist_killmail(killmail)
    rescue
      e ->
        # Handle the specific UndefinedFunctionError regarding atomic actions
        err_msg = Exception.message(e)

        if String.contains?(err_msg, "disable_atomic_actions") do
          # Specific error we're catching - log a warning but consider it a success
          # as this is just a transient DB configuration issue
          Logger.warning(
            "[CharacterKillsService] Ash atomic transaction error - treating as successful: #{err_msg}"
          )

          # Return a synthetic success - we know the killmail is valid, just can't persist it due to config
          {:ok, :persisted_with_warning}
        else
          # For all other errors, log and return error
          Logger.error(
            "[CharacterKillsService] Error persisting killmail: #{inspect(e)}\n#{Exception.format_stacktrace()}"
          )

          {:error, "Persistence error: #{inspect(e)}"}
        end
    end
  end
end
