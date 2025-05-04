defmodule WandererNotifier.Map.SystemStaticInfo do
  @moduledoc """
  Client for fetching static information about EVE systems from the map API.
  Provides clean access to detailed system information for wormholes and other systems.

  Example wormhole system response:
  ```json
  {
    "data": {
      "statics": [
        "C247",
        "P060"
      ],
      "security": "-1.0",
      "class_title": "C4",
      "constellation_id": 21000172,
      "constellation_name": "D-C00172",
      "effect_name": null,
      "effect_power": 4,
      "is_shattered": false,
      "region_id": 11000018,
      "region_name": "D-R00018",
      "solar_system_id": 31001503,
      "solar_system_name": "J155416",
      "solar_system_name_lc": "j155416",
      "sun_type_id": 45032,
      "system_class": 4,
      "triglavian_invasion_status": "Normal",
      "type_description": "Class 4",
      "wandering": [
        "S047",
        "N290",
        "K329"
      ],
      "static_details": [
        {
          "name": "C247",
          "destination": {
            "id": "c3",
            "name": "Class 3",
            "short_name": "C3"
          },
          "properties": {
            "lifetime": "16",
            "mass_regeneration": 0,
            "max_jump_mass": 300000000,
            "max_mass": 2000000000
          }
        },
        {
          "name": "P060",
          "destination": {
            "id": "c1",
            "name": "Class 1",
            "short_name": "C1"
          },
          "properties": {
            "lifetime": "16",
            "mass_regeneration": 0,
            "max_jump_mass": 62000000,
            "max_mass": 500000000
          }
        }
      ]
    }
  }
  """

  alias WandererNotifier.HttpClient.Httpoison, as: HttpClient
  alias WandererNotifier.Logger.Logger, as: AppLogger
  alias WandererNotifier.Config

  @doc """
  Fetches static information for a specific solar system.
  Uses a more robust approach with proper validation and timeouts.

  ## Parameters
    - solar_system_id: The ID of the solar system to fetch information for

  ## Returns
    - {:ok, static_info} on success
    - {:error, reason} on failure
  """
  def get_system_static_info(solar_system_id) do
    case fetch_system_static_info(solar_system_id) do
      {:ok, static_info} ->
        {:ok, static_info}

      {:error, reason} ->
        AppLogger.api_error("[SystemStaticInfo] Failed to get static info", %{
          system_id: solar_system_id,
          error: inspect(reason)
        })

        {:error, reason}
    end
  end

  # Private helper functions

  defp fetch_system_static_info(solar_system_id) do
    AppLogger.api_debug("[SystemStaticInfo] Building URL",
      system_id: solar_system_id
    )

    base_url = Config.base_map_url()
    url = "#{base_url}/api/common/system-static-info?id=#{solar_system_id}"
    headers = get_auth_headers()

    AppLogger.api_debug("[SystemStaticInfo] Making request",
      url: url,
      headers: headers
    )

    # Make API request and process
    make_static_info_request(url, headers)
  end

  # Make the actual API request for static info
  defp make_static_info_request(url, headers) do
    case HttpClient.get(url, headers) do
      {:ok, %{status_code: 200, body: body}} when is_map(body) ->
        {:ok, body}

      {:ok, %{status_code: 200, body: body}} when is_binary(body) ->
        case Jason.decode(body) do
          {:ok, parsed_response} -> {:ok, parsed_response}
          {:error, reason} ->
            AppLogger.api_error("[SystemStaticInfo] Failed to parse JSON", error: inspect(reason))
            {:error, {:json_parse_error, reason}}
        end

      {:ok, %{status_code: status}} ->
        AppLogger.api_error("[SystemStaticInfo] HTTP error", status: status)
        {:error, {:http_error, status}}

      {:error, reason} ->
        AppLogger.api_error("[SystemStaticInfo] Request failed", error: inspect(reason))
        {:error, reason}
    end
  end

  @doc """
  Enriches a MapSystem with static information.

  ## Parameters
    - system: A WandererNotifier.Map.MapSystem struct

  ## Returns
    - {:ok, enhanced_system} on success with enriched data
    - {:ok, system} on failure but returns the original system
  """
  def enrich_system(system) do
    alias WandererNotifier.Map.MapSystem

    try do
      # Only try to enrich if the system has a valid ID
      if system.solar_system_id && system.solar_system_id > 0 do
        # Try to get static info with proper error handling
        result = get_system_static_info(system.solar_system_id)
        AppLogger.api_debug("[SystemStaticInfo] get_system_static_info result (FULL RAW)",
          system_id: system.solar_system_id,
          raw_result: inspect(result, pretty: true, limit: 2000)
        )
        AppLogger.api_debug("[SystemStaticInfo] get_system_static_info result",
          system_id: system.solar_system_id,
          result: inspect(result, pretty: true, limit: 1000)
        )
        case result do
          {:ok, static_info} ->
            # Merge only the inner data map if present
            data_to_merge =
              case static_info do
                %{"data" => data_map} when is_map(data_map) -> data_map
                other -> other
              end
            AppLogger.api_debug("[SystemStaticInfo] Got static info for enrichment",
              system_name: system.name,
              static_info_keys: Map.keys(data_to_merge),
              static_info: inspect(data_to_merge, pretty: true, limit: 1000)
            )

            # Update the map system with static information
            enhanced_system = MapSystem.update_with_static_info(system, data_to_merge)

            # Convert "security" to :security_status (float) and add to struct
            security_status =
              case Map.get(data_to_merge, "security") do
                nil -> 0.0
                val when is_binary(val) ->
                  case Float.parse(val) do
                    {f, _} -> f
                    :error -> 0.0
                  end
                val when is_number(val) -> val
                _ -> 0.0
              end
            enhanced_system = Map.put(enhanced_system, :security_status, security_status)

            # Map expected string keys to atom keys, handling optional fields
            expected_fields = [
              :statics, :effect_name, :class_title, :effect_power, :is_shattered, :region_id,
              :region_name, :system_class, :triglavian_invasion_status, :type_description,
              :constellation_id, :constellation_name, :static_details, :sun_type_id
            ]
            enhanced_system = Enum.reduce(expected_fields, enhanced_system, fn field, acc ->
              string_key = Atom.to_string(field)
              value = Map.get(data_to_merge, string_key)
              # For statics and static_details, default to [] if not present
              default = if field in [:statics, :static_details], do: [], else: nil
              Map.put(acc, field, (if value == nil, do: default, else: value))
            end)

            AppLogger.api_debug("[SystemStaticInfo] Enriched system result",
              enriched_system: inspect(enhanced_system, pretty: true, limit: 1000)
            )
            {:ok, enhanced_system}

          {:error, reason} ->
            # Log error but continue with original system
            AppLogger.api_warn(
              "[SystemStaticInfo] Could not enrich system",
              system_name: system.name,
              error: inspect(reason),
              system: inspect(system, pretty: true, limit: 1000)
            )

            # Return original system - IMPORTANT: Don't error out!
            AppLogger.api_debug("[SystemStaticInfo] Returning original system after enrichment failure",
              system: inspect(system, pretty: true, limit: 1000)
            )
            {:ok, system}
        end
      else
        # Invalid system ID - log and return original
        AppLogger.api_warn(
          "[SystemStaticInfo] Cannot enrich system with invalid ID",
          system_name: system.name,
          system_id: system.solar_system_id,
          system: inspect(system, pretty: true, limit: 1000)
        )

        # Still return original system
        AppLogger.api_debug("[SystemStaticInfo] Returning original system due to invalid ID",
          system: inspect(system, pretty: true, limit: 1000)
        )
        {:ok, system}
      end
    rescue
      e ->
        log_message = [
          "[SystemStaticInfo] Exception during system enrichment:",
          "Error: #{Exception.message(e)}",
          "System: #{inspect(system, pretty: true, limit: 1000)}",
          "Stacktrace:\n#{Exception.format_stacktrace(__STACKTRACE__)}"
        ] |> Enum.join("\n")

        AppLogger.api_error(log_message)
        {:ok, system}
    end
  end

  defp get_auth_headers do
    api_key = Config.map_token()
    [{"Authorization", "Bearer #{api_key}"}]
  end
end
