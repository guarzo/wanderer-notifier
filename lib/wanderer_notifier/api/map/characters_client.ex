alias WandererNotifier.Api.Http.Client
alias WandererNotifier.Api.Map.UrlBuilder
alias WandererNotifier.Config.{Application, Cache}
alias WandererNotifier.Config.Config
alias WandererNotifier.Data.Cache.Keys, as: CacheKeys
alias WandererNotifier.Data.Cache.Repository, as: CacheRepo
alias WandererNotifier.Data.Character
alias WandererNotifier.Data.Repo
alias WandererNotifier.Logger.Logger, as: AppLogger
alias WandererNotifier.Notifiers.Factory, as: NotifierFactory
alias WandererNotifier.Notifiers.StructuredFormatter
alias WandererNotifier.Resources.TrackedCharacter

defmodule WandererNotifier.Api.Map.CharactersClient do
  @moduledoc """
  Client for retrieving and processing character data from the map API.

  This module follows the API Data Standardization principles:
  1. Single Source of Truth: Uses Character struct as the canonical representation
  2. Early Conversion: Converts API responses to Character structs immediately
  3. No Silent Renaming: Preserves field names consistently
  4. No Defensive Fallbacks: Handles errors explicitly
  5. Clear Contracts: Has explicit input/output contracts
  6. Explicit Error Handling: Fails fast with clear error messages
  7. Consistent Access Patterns: Uses the Access behavior for all struct access
  """

  @doc """
  Updates the tracked characters information in the cache.

  If cached_characters is provided, it will also identify and notify about new characters.

  ## Parameters
    - cached_characters: Optional list of cached characters for comparison

  ## Returns
    - {:ok, [Character.t()]} on success with a list of Character structs
    - {:error, {:json_parse_error, reason}} if JSON parsing fails
    - {:error, {:http_error, reason}} if HTTP request fails
    - {:error, {:domain_error, :map, reason}} for domain-specific errors
  """
  @spec update_tracked_characters([Character.t()] | nil) ::
          {:ok, [Character.t()]} | {:error, term()}
  def update_tracked_characters(cached_characters \\ nil) do
    # Ensure cached_characters is a list using our helper function
    cached_characters_safe = Character.ensure_list(cached_characters)

    with {:ok, _} <- check_characters_endpoint_availability(),
         {:ok, url} <- UrlBuilder.build_url("map/characters"),
         {:ok, body} <- fetch_characters_data(url) do
      handle_character_response(body, cached_characters_safe)
    else
      {:error, {:http_error, _}} = error ->
        error

      {:error, reason} = error ->
        if is_tuple(reason) and tuple_size(reason) == 3 and elem(reason, 0) == :domain_error do
          error
        else
          AppLogger.api_error("⚠️ Failed to update characters", error: inspect(reason))
          error
        end
    end
  end

  # Fetch character data from the API
  defp fetch_characters_data(url) do
    headers = UrlBuilder.get_auth_headers()

    # Use HTTP client with built-in retry logic for rate limits
    # Setting max_retries high and enabling rate_limit_aware
    case Client.get(url, headers, rate_limit_aware: true, max_retries: 10) do
      {:ok, %{status_code: 200, body: body}} when is_binary(body) ->
        # Only return success for status 200 with non-empty body
        if String.trim(body) == "" do
          AppLogger.api_warn(
            "⚠️ Got empty body with 200 status - treating as potential rate limit"
          )

          {:error, {:http_error, :empty_body}}
        else
          {:ok, body}
        end

      # Catch specific rate limit errors
      {:error, :rate_limited} ->
        AppLogger.api_warn("⚠️ Characters endpoint reported rate limiting")
        {:error, {:http_error, :rate_limited}}

      # Explicitly handle other status codes to avoid pattern match errors
      {:ok, %{status_code: status_code}} when status_code != 200 ->
        AppLogger.api_warn("⚠️ Characters endpoint returned unexpected status: #{status_code}")
        {:error, {:http_error, status_code}}

      # Catch all other errors
      {:error, reason} ->
        AppLogger.api_error("⚠️ HTTP request failed", error: inspect(reason))
        {:error, {:http_error, reason}}
    end
  end

  # Extract the Retry-After header if present
  defp extract_retry_after(headers) do
    retry_header =
      Enum.find(headers, fn {header_name, _} ->
        String.downcase(header_name) == "retry-after"
      end)

    case retry_header do
      {_, value} ->
        # Try to parse as integer seconds
        case Integer.parse(value) do
          # Convert to milliseconds
          {seconds, _} -> seconds * 1000
          :error -> nil
        end

      nil ->
        nil
    end
  end

  @doc """
  Handles successful character response from the API.
  Parses the JSON, validates the data, and processes the characters.

  ## Parameters
    - body: Raw JSON response body
    - cached_characters: Optional list of cached characters for comparison

  ## Returns
    - {:ok, [Character.t()]} on success with a list of Character structs
    - {:error, {:json_parse_error, reason}} if JSON parsing fails
  """
  @spec handle_character_response(String.t(), [Character.t()] | nil) ::
          {:ok, [Character.t()]} | {:error, {:json_parse_error, term()}}
  def handle_character_response(body, cached_characters) when is_binary(body) do
    # First verify the body is not empty (which could indicate rate limiting)
    if String.trim(body) == "" do
      AppLogger.api_warn("⚠️ Empty response body received - this may indicate rate limiting")
      {:error, {:possible_rate_limit, "Empty response body"}}
    else
      # Proceed with normal JSON parsing
      case Jason.decode(body) do
        {:ok, parsed_json} ->
          process_parsed_character_data(parsed_json, cached_characters)

        {:error, reason} ->
          AppLogger.api_error("⚠️ Failed to parse JSON", error: inspect(reason))
          {:error, {:json_parse_error, reason}}
      end
    end
  rescue
    e ->
      AppLogger.api_error("⚠️ Unexpected error in handle_character_response",
        error: Exception.message(e),
        stacktrace: Exception.format_stacktrace()
      )

      {:error, {:unexpected_error, e}}
  end

  # Process parsed JSON data and extract character information
  defp process_parsed_character_data(parsed_json, cached_characters) do
    # Extract characters data with fallbacks for different API formats
    characters_data = extract_characters_data(parsed_json)
    characters = convert_to_character_structs(characters_data)
    tracked_characters = Enum.filter(characters, & &1.tracked)

    # Cache the characters and handle persistence and notifications
    process_tracked_characters(tracked_characters, cached_characters)

    # Return success with tracked characters
    {:ok, tracked_characters}
  end

  # Extract character data from different JSON structures
  defp extract_characters_data(parsed_json) do
    case parsed_json do
      %{"data" => data} when is_list(data) -> data
      %{"characters" => chars} when is_list(chars) -> chars
      data when is_list(data) -> data
      _ -> []
    end
  end

  # Convert raw character data to Character structs
  defp convert_to_character_structs(characters_data) do
    characters_data
    |> Enum.map(fn raw_char_data ->
      try do
        # First standardize the data
        standardized_data = standardize_character_data(raw_char_data)

        # Create a Character struct from the standardized data
        Character.new(standardized_data)
      rescue
        e ->
          AppLogger.api_error(
            "[CharactersClient] Failed to parse character: #{Exception.message(e)}"
          )

          AppLogger.api_error("[CharactersClient] Character data: #{inspect(raw_char_data)}")

          nil
      end
    end)
    |> Enum.reject(&is_nil/1)
  end

  # Standardize character data before conversion to struct
  defp standardize_character_data(raw_char_data) do
    cond do
      has_nested_eve_id?(raw_char_data) -> raw_char_data
      has_top_level_eve_id?(raw_char_data) -> raw_char_data
      has_only_character_id?(raw_char_data) -> handle_missing_eve_id(raw_char_data)
      is_map(raw_char_data) -> handle_missing_required_fields(raw_char_data)
      true -> handle_invalid_data_type(raw_char_data)
    end
  end

  # Check if the data has a nested character with eve_id
  defp has_nested_eve_id?(data) do
    is_map(data) &&
      Map.has_key?(data, "character") &&
      is_map(data["character"]) &&
      Map.has_key?(data["character"], "eve_id")
  end

  # Check if the data has a top-level eve_id field
  defp has_top_level_eve_id?(data) do
    is_map(data) && Map.has_key?(data, "eve_id")
  end

  # Check if the data only has character_id but not eve_id
  defp has_only_character_id?(data) do
    is_map(data) && Map.has_key?(data, "character_id")
  end

  # Handle data with character_id but missing eve_id
  defp handle_missing_eve_id(data) do
    # Log detailed info about problematic data structure
    AppLogger.api_warn(
      "[CharactersClient] Character data has UUID character_id but no eve_id: #{inspect(data)}"
    )

    # Don't try to fix or modify the data - let Character.new raise an appropriate error
    data
  end

  # Handle map data missing required fields
  defp handle_missing_required_fields(data) do
    # Log available keys for debugging
    AppLogger.api_warn(
      "[CharactersClient] Character data missing required fields. " <>
        "Available keys: #{inspect(Map.keys(data))}"
    )

    # Include all data to help debugging
    AppLogger.api_debug("[CharactersClient] Raw character data: #{inspect(data)}")

    # This will result in an error in Character.new, which is what we want
    data
  end

  # Handle invalid data type (non-map)
  defp handle_invalid_data_type(data) do
    AppLogger.api_warn("[CharactersClient] Unexpected character data type: #{inspect(data)}")

    # Let Character.new handle the error
    data
  end

  # Process tracked characters - cache, persist and notify
  defp process_tracked_characters(tracked_characters, cached_characters) do
    # Cache the characters
    cache_ttl = Cache.characters_cache_ttl()

    try do
      # Cache individual characters and build the list
      tracked_characters_list =
        Enum.reduce(tracked_characters, [], fn char, acc ->
          cache_character(char, cache_ttl, acc)
        end)

      # Cache the main character list only after all individual characters are processed
      # Ensure the list is in the same order as the input
      tracked_characters_list = Enum.reverse(tracked_characters_list)
      CacheRepo.set(CacheKeys.character_list(), tracked_characters_list, cache_ttl)

      AppLogger.api_debug(
        "[CharactersClient] Cached main character list with #{length(tracked_characters_list)} characters"
      )

      # Also update the map:characters key for backward compatibility
      CacheRepo.set("map:characters", tracked_characters_list, cache_ttl)
      AppLogger.api_debug("[CharactersClient] Updated map:characters cache for compatibility")

      # Handle persistence and notifications
      handle_character_persistence(tracked_characters_list)
      handle_character_notifications(tracked_characters_list, cached_characters)
    rescue
      e ->
        AppLogger.api_error(
          "[CharactersClient] Error in process_tracked_characters: #{Exception.message(e)}"
        )

        AppLogger.api_error("[CharactersClient] #{Exception.format_stacktrace()}")
        # Let it crash - the supervisor will handle restart if needed
        reraise e, __STACKTRACE__
    end
  end

  # Cache a single character and return updated accumulator
  defp cache_character(char, cache_ttl, acc) do
    if character_id = char.character_id do
      # Cache individual character
      CacheRepo.set(CacheKeys.character(character_id), char, cache_ttl)
      AppLogger.api_debug("[CharactersClient] Cached character #{character_id}")

      # Mark as tracked
      CacheRepo.set(CacheKeys.tracked_character(character_id), true, cache_ttl)
      AppLogger.api_debug("[CharactersClient] Marked character #{character_id} as tracked")

      # Add to list only if successfully cached
      [char | acc]
    else
      acc
    end
  end

  # Separate function to handle character persistence with isolated error handling
  defp handle_character_persistence(tracked_characters) do
    persistence_config = Application.get_env(:wanderer_notifier, :persistence, [])
    kill_charts_enabled = Keyword.get(persistence_config, :enabled)
    map_charts_enabled = Application.get_env(:wanderer_notifier, :wanderer_feature_map_charts)

    # Only continue if either kill charts or map charts are enabled
    if kill_charts_enabled || map_charts_enabled do
      # Check if the repo is started, and if not, try waiting for it
      ensure_database_available_and_persist(tracked_characters)
    else
      AppLogger.api_debug(
        "[CharactersClient] Database features disabled, skipping character persistence"
      )

      # Return empty result
      return_empty_sync_result()
    end
  rescue
    e ->
      # Log detailed error but don't propagate it
      AppLogger.api_error(
        "[CharactersClient] Exception persisting characters: #{Exception.message(e)}"
      )

      # Log the exact error location for debugging
      AppLogger.api_error("[CharactersClient] Stacktrace: #{Exception.format_stacktrace()}")
  end

  # Ensure database is available and persist characters if so
  defp ensure_database_available_and_persist(tracked_characters) do
    # Check if the repo is started, wait if needed
    if !repo_started?() do
      wait_for_database_connection()
    end

    # After waiting, verify the repo is started
    if repo_started?() do
      persist_characters_to_database(tracked_characters)
    else
      AppLogger.api_warn(
        "[CharactersClient] Database repository not started, character persistence skipped"
      )

      return_empty_sync_result()
    end
  end

  # Wait for the database to become available
  defp wait_for_database_connection do
    # Wait up to 3 seconds for database to become available
    wait_result =
      Enum.reduce_while(1..3, false, fn attempt, _ ->
        Process.sleep(500)

        if repo_started?() do
          {:halt, true}
        else
          handle_failed_connection_attempt(attempt)
        end
      end)

    AppLogger.api_debug("🔄 Database connection wait result: #{inspect(wait_result)}")
  end

  # Handle a failed connection attempt
  defp handle_failed_connection_attempt(attempt) do
    if attempt == 3 do
      # Final attempt failed
      AppLogger.api_warn("⚠️ Database connection not available after waiting")
      {:halt, false}
    else
      # Continue trying
      {:cont, false}
    end
  end

  # Persist characters to the database
  defp persist_characters_to_database(tracked_characters) do
    case TrackedCharacter.sync_from_characters(%{characters: tracked_characters}) do
      {:ok, _stats} ->
        :ok

      {:error, reason} ->
        AppLogger.api_error("⚠️ Failed to persist characters", error: inspect(reason))
    end
  end

  # Return an empty sync result for when database operations are disabled
  defp return_empty_sync_result do
    empty_stats = %{
      stats: %{total: 0, created: 0, updated: 0, unchanged: 0, errors: 0},
      errors: []
    }

    AppLogger.api_debug(
      "[CharactersClient] Returning empty sync result due to disabled database operations"
    )

    {:ok, empty_stats}
  end

  # Helper function to check if the repo is started and provide diagnostics
  defp repo_started? do
    # Check if the repo process exists
    pid = Process.whereis(Repo)

    cond do
      is_pid(pid) && Process.alive?(pid) ->
        # Repo process exists and is alive, perform a simple query test
        check_database_connectivity(pid)

      is_pid(pid) ->
        AppLogger.api_warn("[CharactersClient] Database repo process exists but is not alive")
        false

      true ->
        log_repo_missing_diagnostics()
        false
    end
  rescue
    e ->
      AppLogger.api_error(
        "[CharactersClient] Error checking database connection: #{Exception.message(e)}"
      )

      false
  catch
    type, value ->
      AppLogger.api_error(
        "[CharactersClient] Caught #{inspect(type)} while checking database: #{inspect(value)}"
      )

      false
  end

  # Check if database is actually connectable
  defp check_database_connectivity(_pid) do
    case Repo.health_check() do
      {:ok, ping_time} ->
        AppLogger.api_debug(
          "[CharactersClient] Database connection is healthy (ping: #{ping_time}ms)"
        )

        true

      {:error, reason} ->
        AppLogger.api_warn(
          "[CharactersClient] Database connection exists but health check failed: #{inspect(reason)}"
        )

        false
    end
  end

  # Log detailed diagnostics when the repo is missing
  defp log_repo_missing_diagnostics do
    # Check if repo module is defined
    if Code.ensure_loaded?(Repo) do
      AppLogger.api_warn(
        "[CharactersClient] Database repo module exists but process not started. " <>
          "This often indicates the repo failed to connect during startup."
      )
    else
      AppLogger.api_warn("[CharactersClient] Database repo module is not available.")
    end

    # Log database configuration for diagnostics
    log_database_config()
  end

  # Log database configuration details to help with troubleshooting
  defp log_database_config do
    db_config = get_db_config()

    if is_nil(db_config) do
      AppLogger.api_error("[CharactersClient] Database configuration is missing")
    else
      host = db_config[:hostname] || "unknown"
      port = db_config[:port] || "unknown"
      db = db_config[:database] || "unknown"
      user = db_config[:username] || "unknown"

      AppLogger.api_debug(
        "[CharactersClient] Database configuration: #{user}@#{host}:#{port}/#{db}"
      )
    end
  end

  defp get_db_config do
    case Application.get_repo_config() do
      {:ok, config} -> config
      _ -> %{}
    end
  end

  # Separate function to handle new character notifications with isolated error handling
  defp handle_character_notifications(tracked_characters, cached_characters) do
    notify_new_tracked_characters(tracked_characters, cached_characters)
  rescue
    e ->
      # Log but don't fail the overall operation
      AppLogger.api_error(
        "[CharactersClient] Error notifying new characters: #{Exception.message(e)}"
      )
  end

  @doc """
  Checks if the characters endpoint is available in the current map API.

  ## Returns
    - {:ok, true} if available
    - {:error, reason} if not available
  """
  @spec check_characters_endpoint_availability() :: {:ok, boolean()} | {:error, term()}
  def check_characters_endpoint_availability do
    case UrlBuilder.build_url("map/characters") do
      {:ok, url} ->
        headers = UrlBuilder.get_auth_headers()

        case Client.get(url, headers) do
          {:ok, %{status_code: status}} when status >= 200 and status < 300 ->
            {:ok, true}

          {:ok, %{status_code: 429, headers: headers}} ->
            # Handle rate limiting with backoff
            retry_after = extract_retry_after(headers)
            # Default to 5 seconds
            wait_time = retry_after || 5000

            AppLogger.api_warn(
              "⚠️ Characters endpoint rate limited. Retrying after #{wait_time}ms"
            )

            Process.sleep(wait_time)

            # Try again after waiting
            check_characters_endpoint_availability()

          {:ok, %{status_code: status, body: body}} ->
            error_reason = "Endpoint returned status #{status}: #{body}"
            AppLogger.api_warn("⚠️ Characters endpoint error", error: error_reason)
            {:error, error_reason}

          {:error, :rate_limited} ->
            # API recognized as rate limited from HTTP client
            AppLogger.api_warn("⚠️ Characters endpoint rate limited. Retrying after 5 seconds")
            Process.sleep(5000)
            check_characters_endpoint_availability()

          {:error, {:domain_error, _domain, :rate_limited}} ->
            # Domain-specific rate limiting from HTTP client
            AppLogger.api_warn(
              "⚠️ Characters endpoint domain-specific rate limited. Retrying after 5 seconds"
            )

            Process.sleep(5000)
            check_characters_endpoint_availability()

          {:error, reason} ->
            AppLogger.api_warn("⚠️ Characters endpoint not available", error: inspect(reason))
            {:error, reason}
        end

      {:error, reason} ->
        AppLogger.api_warn("⚠️ Characters endpoint not available", error: inspect(reason))
        {:error, reason}
    end
  end

  @doc """
  Retrieves character activity data from the map API.

  ## Parameters
    - slug: Optional map slug override

  ## Returns
    - {:ok, activity_data} on success
    - {:error, {:json_parse_error, reason}} if JSON parsing fails
    - {:error, {error_type, {:http_error, reason}}} if HTTP request fails
    - {:error, {:unexpected_error, message}} for unexpected errors
  """
  @spec get_character_activity(String.t() | nil) :: {:ok, list(map())} | {:error, term()}
  def get_character_activity(slug \\ nil) do
    # Call the 2-parameter version with default days=1
    get_character_activity(slug, 1)
  end

  @doc """
  Gets character activity data for the specified number of days.

  ## Parameters
    - slug: Optional map slug to override the default one
    - days: Number of days of activity to retrieve (default is 1)

  ## Returns
    - {:ok, activity_data} on success
    - {:error, reason} on failure
  """
  def get_character_activity(slug, days) when is_integer(days) do
    AppLogger.api_debug("[CharactersClient] Getting character activity for #{days} days")

    # Build URL for activity endpoint with days parameter
    case UrlBuilder.build_url("map/character-activity", %{days: days}, slug) do
      {:ok, url} ->
        AppLogger.api_debug("[CharactersClient] Activity URL: #{url}")

        case fetch_activity_data(url) do
          {:ok, body} -> parse_activity_data(body)
          error -> error
        end

      {:error, reason} ->
        AppLogger.api_error("[CharactersClient] Failed to build activity URL: #{inspect(reason)}")
        {:error, reason}
    end
  end

  # Fetch activity data from API
  defp fetch_activity_data(url) do
    headers = UrlBuilder.get_auth_headers()

    case Client.get(url, headers) do
      {:ok, %{status_code: 200, body: body}} when is_binary(body) ->
        {:ok, body}

      {:ok, %{status_code: status_code}} ->
        AppLogger.api_error("[CharactersClient] API returned non-200 status: #{status_code}")
        # Determine if this error is retryable
        error_type = if status_code >= 500, do: :retriable, else: :permanent
        {:error, {error_type, {:http_error, status_code}}}

      {:error, reason} ->
        AppLogger.api_error("[CharactersClient] HTTP request failed: #{inspect(reason)}")
        # Network errors are generally retryable
        {:error, {:retriable, {:http_error, reason}}}
    end
  end

  # Parse activity data from response body
  defp parse_activity_data(body) do
    case Jason.decode(body) do
      {:ok, parsed_json} ->
        # Log the raw parsed JSON for debugging
        AppLogger.api_debug(
          "[CharactersClient] Raw parsed JSON structure: #{inspect(parsed_json, pretty: true, limit: 5000)}"
        )

        # Extract and format activity data
        activity_data = extract_activity_data(parsed_json)

        AppLogger.api_debug(
          "[CharactersClient] Extracted activity data structure: #{inspect(activity_data, pretty: true, limit: 5000)}"
        )

        AppLogger.api_debug(
          "[CharactersClient] Parsed #{length(activity_data)} activity entries from API response"
        )

        {:ok, activity_data}

      {:error, reason} ->
        log_json_parse_error(body, reason)
        {:error, {:json_parse_error, reason}}
    end
  end

  # Extract activity data from parsed JSON with fallbacks for different formats
  defp extract_activity_data(parsed_json) do
    case parsed_json do
      %{"data" => data} when is_list(data) -> data
      %{"activity" => activity} when is_list(activity) -> activity
      data when is_list(data) -> data
      _ -> []
    end
  end

  # Log JSON parse error with sample of body
  defp log_json_parse_error(body, reason) do
    AppLogger.api_error("[CharactersClient] Failed to parse JSON: #{inspect(reason)}")

    AppLogger.api_debug(
      "[CharactersClient] Raw response body sample: #{String.slice(body, 0, 100)}..."
    )
  end

  @doc """
  Identifies new tracked characters and sends notifications.

  ## Parameters
    - new_characters: List of newly fetched tracked characters
    - cached_characters: List of previously cached characters

  ## Returns
    - {:ok, new_characters} on success with a list of new Character structs
      that were found and notified
    - {:ok, []} if no new characters or notifications are disabled
  """
  @spec notify_new_tracked_characters([Character.t()], [Character.t()] | nil) ::
          {:ok, [Character.t()]}
  def notify_new_tracked_characters(new_characters, cached_characters) do
    # Check if both tracking and notifications are enabled
    if Config.character_tracking_enabled?() && Config.character_notifications_enabled?() do
      # Ensure we have lists to work with
      new_chars = new_characters || []
      cached_chars = cached_characters || []

      # Find characters that are in new_chars but not in cached_chars
      added_characters = find_added_characters(new_chars, cached_chars)

      # Notify about added characters
      notify_characters(added_characters)
    else
      # Return early if tracking or notifications are disabled
      {:ok, []}
    end
  end

  # Find characters that exist in new list but not in cached list
  # No cached chars - first run, don't spam notifications
  defp find_added_characters(_new_chars, []), do: []

  defp find_added_characters(new_chars, cached_chars) do
    # Find characters by their character_id that are in new but not in cached
    new_char_ids = MapSet.new(new_chars, & &1.character_id)
    cached_char_ids = MapSet.new(cached_chars, & &1.character_id)

    # Get the difference (characters in new but not in cached)
    new_ids = MapSet.difference(new_char_ids, cached_char_ids)

    # Return the full character structs for new characters
    Enum.filter(new_chars, fn char -> MapSet.member?(new_ids, char.character_id) end)
  end

  # Send notifications for each new character
  # No new characters
  defp notify_characters([]), do: {:ok, []}

  defp notify_characters(added_characters) do
    AppLogger.api_debug(
      "[CharactersClient] Found #{length(added_characters)} new tracked characters"
    )

    Enum.each(added_characters, &send_character_notification_safely/1)

    {:ok, added_characters}
  end

  # Safely send a notification for a character, handling errors
  defp send_character_notification_safely(character) do
    send_character_notification(character)
  rescue
    e ->
      AppLogger.api_error(
        "[CharactersClient] Failed to send notification for new character: #{inspect(e)}"
      )
  end

  @doc """
  Sends a notification for a new tracked character.
  """
  def send_character_notification(%Character{} = character_data) do
    # Create and send notification
    generic_notification = StructuredFormatter.format_character_notification(character_data)
    discord_format = StructuredFormatter.to_discord_format(generic_notification)

    case NotifierFactory.notify(:send_discord_embed, [discord_format]) do
      :ok ->
        :ok

      {:ok, _} ->
        :ok

      {:error, reason} ->
        AppLogger.api_error("⚠️ Failed to send character notification", error: inspect(reason))
        {:error, reason}
    end
  end
end
