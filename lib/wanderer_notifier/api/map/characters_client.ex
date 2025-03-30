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
  alias WandererNotifier.Api.Http.Client
  alias WandererNotifier.Api.Map.Characters
  alias WandererNotifier.Api.Map.UrlBuilder
  alias WandererNotifier.Core.Config
  alias WandererNotifier.Data.Character
  alias WandererNotifier.Logger, as: AppLogger

  @doc """
  Updates tracked characters from the map API.

  ## Parameters
    - cached_characters: Optional list of cached characters

  ## Returns
    - {:ok, characters} on success
    - {:error, reason} on failure
  """
  def update_tracked_characters(cached_characters \\ nil) do
    # Build the URL for the characters endpoint
    AppLogger.api_debug("[DEBUG] Starting tracked characters update")

    try do
      # Build the URL and make the API request
      with {:ok, url} <- build_and_log_url(),
           {:ok, response} <- make_api_request(url) do
        # Process the API response
        process_character_response(response, cached_characters)
      else
        {:error, reason} -> handle_error(reason)
      end
    rescue
      e ->
        handle_exception(e, __STACKTRACE__)
    end
  end

  # Build and log the characters URL
  defp build_and_log_url do
    AppLogger.api_debug("[DEBUG] Building URL")

    case build_characters_url() do
      {:ok, url} = result ->
        # Log the URL being used
        AppLogger.api_debug("[DEBUG] URL built successfully: #{url}")
        result

      error ->
        AppLogger.api_error("[DEBUG] Failed to build characters URL: #{inspect(error)}")
        error
    end
  end

  # Process the API response
  defp process_character_response(response, cached_characters) do
    AppLogger.api_error("[CRITICAL] Response type before parse: #{type_of(response)}")

    # Check if response has valid status_code and body
    if Map.has_key?(response, :status_code) && Map.has_key?(response, :body) do
      process_response_with_status(response, cached_characters)
    else
      # Handle unexpected response format
      AppLogger.api_error(
        "[CRITICAL] Unexpected response format: #{inspect(response, limit: 200)}"
      )

      {:error, :invalid_response_format}
    end
  end

  # Process response with status code
  defp process_response_with_status(%{status_code: 200, body: body}, cached_characters) do
    # Pass the raw response body to Characters module for processing
    AppLogger.api_info("[CRITICAL] Delegating to Characters.update_tracked_characters")
    Characters.update_tracked_characters(body, cached_characters)
  end

  defp process_response_with_status(%{status_code: status}, _cached_characters) do
    # Handle non-200 responses
    AppLogger.api_error("[CRITICAL] API returned non-200 status: #{status}")
    {:error, {:api_error, status}}
  end

  # Handle errors from the URL building or API request
  defp handle_error(reason) do
    AppLogger.api_error("[DEBUG] Error in character update process: #{inspect(reason)}")
    {:error, reason}
  end

  # Handle exceptions in the update process
  defp handle_exception(e, stacktrace) do
    AppLogger.api_error("[DEBUG] Exception in update_tracked_characters: #{Exception.message(e)}")

    AppLogger.api_error("[DEBUG] Stack: #{Exception.format_stacktrace(stacktrace)}")
    {:error, {:exception, e}}
  end

  # Make a request to the map API
  defp make_api_request(url) do
    AppLogger.api_debug("[DEBUG] Starting HTTP request to #{url}")

    # Get authentication token
    token = Config.map_token()
    token_preview = if token, do: "#{String.slice(token, 0, 5)}...", else: "nil"
    AppLogger.api_info("[CharactersClient] Using auth token: #{token_preview}")

    # Set up headers
    headers = [
      {"Authorization", "Bearer #{token}"},
      {"Content-Type", "application/json"},
      {"Accept", "application/json"}
    ]

    # Log headers being sent (without sensitive information)
    AppLogger.api_debug("[DEBUG] Headers prepared: #{inspect(headers, sensitive: true)}")

    # Log equivalent curl command (redacted token for security)
    curl_cmd =
      "curl -X GET -H 'Authorization: Bearer #{token_preview}' -H 'Content-Type: application/json' -H 'Accept: application/json' '#{url}'"

    AppLogger.api_info("[CharactersClient] Equivalent curl: #{curl_cmd}")

    # Make the HTTP request - delegating to the HTTP client
    AppLogger.api_debug("[DEBUG] Calling Client.get NOW...")
    response = Client.get(url, headers)

    # Log response type and status
    response_info =
      case response do
        {:ok, %{status_code: status}} ->
          "Status: #{status}"

        %{status_code: status} ->
          "Unwrapped status: #{status}"

        {:error, reason} ->
          "Error: #{inspect(reason)}"

        other ->
          "Unknown format: #{inspect(other)}"
      end

    AppLogger.api_info("[CharactersClient] HTTP response: #{response_info}")
    AppLogger.api_debug("[DEBUG] Client.get returned: #{inspect(response, limit: 500)}")

    # Return response
    response
  rescue
    e ->
      stacktrace = __STACKTRACE__
      AppLogger.api_error("[DEBUG] Exception during API request: #{Exception.message(e)}")
      AppLogger.api_error("[DEBUG] Stack: #{Exception.format_stacktrace(stacktrace)}")
      {:error, {:exception, e}}
  catch
    kind, value ->
      stacktrace = __STACKTRACE__
      AppLogger.api_error("[DEBUG] #{kind} during API request: #{inspect(value)}")
      AppLogger.api_error("[DEBUG] Stack: #{Exception.format_stacktrace(stacktrace)}")
      {:error, {kind, value}}
  end

  # Helper functions to determine the type of a value
  defp type_of(value) when is_binary(value), do: "binary"
  defp type_of(value) when is_integer(value), do: "integer"
  defp type_of(value) when is_float(value), do: "float"
  defp type_of(value) when is_boolean(value), do: "boolean"
  defp type_of(nil), do: "nil"
  defp type_of(value) when is_atom(value), do: "atom: #{value}"
  defp type_of(value) when is_list(value), do: "list of #{length(value)} items"
  defp type_of(value) when is_map(value), do: "map with keys: #{inspect(Map.keys(value))}"
  defp type_of(value) when is_tuple(value), do: "tuple of size #{tuple_size(value)}"
  defp type_of(value) when is_function(value), do: "function"
  defp type_of(value) when is_pid(value), do: "pid"
  defp type_of(value) when is_reference(value), do: "reference"
  defp type_of(_), do: "unknown"

  # Process activity request
  defp process_activity_request(url, character_id, days) do
    headers = UrlBuilder.get_auth_headers()
    query_params = URI.encode_query(%{"character_id" => character_id, "days" => days})
    activity_url = "#{url}?#{query_params}"
    Client.get(activity_url, headers)
  end

  # Process activity response
  defp process_activity_response({:ok, %{status_code: 200, body: body}}) when is_binary(body) do
    parse_activity_response_body(body)
  end

  defp process_activity_response({:ok, %{status_code: status_code}}) do
    AppLogger.api_error("[CharactersClient] Activity API returned non-200 status: #{status_code}")
    {:error, {:http_error, status_code}}
  end

  defp process_activity_response({:error, reason}) do
    AppLogger.api_error("[CharactersClient] Activity HTTP request failed: #{inspect(reason)}")
    {:error, {:http_error, reason}}
  end

  # Helper to parse activity response body
  defp parse_activity_response_body(body) do
    case Jason.decode(body) do
      {:ok, parsed_json} -> extract_activity_data(parsed_json)
      {:error, reason} -> handle_json_parse_error(reason)
    end
  end

  # Helper to extract activity data from parsed JSON
  defp extract_activity_data(parsed_json) do
    activity_data =
      case parsed_json do
        %{"data" => data} when is_list(data) -> data
        %{"activity" => activity} when is_list(activity) -> activity
        data when is_list(data) -> data
        _ -> []
      end

    {:ok, activity_data}
  end

  # Helper to handle JSON parse errors
  defp handle_json_parse_error(reason) do
    AppLogger.api_error("[CharactersClient] Failed to parse activity JSON: #{inspect(reason)}")
    {:error, {:json_parse_error, reason}}
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
    # Instead of processing the data ourselves, delegate directly to Characters module
    AppLogger.api_info(
      "[CharactersClient] Delegating character response handling to Characters module"
    )

    # Pass the raw body directly to Characters.update_tracked_characters
    Characters.update_tracked_characters(body, cached_characters)
  rescue
    e ->
      stacktrace = __STACKTRACE__

      AppLogger.api_error(
        "[CharactersClient] Unexpected error in handle_character_response: #{Exception.message(e)}"
      )

      AppLogger.api_error("[CharactersClient] #{Exception.format_stacktrace(stacktrace)}")
      {:error, {:unexpected_error, e}}
  end

  # Build the URL for characters endpoint
  defp build_characters_url do
    # Use the UrlBuilder which works correctly for systems
    AppLogger.api_debug("[CharactersClient] Using UrlBuilder to build characters URL")

    # Log both the map_url and map_name configuration values
    AppLogger.api_info(
      "[CharactersClient] Config values: map_url=#{Config.map_url()}, map_name=#{Config.map_name()}"
    )

    # Get the result
    result = UrlBuilder.build_url("map/characters")

    # Log the result URL
    case result do
      {:ok, url} ->
        AppLogger.api_info("[CharactersClient] Built URL: #{url}")
        # Also log curl command for comparison
        curl_cmd = "curl -X GET '#{url}'"
        AppLogger.api_info("[CharactersClient] Equivalent curl: #{curl_cmd}")

      {:error, reason} ->
        AppLogger.api_error("[CharactersClient] Failed to build URL: #{inspect(reason)}")
    end

    # Return the result
    result
  end

  @doc """
  Checks if the characters endpoint is available in the current map API.

  ## Returns
    - {:ok, true} if available
    - {:error, reason} if not available
  """
  @spec check_characters_endpoint_availability() :: {:ok, boolean()} | {:error, term()}
  def check_characters_endpoint_availability do
    AppLogger.api_debug("[CharactersClient] Checking characters endpoint availability")

    with {:ok, url} <- UrlBuilder.build_url("map/characters"),
         headers = UrlBuilder.get_auth_headers(),
         {:ok, response} <- Client.get(url, headers) do
      # We only need to verify that we get a successful response
      case response do
        %{status_code: status} when status >= 200 and status < 300 ->
          AppLogger.api_info("[CharactersClient] Characters endpoint is available")
          {:ok, true}

        %{status_code: status, body: body} ->
          error_reason = "Endpoint returned status #{status}: #{body}"

          AppLogger.api_warn(
            "[CharactersClient] Characters endpoint returned error: #{error_reason}"
          )

          {:error, error_reason}
      end
    else
      {:error, reason} ->
        AppLogger.api_warn(
          "[CharactersClient] Characters endpoint is NOT available: #{inspect(reason)}"
        )

        {:error, reason}
    end
  end

  @doc """
  Gets character activity data from the map API.

  ## Parameters
    - character_id: Optional character ID override
    - days: Optional number of days to fetch activity data

  ## Returns
    - {:ok, activity_data} on success
    - {:error, {:json_parse_error, reason}} if JSON parsing fails
    - {:error, {error_type, {:http_error, reason}}} if HTTP request fails
    - {:error, {:unexpected_error, message}} for unexpected errors
  """
  @spec get_character_activity(String.t() | nil, integer()) ::
          {:ok, list(map())} | {:error, term()}
  def get_character_activity(character_id, days \\ 1) do
    AppLogger.api_debug("[CharactersClient] Getting character activity",
      character_id: character_id
    )

    with {:ok, url} <- UrlBuilder.build_url("map/character-activity"),
         {:ok, response} <- process_activity_request(url, character_id, days),
         {:ok, activity_data} <- process_activity_response(response) do
      {:ok, activity_data}
    else
      {:error, reason} ->
        AppLogger.api_error(
          "[CharactersClient] Failed to get character activity: #{inspect(reason)}"
        )

        {:error, reason}
    end
  end
end
