defmodule WandererNotifier.Map.Client do
  @moduledoc """
  High-level map API client.
  """
  require Logger
  alias WandererNotifier.Map.Systems
  alias WandererNotifier.Map.Characters
  alias WandererNotifier.Features
  alias WandererNotifier.Cache.Repository, as: CacheRepo
  alias WandererNotifier.Http.Client, as: HttpClient
  alias WandererNotifier.Config

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
        Logger.debug("[Map.Client] Character tracking is enabled, checking for tracked characters")

        # Use provided cached_characters if available, otherwise get from cache
        current_characters = cached_characters || CacheRepo.get("map:characters") || []

        if Features.limit_reached?(:tracked_characters, length(current_characters)) do
          Logger.warning("[Map.Client] Character tracking limit reached (#{length(current_characters)}). Upgrade license for more.")
          {:error, :limit_reached}
        else
          # First check if the characters endpoint is available
          case Characters.check_characters_endpoint_availability() do
            {:ok, _} ->
              # Endpoint is available, proceed with update
              Logger.debug("[Map.Client] Characters endpoint is available, proceeding with update")
              Characters.update_tracked_characters(current_characters)

            {:error, reason} ->
              # Endpoint is not available, log detailed error
              Logger.error("[Map.Client] Characters endpoint is not available: #{inspect(reason)}")
              Logger.error("[Map.Client] This map API may not support character tracking")
              Logger.error("[Map.Client] To disable character tracking, set ENABLE_CHARACTER_TRACKING=false")

              # Return a more descriptive error
              {:error, {:characters_endpoint_unavailable, reason}}
          end
        end
      else
        Logger.debug("[Map.Client] Character tracking disabled due to license restrictions or configuration")
        {:error, :feature_disabled}
      end
    rescue
      e ->
        Logger.error("[Map.Client] Error in update_tracked_characters: #{inspect(e)}")
        Logger.error("[Map.Client] Stacktrace: #{inspect(Process.info(self(), :current_stacktrace))}")
        {:error, {:exception, e}}
    end
  end

  @doc """
  Fetches character activity data from the map API.

  ## Parameters
    - slug: The map slug to fetch data for

  ## Returns
    - {:ok, data} on success
    - {:error, reason} on failure
  """
  def get_character_activity(slug \\ nil) do
    map_slug = slug || Config.map_name()

    if map_slug == nil do
      Logger.error("Map slug not provided and not configured")
      {:error, "Map slug not provided and not configured"}
    else
      url = "#{Config.map_url()}/api/map/character-activity?slug=#{map_slug}"
      headers = build_headers()

      case HttpClient.request("GET", url, headers) do
        {:ok, %{status_code: status, body: body}} when status in 200..299 ->
          case Jason.decode(body) do
            {:ok, data} ->
              Logger.debug("Successfully fetched character activity data")
              {:ok, data}
            {:error, reason} ->
              Logger.error("Failed to decode character activity data: #{inspect(reason)}")
              {:error, "Failed to decode character activity data"}
          end
        {:ok, %{status_code: status, body: body}} ->
          Logger.error("Failed to fetch character activity data: status=#{status}, body=#{body}")
          {:error, "Failed to fetch character activity data: HTTP #{status}"}
        {:error, reason} ->
          Logger.error("Error fetching character activity data: #{inspect(reason)}")
          {:error, "Error fetching character activity data"}
      end
    end
  end

  defp build_headers do
    token = Config.map_token()
    csrf_token = Config.map_csrf_token()

    headers = [
      {"accept", "application/json"}
    ]

    headers = if token, do: [{"Authorization", "Bearer #{token}"} | headers], else: headers
    headers = if csrf_token, do: [{"x-csrf-token", csrf_token} | headers], else: headers

    headers
  end
end
