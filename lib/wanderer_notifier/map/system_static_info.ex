defmodule WandererNotifier.Map.SystemStaticInfo do
  alias WandererNotifier.Map.MapSystem
  alias WandererNotifier.Config
  alias WandererNotifier.Logger.Logger, as: AppLogger

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
    case WandererNotifier.HTTP.get(url, headers) do
      {:ok, %{status_code: 200, body: body}} -> handle_successful_response(body)
      {:ok, %{status_code: status}} -> handle_http_error(status)
      {:error, reason} -> handle_request_error(reason)
    end
  end

  defp handle_successful_response(body) when is_map(body), do: {:ok, body}

  defp handle_successful_response(body) when is_binary(body) do
    case Jason.decode(body) do
      {:ok, parsed_response} -> {:ok, parsed_response}
      {:error, reason} -> handle_json_parse_error(reason)
    end
  end

  defp handle_http_error(status) do
    AppLogger.api_error("[SystemStaticInfo] HTTP error", status: status)
    {:error, {:http_error, status}}
  end

  defp handle_request_error(reason) do
    AppLogger.api_error("[SystemStaticInfo] Request failed", error: inspect(reason))
    {:error, reason}
  end

  defp handle_json_parse_error(reason) do
    AppLogger.api_error("[SystemStaticInfo] Failed to parse JSON", error: inspect(reason))
    {:error, {:json_parse_error, reason}}
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
    with true <- valid_system_id?(system),
         system_id <- get_system_id(system),
         {:ok, static_info} <- get_system_static_info(system_id),
         data_to_merge <- extract_data_from_static_info(static_info),
         enhanced_system <- update_system_with_static_info(system, data_to_merge) do
      {:ok, enhanced_system}
    else
      false ->
        log_invalid_system_id(system)
        {:ok, system}

      {:error, reason} ->
        log_enrichment_failure(system, reason)
        {:ok, system}

      error ->
        log_enrichment_exception(system, error)
        {:ok, system}
    end
  end

  # Helper functions for system enrichment

  defp valid_system_id?(%MapSystem{solar_system_id: id}) when is_integer(id), do: id > 0

  defp valid_system_id?(%MapSystem{solar_system_id: id}) when is_binary(id) do
    case Integer.parse(id) do
      {parsed_id, _} -> parsed_id > 0
      :error -> false
    end
  end

  defp valid_system_id?(%{"solar_system_id" => id}) when is_integer(id), do: id > 0

  defp valid_system_id?(%{"solar_system_id" => id}) when is_binary(id) do
    case Integer.parse(id) do
      {parsed_id, _} -> parsed_id > 0
      :error -> false
    end
  end

  defp valid_system_id?(_), do: false

  defp extract_data_from_static_info(%{"data" => data}) when is_map(data), do: data
  defp extract_data_from_static_info(data) when is_map(data), do: data
  defp extract_data_from_static_info(_), do: %{}

  defp update_system_with_static_info(system, data_to_merge) do
    # First update with basic static info
    enhanced_system = MapSystem.update_with_static_info(system, data_to_merge)

    # Then handle special cases
    enhanced_system
    |> update_security_status(data_to_merge)
    |> update_optional_fields(data_to_merge)
  end

  defp update_security_status(system, data) do
    security_status = parse_security_status(Map.get(data, "security"))
    Map.put(system, :security_status, security_status)
  end

  defp parse_security_status(nil), do: 0.0

  defp parse_security_status(val) when is_binary(val) do
    case Float.parse(val) do
      {f, _} -> f
      :error -> 0.0
    end
  end

  defp parse_security_status(val) when is_number(val), do: val
  defp parse_security_status(_), do: 0.0

  defp update_optional_fields(system, data) do
    optional_fields = [
      :statics,
      :effect_name,
      :class_title,
      :effect_power,
      :is_shattered,
      :region_id,
      :region_name,
      :system_class,
      :triglavian_invasion_status,
      :type_description,
      :constellation_id,
      :constellation_name,
      :static_details,
      :sun_type_id
    ]

    Enum.reduce(optional_fields, system, fn field, acc ->
      case Map.get(data, to_string(field)) do
        nil -> acc
        value -> Map.put(acc, field, value)
      end
    end)
  end

  # Logging helper functions

  defp log_invalid_system_id(system) do
    AppLogger.api_warn(
      "[SystemStaticInfo] Cannot enrich system with invalid ID",
      system_name: system.name,
      system_id: system.solar_system_id,
      system: inspect(system, pretty: true, limit: 1000)
    )
  end

  defp log_enrichment_failure(system, reason) do
    AppLogger.api_warn(
      "[SystemStaticInfo] Could not enrich system",
      system_name: system.name,
      error: inspect(reason),
      system: inspect(system, pretty: true, limit: 1000)
    )
  end

  defp log_enrichment_exception(system, error) do
    log_message =
      [
        "[SystemStaticInfo] Exception during system enrichment:",
        "Error: #{inspect(error)}",
        "System: #{inspect(system, pretty: true, limit: 1000)}"
      ]
      |> Enum.join("\n")

    AppLogger.api_error(log_message)
  end

  defp get_auth_headers do
    api_key = Config.map_token()
    [{"Authorization", "Bearer #{api_key}"}]
  end

  @doc """
  Returns static information about a system.

  ## Parameters
    - system_id: The ID of the system

  ## Returns
    - {:ok, system_info} on success
    - {:error, :not_found} if the system is not found
    - {:error, reason} on other errors
  """
  def get_system_info(system_id) do
    headers = [
      {"Authorization", "Bearer #{Config.map_token()}"},
      {"Content-Type", "application/json"}
    ]

    base_url = Config.map_url_with_name()
    url = "#{base_url}/systems/#{system_id}/static"

    case WandererNotifier.HTTP.get(url, headers) do
      {:ok, %{status_code: 200, body: body}} ->
        {:ok, body}

      {:ok, %{status_code: 404}} ->
        AppLogger.api_debug("[SystemStaticInfo] System not found", system_id: system_id)
        {:error, :not_found}

      {:ok, %{status_code: status}} ->
        AppLogger.api_error("[SystemStaticInfo] API request failed",
          system_id: system_id,
          status: status
        )

        {:error, {:api_error, status}}

      {:error, reason} ->
        AppLogger.api_error("[SystemStaticInfo] Request failed",
          system_id: system_id,
          error: inspect(reason)
        )

        {:error, reason}
    end
  end

  # Helper function to get system_id from both MapSystem structs and maps with string keys
  defp get_system_id(%MapSystem{solar_system_id: id}), do: id
  defp get_system_id(%{"solar_system_id" => id}), do: id
  defp get_system_id(system), do: Map.get(system, :solar_system_id)
end
