defmodule WandererNotifier.Api.Map.Systems do
  @moduledoc """
  Retrieves and processes system data from the map API, filtering for wormhole systems.
  Only wormhole systems (where a system's static info shows a non-empty "statics" list or
  the "type_description" starts with "Class") are returned.
  """
  require Logger
  alias WandererNotifier.Api.Http.Client, as: HttpClient
  alias WandererNotifier.Data.Cache.Repository, as: CacheRepo
  alias WandererNotifier.Core.Config
  alias WandererNotifier.Config.Timings
  alias WandererNotifier.Notifiers.Factory, as: NotifierFactory

  def update_systems(cached_systems \\ nil) do
    Logger.debug("[update_systems] Starting systems update")

    with {:ok, systems_url} <- build_systems_url(),
         {:ok, body} <- fetch_get_body(systems_url),
         {:ok, json} <- decode_json(body),
         {:ok, fresh_systems} <- process_systems(json) do
      if fresh_systems == [] do
        Logger.warning("[update_systems] No systems found in map API response")
      else
        Logger.debug("[update_systems] Found #{length(fresh_systems)} systems")
      end

      # Cache the systems
      CacheRepo.set("systems", fresh_systems, Timings.systems_cache_ttl())

      # Find new systems by comparing with cached_systems
      _ = notify_new_systems(fresh_systems, cached_systems)

      {:ok, fresh_systems}
    else
      {:error, reason} ->
        Logger.error("[update_systems] Failed to update systems: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp build_systems_url do
    base_url = Config.map_url()
    map_token = Config.map_token()

    cond do
      is_nil(base_url) or base_url == "" ->
        {:error, "Map URL is not configured"}

      is_nil(map_token) or map_token == "" ->
        {:error, "Map token is not configured"}

      true ->
        # Remove trailing slash if present
        base_url = String.trim_trailing(base_url, "/")
        {:ok, "#{base_url}/api/systems"}
    end
  end

  defp fetch_get_body(url) do
    map_token = Config.map_token()
    # Request headers
    headers = [
      {"Authorization", "Bearer #{map_token}"},
      {"Content-Type", "application/json"},
      {"Accept", "application/json"}
    ]

    # Make the request
    case HttpClient.get(url, headers) do
      {:ok, %{status_code: 200, body: body}} ->
        {:ok, body}

      {:ok, %{status_code: status_code, body: body}} ->
        Logger.error(
          "[fetch_get_body] API returned non-200 status: #{status_code}. Body: #{body}"
        )

        {:error, "API returned non-200 status: #{status_code}"}

      {:error, reason} ->
        Logger.error("[fetch_get_body] API request failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp decode_json(body) do
    case Jason.decode(body) do
      {:ok, json} ->
        {:ok, json}

      {:error, reason} ->
        Logger.error("[decode_json] Failed to decode JSON: #{inspect(reason)}")
        {:error, "Failed to decode JSON: #{inspect(reason)}"}
    end
  end

  defp process_systems(json) do
    case json do
      %{"systems" => systems} when is_list(systems) ->
        # Filter for wormhole systems
        wormhole_systems =
          systems
          |> Enum.filter(&is_wormhole_system?/1)
          |> Enum.map(&extract_system_data/1)

        {:ok, wormhole_systems}

      _ ->
        Logger.error("[process_systems] Unexpected JSON format: #{inspect(json)}")
        {:error, "Unexpected JSON format"}
    end
  end

  defp is_wormhole_system?(system) do
    # Check for presence of "statics" in the system info
    case system do
      %{"staticInfo" => %{"statics" => statics}} when is_list(statics) and statics != [] ->
        true

      %{"staticInfo" => %{"typeDescription" => type_desc}} when is_binary(type_desc) ->
        # Check if type description starts with "Class" (common for WH systems)
        String.starts_with?(type_desc, "Class")

      _ ->
        false
    end
  end

  defp extract_system_data(system) do
    # Extract relevant fields for tracking
    %{
      "id" => Map.get(system, "id"),
      "systemName" => Map.get(system, "systemName"),
      "alias" => Map.get(system, "alias"),
      "systemId" => Map.get(system, "systemId"),
      "staticInfo" => Map.get(system, "staticInfo", %{})
    }
  end

  defp notify_new_systems(fresh_systems, cached_systems) do
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
              Map.get(fresh_sys, "id") == Map.get(cached_sys, "id")
            end)
          end)
        end

      # Send notifications for added systems
      track_all_systems = Config.track_all_systems?()

      for system <- added_systems do
        Task.start(fn ->
          try do
            system_name = Map.get(system, "systemName") || Map.get(system, "alias") || "Unknown"
            system_id = Map.get(system, "systemId")

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
                "[notify_new_systems] System #{system_name} added and tracked (track_all_systems=true)"
              )
            else
              Logger.info("[notify_new_systems] New system #{system_name} discovered")
            end
          rescue
            e ->
              Logger.error(
                "[notify_new_systems] Error sending system notification: #{inspect(e)}"
              )
          end
        end)
      end

      {:ok, added_systems}
    else
      Logger.debug("[notify_new_systems] System notifications disabled")
      {:ok, []}
    end
  end

  # Helper function to generate system URL
  defp system_url(nil), do: nil
  defp system_url(system_id), do: "https://zkillboard.com/system/#{system_id}/"
end
