defmodule WandererNotifier.Api.Map.SystemsClient do
  @moduledoc """
  Client for retrieving and processing system data from the map API.
  Uses structured data types and consistent parsing to simplify the logic.
  """
  require Logger
  alias WandererNotifier.Api.Http.Client
  alias WandererNotifier.Api.Map.UrlBuilder
  alias WandererNotifier.Data.Cache.Repository, as: CacheRepo
  alias WandererNotifier.Core.Config
  alias WandererNotifier.Core.Config.Timings
  alias WandererNotifier.Notifiers.Factory, as: NotifierFactory
  alias WandererNotifier.Data.MapSystem

  @doc """
  Updates the system information in the cache.
  
  If cached_systems is provided, it will also identify and notify about new systems.
  
  ## Parameters
    - cached_systems: Optional list of cached systems for comparison
    
  ## Returns
    - {:ok, systems} on success
    - {:error, reason} on failure
  """
  def update_systems(cached_systems \\ nil) do
    Logger.debug("[SystemsClient] Starting systems update")

    with {:ok, url} <- UrlBuilder.build_url("map/systems"),
         headers = UrlBuilder.get_auth_headers() do
      
      # Make the API request directly to handle raw response
      case Client.get(url, headers) do
        {:ok, %{status_code: 200, body: body, headers: _headers}} when is_binary(body) ->
          # Successfully got response, now parse it carefully
          case Jason.decode(body) do
            {:ok, parsed_json} ->
              # Extract systems data with fallbacks for different API formats
              systems_data = case parsed_json do
                %{"data" => data} when is_list(data) -> data
                %{"systems" => systems} when is_list(systems) -> systems
                data when is_list(data) -> data
                _ -> []
              end

              # Convert to MapSystem structs
              Logger.debug("[SystemsClient] Parsing #{length(systems_data)} systems from API response")
              systems = Enum.map(systems_data, &MapSystem.new/1)
              
              # Optional: Filter for just wormhole systems if needed
              wormhole_systems = Enum.filter(systems, &MapSystem.is_wormhole?/1)
              
              if wormhole_systems == [] do
                Logger.warning("[SystemsClient] No wormhole systems found in map API response")
              else
                Logger.debug("[SystemsClient] Found #{length(wormhole_systems)} wormhole systems")
              end

              # Cache the systems
              CacheRepo.set("map:systems", wormhole_systems, Timings.systems_cache_ttl())

              # Find and notify about new systems
              _ = notify_new_systems(wormhole_systems, cached_systems)

              {:ok, wormhole_systems}
              
            {:error, reason} ->
              Logger.error("[SystemsClient] Failed to parse JSON: #{inspect(reason)}")
              Logger.debug("[SystemsClient] Raw response body sample: #{String.slice(body, 0, 100)}...")
              {:error, {:json_parse_error, reason}}
          end
          
        {:ok, %{status_code: status_code}} when status_code != 200 ->
          Logger.error("[SystemsClient] API returned non-200 status: #{status_code}")
          {:error, {:http_error, status_code}}
          
        {:error, reason} ->
          Logger.error("[SystemsClient] HTTP request failed: #{inspect(reason)}")
          {:error, {:http_error, reason}}
      end
    else
      {:error, reason} ->
        Logger.error("[SystemsClient] Failed to build URL or headers: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Identifies new systems by comparing with cached systems and sends notifications.
  
  ## Parameters
    - fresh_systems: List of newly fetched systems
    - cached_systems: List of previously cached systems
    
  ## Returns
    - {:ok, added_systems} with list of newly added systems
  """
  def notify_new_systems(fresh_systems, cached_systems) do
    if Config.system_notifications_enabled?() do
      # Ensure we have both fresh and cached systems as lists
      fresh = fresh_systems || []
      cached = cached_systems || []

      # Find systems that are in fresh but not in cached
      # We compare by id because that's the unique identifier in the map API
      added_systems =
        if cached == [] do
          # If there's no cached systems, this is probably the first run
          # Don't notify about all systems to avoid spamming
          []
        else
          fresh
          |> Enum.filter(fn fresh_sys ->
            !Enum.any?(cached, fn cached_sys ->
              fresh_sys.id == cached_sys.id
            end)
          end)
        end

      # Send notifications for added systems
      track_all_systems = Config.track_all_systems?()

      for system <- added_systems do
        Task.start(fn ->
          try do
            system_name = system.name
            system_id = system.solar_system_id

            # Prepare the notification
            system_data = %{
              "name" => system_name,
              "id" => system_id,
              "url" => system_url(system_id)
            }

            # Send the notification
            notifier = NotifierFactory.get_notifier()
            notifier.send_new_system_notification(system_data)

            if track_all_systems do
              Logger.info(
                "[SystemsClient] System #{system_name} added and tracked (track_all_systems=true)"
              )
            else
              Logger.info("[SystemsClient] New system #{system_name} discovered")
            end
          rescue
            e ->
              Logger.error(
                "[SystemsClient] Error sending system notification: #{inspect(e)}"
              )
          end
        end)
      end

      {:ok, added_systems}
    else
      Logger.debug("[SystemsClient] System notifications disabled")
      {:ok, []}
    end
  end

  # Helper function to generate system URL
  defp system_url(nil), do: nil
  defp system_url(system_id), do: "https://zkillboard.com/system/#{system_id}/"
end
