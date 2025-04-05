defmodule WandererNotifier.Api.Map.SystemStaticInfo do
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

  require Logger
  alias WandererNotifier.Api.Http.Client
  alias WandererNotifier.Api.Http.ErrorHandler
  alias WandererNotifier.Api.Map.ResponseValidator
  alias WandererNotifier.Api.Map.UrlBuilder
  alias WandererNotifier.Logger.Logger, as: AppLogger

  @doc """
  Fetches static information for a specific solar system.
  Uses a more robust approach with proper validation and timeouts.

  ## Parameters
    - solar_system_id: The EVE Online ID of the solar system

  ## Returns
    - {:ok, system_info} on success
    - {:error, reason} on failure
  """
  def get_system_static_info(solar_system_id) do
    AppLogger.api_debug("[SystemStaticInfo] Starting static info fetch",
      system_id: solar_system_id
    )

    # Create a task for the API request to add timeout handling
    task = Task.async(fn -> fetch_system_static_info(solar_system_id) end)

    # Wait for the task with a timeout (3 seconds)
    case Task.yield(task, 3_000) do
      {:ok, result} ->
        # Log result and return
        case result do
          {:ok, static_info} ->
            AppLogger.api_debug("[SystemStaticInfo] Successfully got static info",
              system_id: solar_system_id,
              static_info_keys: Map.keys(static_info)
            )

          {:error, reason} ->
            AppLogger.api_warn("[SystemStaticInfo] Static info failed",
              system_id: solar_system_id,
              error: inspect(reason)
            )
        end

        result

      nil ->
        # Task took too long, kill it
        Task.shutdown(task, :brutal_kill)

        AppLogger.api_error("[SystemStaticInfo] Static info request timed out",
          system_id: solar_system_id
        )

        {:error, :timeout}
    end
  end

  # Separate function to fetch the system static info (reduces nesting)
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
    case Client.get(url, headers) do
      {:ok, response} ->
        # Process the response with proper validation
        case process_api_response(response) do
          {:ok, parsed_response} ->
            AppLogger.api_debug("[SystemStaticInfo] Parsed response",
              parsed_response: parsed_response
            )

            # Validate the static info format
            validate_static_info(parsed_response)

          error ->
            error
        end

      {:error, reason} ->
        AppLogger.api_error("[SystemStaticInfo] Request failed",
          error: inspect(reason)
        )

        {:error, reason}
    end
  end

  defp process_api_response(response) do
    case ErrorHandler.handle_http_response(response, domain: :map, tag: "Map.static_info") do
      {:ok, parsed_response} = success ->
        AppLogger.api_debug("[SystemStaticInfo] Parsed response",
          response_keys: Map.keys(parsed_response)
        )

        success

      {:error, reason} = error ->
        AppLogger.api_error("[SystemStaticInfo] HTTP error",
          error: inspect(reason)
        )

        error
    end
  end

  defp validate_static_info(parsed_response) do
    case ResponseValidator.validate_system_static_info_response(parsed_response) do
      {:ok, data} = success ->
        # Successfully validated
        AppLogger.api_debug("[SystemStaticInfo] Validated response",
          data_keys: Map.keys(data)
        )

        success

      {:error, reason} = error ->
        AppLogger.api_warn("[SystemStaticInfo] Invalid system static info",
          error: inspect(reason)
        )

        error
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
    alias WandererNotifier.Data.MapSystem

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
