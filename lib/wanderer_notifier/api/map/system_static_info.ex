defmodule WandererNotifier.Api.Map.SystemStaticInfo do
  @moduledoc """
  Client for fetching static information about EVE systems from the map API.
  Provides clean access to detailed system information for wormholes and other systems.
  """

  require Logger
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
    # Build the URL with the 'id' parameter instead of 'slug'
    with {:ok, base_domain} <- extract_base_domain(),
         url = "#{base_domain}/api/common/system-static-info?id=#{solar_system_id}",
         headers = UrlBuilder.get_auth_headers() do
      # Log request details for debugging
      Logger.debug("[SystemStaticInfo] Requesting static info for system #{solar_system_id}")
      Logger.debug("[SystemStaticInfo] URL: #{url}")

      # Make the API request
      case Client.get(url, headers) do
        {:ok, response} ->
          # Let the error handler handle the response in a consistent way
          case ErrorHandler.handle_http_response(response, domain: :map, tag: "Map.static_info") do
            {:ok, parsed_response} ->
              # Validate the response structure with our validator
              case ResponseValidator.validate_system_static_info_response(parsed_response) do
                {:ok, data} ->
                  Logger.debug("[SystemStaticInfo] Successfully validated static info")
                  {:ok, data}

                {:error, reason} ->
                  Logger.warning(
                    "[SystemStaticInfo] Invalid system static info: #{inspect(reason)}"
                  )

                  {:error, reason}
              end

            {:error, reason} ->
              Logger.error("[SystemStaticInfo] HTTP error: #{inspect(reason)}")
              {:error, reason}
          end

        {:error, reason} ->
          Logger.error("[SystemStaticInfo] Request failed: #{inspect(reason)}")
          {:error, reason}
      end
    else
      {:error, reason} ->
        Logger.error("[SystemStaticInfo] Failed to construct URL: #{inspect(reason)}")
        {:error, reason}
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
