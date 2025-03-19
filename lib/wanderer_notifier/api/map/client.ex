defmodule WandererNotifier.Api.Map.Client do
  @moduledoc """
  Client for interacting with the Wanderer map API.
  Handles making HTTP requests to the map API endpoints.
  """
  require Logger
  alias WandererNotifier.SystemTracker, as: Systems
  alias WandererNotifier.CharTracker, as: Characters
  alias WandererNotifier.Core.Features
  alias WandererNotifier.Cache.Repository, as: CacheRepo
  alias WandererNotifier.Api.Http.Client, as: HttpClient
  alias WandererNotifier.Core.Config

  # A single function for each major operation:
  def update_systems do
    try do
      if Features.enabled?(:system_tracking) do
        Systems.update_systems()
      else
        Logger.debug("System tracking disabled due to license restrictions")
        {:error, :feature_disabled}
      end
    rescue
      e ->
        Logger.error("Error in update_systems: #{inspect(e)}")
        Logger.error("Stacktrace: #{inspect(Process.info(self(), :current_stacktrace))}")
        {:error, {:exception, e}}
    end
  end

  def update_systems_with_cache(cached_systems) do
    try do
      if Features.enabled?(:system_tracking) do
        Systems.update_systems(cached_systems)
      else
        Logger.debug("System tracking disabled due to license restrictions")
        {:error, :feature_disabled}
      end
    rescue
      e ->
        Logger.error("Error in update_systems_with_cache: #{inspect(e)}")
        Logger.error("Stacktrace: #{inspect(Process.info(self(), :current_stacktrace))}")
        {:error, {:exception, e}}
    end
  end

  def update_tracked_characters(cached_characters \\ nil) do
    try do
      if Features.enabled?(:tracked_characters_notifications) do
        Logger.debug(
          "[Map.Client] Character tracking is enabled, checking for tracked characters"
        )

        # Use provided cached_characters if available, otherwise get from cache
        current_characters = cached_characters || CacheRepo.get("map:characters") || []

        if Features.limit_reached?(:tracked_characters, length(current_characters)) do
          Logger.warning(
            "[Map.Client] Character tracking limit reached (#{length(current_characters)}). Upgrade license for more."
          )

          {:error, :limit_reached}
        else
          # First check if the characters endpoint is available
          case Characters.check_characters_endpoint_availability() do
            {:ok, _} ->
              # Endpoint is available, proceed with update
              Logger.debug(
                "[Map.Client] Characters endpoint is available, proceeding with update"
              )

              Characters.update_tracked_characters(current_characters)

            {:error, reason} ->
              # Endpoint is not available, log detailed error
              Logger.error(
                "[Map.Client] Characters endpoint is not available: #{inspect(reason)}"
              )

              Logger.error("[Map.Client] This map API may not support character tracking")

              Logger.error(
                "[Map.Client] To disable character tracking, set ENABLE_CHARACTER_TRACKING=false"
              )

              # Return a more descriptive error
              {:error, {:characters_endpoint_unavailable, reason}}
          end
        end
      else
        Logger.debug(
          "[Map.Client] Character tracking disabled due to license restrictions or configuration"
        )

        {:error, :feature_disabled}
      end
    rescue
      e ->
        Logger.error("[Map.Client] Error in update_tracked_characters: #{inspect(e)}")

        Logger.error(
          "[Map.Client] Stacktrace: #{inspect(Process.info(self(), :current_stacktrace))}"
        )

        {:error, {:exception, e}}
    end
  end

  @doc """
  Helper function to construct map API URLs consistently.

  ## Parameters
    - endpoint: The API endpoint path (e.g., "map/character-activity")
    - params: Map of query parameters to include in the URL
    - slug: Optional map slug. If not provided, uses the configured map_name or extracts it from map_url_with_name

  ## Returns
    - A properly formatted URL for the map API
  """
  def build_map_api_url(endpoint, params \\ %{}, slug \\ nil) do
    # Get the map slug either from the parameter, config, or extract from map_url_with_name
    map_slug = slug || Config.map_name() || extract_slug_from_url(Config.map_url())

    if map_slug == nil do
      Logger.error("No map slug provided or configured. Cannot construct API URL without a slug.")

      raise "Map slug is required but not available. Please set MAP_NAME or MAP_URL_WITH_NAME in your environment."
    end

    # Extract the base domain from map_url (without the map name)
    # For example: if map_url is "https://wanderer.zoolanders.space/flygd",
    # base_domain should be "https://wanderer.zoolanders.space"
    base_url = Config.map_url()

    # Extract base domain - should be just the domain without the slug path
    base_domain =
      if base_url do
        base_url |> String.split("/") |> Enum.take(3) |> Enum.join("/")
      else
        Logger.error("MAP_URL not configured. Cannot construct API URL.")

        raise "MAP_URL is required but not configured. Please set MAP_URL or MAP_URL_WITH_NAME in your environment."
      end

    # Ensure endpoint doesn't start with a slash
    endpoint = String.trim_leading(endpoint, "/")

    # Add the slug to params if provided
    params = Map.put(params, "slug", map_slug)

    # Convert params to query string
    query_string =
      if map_size(params) > 0 do
        "?" <>
          Enum.map_join(params, "&", fn {key, value} ->
            "#{key}=#{URI.encode_www_form(to_string(value))}"
          end)
      else
        ""
      end

    # Construct and return the full URL
    "#{base_domain}/api/#{endpoint}#{query_string}"
  end

  # Helper function to extract slug from URL
  defp extract_slug_from_url(url) when is_binary(url) do
    # Example: "https://wanderer.zoolanders.space/flygd" -> "flygd"
    # Split by "/" and take the last part
    parts = String.split(url, "/")
    List.last(parts)
  end

  defp extract_slug_from_url(_), do: nil

  @doc """
  Retrieves character activity data from the map API.

  ## Parameters
    - slug: The map slug to fetch data for

  ## Returns
    - {:ok, data} on success
    - {:error, reason} on failure
  """
  def get_character_activity(slug \\ nil) do
    try do
      # Use the helper function to construct the URL - it will raise an error if no slug is available
      url = build_map_api_url("map/character-activity", %{}, slug)
      headers = build_headers()

      # Log the URL and headers for debugging
      Logger.info("Fetching character activity from: #{url}")
      Logger.debug("Request headers: #{inspect(headers)}")

      # Generate curl command for manual testing
      curl_cmd = WandererNotifier.Api.Http.Client.build_curl_command("GET", url, headers)
      Logger.debug("Equivalent curl command: #{curl_cmd}")

      case HttpClient.request("GET", url, headers) do
        {:ok, %{status_code: status, body: body}} when status in 200..299 ->
          Logger.info("Successfully received response with status: #{status}")

          case Jason.decode(body) do
            {:ok, data} ->
              Logger.info("Successfully decoded character activity data")
              {:ok, data}

            {:error, reason} ->
              Logger.error("Failed to decode character activity data: #{inspect(reason)}")
              Logger.error("Raw response body (first 500 chars): #{String.slice(body, 0, 500)}")
              {:error, "Failed to decode character activity data"}
          end

        {:ok, %{status_code: status, body: body}} ->
          Logger.error("Failed to fetch character activity data: status=#{status}")
          Logger.error("Error response body (first 500 chars): #{String.slice(body, 0, 500)}")
          {:error, "Failed to fetch character activity data: HTTP #{status}"}

        {:error, reason} ->
          Logger.error("Error fetching character activity data: #{inspect(reason)}")
          # Also log the URL and headers again for context
          Logger.error("Failed URL: #{url}")
          Logger.error("Failed headers: #{inspect(headers)}")
          {:error, "Error fetching character activity data: #{inspect(reason)}"}
      end
    rescue
      e ->
        error_message = "Error constructing character activity URL: #{inspect(e)}"
        Logger.error(error_message)
        {:error, error_message}
    end
  end

  defp build_headers do
    token = Config.map_token()
    csrf_token = Config.map_csrf_token()

    # Debug logs for token availability
    if token do
      Logger.info("Map token is available")
    else
      Logger.warning("Map token is NOT available - bearer token authentication will not be used")
      # Log environment variables for debugging (don't log full values for security)
      env_vars =
        System.get_env()
        |> Enum.filter(fn {k, _} ->
          String.contains?(String.downcase(k), "token") ||
            String.contains?(String.downcase(k), "map")
        end)

      env_var_names = Enum.map(env_vars, fn {k, _} -> k end)
      Logger.info("Environment variables that might contain tokens: #{inspect(env_var_names)}")
    end

    headers = [
      {"accept", "application/json"}
    ]

    headers = if token, do: [{"Authorization", "Bearer #{token}"} | headers], else: headers
    headers = if csrf_token, do: [{"x-csrf-token", csrf_token} | headers], else: headers

    headers
  end
end
