defmodule WandererNotifier.Api.Map.SystemStaticInfo do
  @moduledoc """
  Client for fetching static information about EVE systems from the map API.
  Provides clean access to detailed system information for wormholes and other systems.
  """

  require Logger
  alias WandererNotifier.Logger, as: AppLogger
  alias WandererNotifier.Api.Http.Client
  alias WandererNotifier.Api.Http.ErrorHandler
  alias WandererNotifier.Api.Map.UrlBuilder
  alias WandererNotifier.Api.Map.ResponseValidator

  @doc """
  Fetches static information for a specific solar system.

  ## Parameters
    - solar_system_id: The EVE Online ID of the solar system

  ## Returns
    - {:ok, system_info} on success
    - {:error, reason} on failure
  """
  def get_system_static_info(solar_system_id) do
    with {:ok, url} <- build_system_static_info_url(solar_system_id),
         {:ok, response} <- make_api_request(url, solar_system_id),
         {:ok, parsed_response} <- process_api_response(response),
         {:ok, data} <- validate_static_info(parsed_response) do
      AppLogger.api_debug("[SystemStaticInfo] Successfully validated static info")
      {:ok, data}
    end
  end

  defp build_system_static_info_url(solar_system_id) do
    case extract_base_domain() do
      {:ok, base_domain} ->
        url = "#{base_domain}/api/common/system-static-info?id=#{solar_system_id}"
        {:ok, url}

      {:error, reason} = error ->
        AppLogger.api_error("[SystemStaticInfo] Failed to construct URL: #{inspect(reason)}")
        error
    end
  end

  defp make_api_request(url, solar_system_id) do
    headers = UrlBuilder.get_auth_headers()
    # Log request details for debugging
    AppLogger.api_debug("[SystemStaticInfo] Requesting static info for system #{solar_system_id}")
    AppLogger.api_debug("[SystemStaticInfo] URL: #{url}")

    case Client.get(url, headers) do
      {:ok, _response} = success ->
        success

      {:error, reason} = error ->
        AppLogger.api_error("[SystemStaticInfo] Request failed: #{inspect(reason)}")
        error
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
    - {:ok, enhanced_system} on success
    - {:error, reason} on failure
  """
  def enrich_system(system) do
    alias WandererNotifier.Data.MapSystem

    case get_system_static_info(system.solar_system_id) do
      {:ok, static_info} ->
        # Update the map system with static information
        enhanced_system = MapSystem.update_with_static_info(system, static_info)
        {:ok, enhanced_system}

      {:error, reason} ->
        Logger.warning(
          "[SystemStaticInfo] Could not enrich system #{system.name}: #{inspect(reason)}"
        )

        {:error, reason}
    end
  end

  # Private helper functions

  defp extract_base_domain do
    base_url = WandererNotifier.Core.Config.map_url()

    if is_nil(base_url) or base_url == "" do
      {:error, "MAP_URL is not configured"}
    else
      # Extract base domain - just the domain without the slug path
      base_domain = base_url |> String.split("/") |> Enum.take(3) |> Enum.join("/")
      {:ok, base_domain}
    end
  end
end
