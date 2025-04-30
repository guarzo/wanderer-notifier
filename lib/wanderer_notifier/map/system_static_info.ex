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
  alias WandererNotifier.HttpClient.ErrorHandler
  alias WandererNotifier.HttpClient.UrlBuilder
  alias WandererNotifier.Logger.Logger, as: AppLogger

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

    case UrlBuilder.build_url("common/system-static-info", %{id: solar_system_id}) do
      {:ok, url} ->
        # Get auth headers
        headers = UrlBuilder.get_auth_headers()

        AppLogger.api_debug("[SystemStaticInfo] Making request",
          url: url,
          headers: headers
        )

        # Make API request and process
        make_static_info_request(url, headers)

      {:error, reason} ->
        AppLogger.api_error("[SystemStaticInfo] Failed to build URL",
          system_id: solar_system_id,
          error: inspect(reason)
        )

        {:error, reason}
    end
  end

  # Make the actual API request for static info
  defp make_static_info_request(url, headers) do
    case HttpClient.get(url, headers) do
      {:ok, response} ->
        case ErrorHandler.handle_http_response(response, domain: :map, tag: "Map.static_info") do
          {:ok, parsed_response} ->
            AppLogger.api_debug("[SystemStaticInfo] Parsed response",
              response_keys: Map.keys(parsed_response)
            )

            {:ok, parsed_response}

          {:error, reason} = error ->
            AppLogger.api_error("[SystemStaticInfo] HTTP error",
              error: inspect(reason)
            )

            error
        end

      {:error, reason} ->
        AppLogger.api_error("[SystemStaticInfo] Request failed",
          error: inspect(reason)
        )

        {:error, reason}
    end
  end

  @doc """
  Enriches a MapSystem with static information.

  ## Parameters
    - system: A WandererNotifier.Data.MapSystem struct

  ## Returns
    - {:ok, enhanced_system} on success with enriched data
    - {:ok, system} on failure but returns the original system
  """
  def enrich_system(system) do
    alias WandererNotifier.Map.MapSystem

    AppLogger.api_debug("[SystemStaticInfo] Starting system enrichment",
      system_name: system.name,
      system_id: system.solar_system_id
    )

    # Only try to enrich if the system has a valid ID
    if system.solar_system_id && system.solar_system_id > 0 do
      # Try to get static info with proper error handling
      case get_system_static_info(system.solar_system_id) do
        {:ok, static_info} ->
          AppLogger.api_debug("[SystemStaticInfo] Got static info for enrichment",
            system_name: system.name,
            static_info_keys: Map.keys(static_info)
          )

          # Update the map system with static information
          enhanced_system = MapSystem.update_with_static_info(system, static_info)

          {:ok, enhanced_system}

        {:error, reason} ->
          # Log error but continue with original system
          AppLogger.api_warn(
            "[SystemStaticInfo] Could not enrich system",
            system_name: system.name,
            error: inspect(reason)
          )

          # Return original system - IMPORTANT: Don't error out!
          {:ok, system}
      end
    else
      # Invalid system ID - log and return original
      AppLogger.api_warn(
        "[SystemStaticInfo] Cannot enrich system with invalid ID",
        system_name: system.name,
        system_id: system.solar_system_id
      )

      # Still return original system
      {:ok, system}
    end
  end
end
