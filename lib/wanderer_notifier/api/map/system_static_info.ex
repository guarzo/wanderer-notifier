defmodule WandererNotifier.Api.Map.SystemStaticInfo do
  @moduledoc """
  Client for fetching static information about EVE systems from the map API.
  Provides clean access to detailed system information for wormholes and other systems.
  """

  require Logger
  alias WandererNotifier.Api.Http.Client
  alias WandererNotifier.Api.Http.ErrorHandler
  alias WandererNotifier.Api.Map.ResponseValidator
  alias WandererNotifier.Api.Map.UrlBuilder
  alias WandererNotifier.Logger, as: AppLogger

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
    # Add detailed logging for debugging
    AppLogger.api_info("[SystemStaticInfo] Fetching static info for system #{solar_system_id}")

    # Create a task for the API request to add timeout handling
    task = Task.async(fn -> fetch_system_static_info(solar_system_id) end)

    # Wait for the task with a timeout (3 seconds)
    case Task.yield(task, 3_000) do
      {:ok, result} ->
        # Log result and return
        case result do
          {:ok, _} ->
            AppLogger.api_info("[SystemStaticInfo] Successfully got static info")

          {:error, reason} ->
            AppLogger.api_warn("[SystemStaticInfo] Static info failed: #{inspect(reason)}")
        end

        result

      nil ->
        # Task took too long, kill it
        Task.shutdown(task, :brutal_kill)
        AppLogger.api_error("[SystemStaticInfo] Static info request timed out")
        {:error, :timeout}
    end
  end

  # Separate function to fetch the system static info (reduces nesting)
  defp fetch_system_static_info(solar_system_id) do
    case UrlBuilder.build_url("common/system-static-info", %{id: solar_system_id}) do
      {:ok, url} ->
        # Log URL for debugging
        AppLogger.api_debug("[SystemStaticInfo] Requesting static info from URL: #{url}")

        # Get auth headers
        headers = UrlBuilder.get_auth_headers()

        # Make API request and process
        make_static_info_request(url, headers)

      {:error, reason} ->
        AppLogger.api_error("[SystemStaticInfo] Failed to build URL: #{inspect(reason)}")
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
            # Validate the static info format
            validate_static_info(parsed_response)

          error ->
            error
        end

      {:error, reason} ->
        AppLogger.api_error("[SystemStaticInfo] Request failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp process_api_response(response) do
    case ErrorHandler.handle_http_response(response, domain: :map, tag: "Map.static_info") do
      {:ok, _parsed_response} = success ->
        success

      {:error, reason} = error ->
        AppLogger.api_error("[SystemStaticInfo] HTTP error: #{inspect(reason)}")
        error
    end
  end

  defp validate_static_info(parsed_response) do
    case ResponseValidator.validate_system_static_info_response(parsed_response) do
      {:ok, _data} = success ->
        # Successfully validated
        AppLogger.api_debug("[SystemStaticInfo] Successfully validated static info")
        success

      {:error, reason} = error ->
        AppLogger.api_warn("[SystemStaticInfo] Invalid system static info: #{inspect(reason)}")
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

    # Log the start of enrichment
    AppLogger.api_info(
      "[SystemStaticInfo] Starting enrichment for system #{system.name} (ID: #{system.solar_system_id})"
    )

    # Only try to enrich if the system has a valid ID
    if system.solar_system_id && system.solar_system_id > 0 do
      # Try to get static info with proper error handling
      case get_system_static_info(system.solar_system_id) do
        {:ok, static_info} ->
          # Log success with info about what we got
          AppLogger.api_info(
            "[SystemStaticInfo] Successfully got static info for #{system.name}",
            keys: Map.keys(static_info)
          )

          # Update the map system with static information
          enhanced_system = MapSystem.update_with_static_info(system, static_info)

          # Log what was added
          AppLogger.api_debug(
            "[SystemStaticInfo] System enriched successfully",
            statics: enhanced_system.statics,
            type_description: enhanced_system.type_description,
            class_title: enhanced_system.class_title
          )

          {:ok, enhanced_system}

        {:error, reason} ->
          # Log error but continue with original system
          AppLogger.api_warn(
            "[SystemStaticInfo] Could not enrich system #{system.name}: #{inspect(reason)}. Using basic system."
          )

          # Return original system - IMPORTANT: Don't error out!
          {:ok, system}
      end
    else
      # Invalid system ID - log and return original
      AppLogger.api_warn(
        "[SystemStaticInfo] Cannot enrich system with invalid ID: #{inspect(system.solar_system_id)}"
      )

      # Still return original system
      {:ok, system}
    end
  end
end
