defmodule WandererNotifier.Domains.Tracking.StaticInfo do
  alias WandererNotifier.Domains.Tracking.Entities.System
  alias WandererNotifier.Shared.Config
  require Logger
  alias WandererNotifier.Infrastructure.Http.ResponseHandler
  alias WandererNotifier.Infrastructure.Http.Headers

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
        Logger.error("[SystemStaticInfo] Failed to get static info",
          system_id: solar_system_id,
          error: inspect(reason),
          category: :api
        )

        {:error, reason}
    end
  end

  # Private helper functions

  defp fetch_system_static_info(solar_system_id) do
    Logger.debug("[SystemStaticInfo] Building URL",
      system_id: solar_system_id,
      category: :api
    )

    base_url = Config.map_url()
    url = "#{base_url}/api/common/system-static-info?id=#{solar_system_id}"
    headers = get_auth_headers()

    Logger.debug("[SystemStaticInfo] Making request",
      url: url,
      headers: headers,
      category: :api
    )

    # Make API request and process
    make_static_info_request(url, headers)
  end

  # Make the actual API request for static info
  defp make_static_info_request(url, headers) do
    # Use high rate limits for internal map API calls
    # These are our own servers so we can afford higher limits
    opts = [
      rate_limit_options: [
        # Much higher limit for internal APIs
        requests_per_second: 1000,
        per_host: true
      ]
    ]

    result = WandererNotifier.Infrastructure.Http.request(:get, url, nil, headers, opts)

    case ResponseHandler.handle_response(result,
           success_codes: [200],
           log_context: %{client: "SystemStaticInfo", url: url}
         ) do
      {:ok, body} ->
        handle_successful_response(body)

      {:error, _reason} = error ->
        Logger.error("[SystemStaticInfo] Request failed")
        error
    end
  end

  defp handle_successful_response(body) when is_map(body), do: {:ok, body}

  defp handle_successful_response(body) when is_binary(body) do
    case Jason.decode(body) do
      {:ok, parsed_response} ->
        {:ok, parsed_response}

      {:error, reason} ->
        Logger.error("[SystemStaticInfo] Failed to parse JSON")
        {:error, {:json_parse_error, reason}}
    end
  end

  @doc """
  Enriches a System with static information.

  ## Parameters
    - system: A WandererNotifier.Domains.SystemTracking.System struct

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
    end
  end

  # Helper functions for system enrichment

  defp valid_system_id?(%System{solar_system_id: id}) when is_integer(id), do: id > 0

  defp valid_system_id?(%System{solar_system_id: id}) when is_binary(id) do
    parsed_id = WandererNotifier.Shared.Config.Utils.parse_int(id, 0)
    parsed_id > 0
  end

  defp valid_system_id?(%{"solar_system_id" => id}) when is_integer(id), do: id > 0

  defp valid_system_id?(%{"solar_system_id" => id}) when is_binary(id) do
    parsed_id = WandererNotifier.Shared.Config.Utils.parse_int(id, 0)
    parsed_id > 0
  end

  defp valid_system_id?(_), do: false

  defp extract_data_from_static_info(%{"data" => data}) when is_map(data), do: data
  defp extract_data_from_static_info(data) when is_map(data), do: data
  defp extract_data_from_static_info(_), do: %{}

  defp update_system_with_static_info(system, data_to_merge) do
    # First update with basic static info
    enhanced_system = Map.merge(system, data_to_merge)

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
    # Log what we're getting from the API
    Logger.info("[StaticInfo] Updating optional fields - Data keys: #{inspect(Map.keys(data))}")
    Logger.info("[StaticInfo] Statics from API: #{inspect(Map.get(data, "statics"))}")
    Logger.info("[StaticInfo] Class title: #{inspect(Map.get(data, "class_title"))}")
    Logger.info("[StaticInfo] Full data sample: #{inspect(data) |> String.slice(0, 500)}")

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

    result =
      Enum.reduce(optional_fields, system, fn field, acc ->
        string_key = to_string(field)

        case Map.get(data, string_key) do
          nil ->
            acc

          value ->
            Logger.debug(
              "[StaticInfo] Setting #{field} = #{inspect(value) |> String.slice(0, 100)}"
            )

            Map.put(acc, field, value)
        end
      end)

    # CRITICAL: Set system_type based on class_title or security
    result = determine_system_type(result, data)

    Logger.info(
      "[StaticInfo] After enrichment - statics: #{inspect(result.statics)}, system_type: #{result.system_type}"
    )

    result
  end

  defp determine_system_type(system, data) do
    cond do
      # If it has a wormhole class (C1-C6), it's a wormhole
      data["class_title"] in ["C1", "C2", "C3", "C4", "C5", "C6"] ->
        Map.put(system, :system_type, "wormhole")

      # If security is -1.0, it's likely a wormhole (J-space)
      data["security"] == "-1.0" ->
        Map.put(system, :system_type, "wormhole")

      # If it starts with J and has numbers, it's a wormhole
      system.name && String.match?(system.name, ~r/^J\d+$/) ->
        Map.put(system, :system_type, "wormhole")

      # Otherwise keep the existing type or set based on security
      true ->
        system
    end
  end

  # Logging helper functions

  defp log_invalid_system_id(system) do
    Logger.warning(
      "[SystemStaticInfo] Cannot enrich system with invalid ID",
      system_name: system.name,
      system_id: system.solar_system_id,
      system: inspect(system, pretty: true, limit: 1000),
      category: :api
    )
  end

  defp log_enrichment_failure(system, reason) do
    Logger.warning(
      "[SystemStaticInfo] Could not enrich system",
      system_name: system.name,
      error: inspect(reason),
      system: inspect(system, pretty: true, limit: 1000),
      category: :api
    )
  end

  defp get_auth_headers do
    Headers.map_api_headers()
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
    headers = Headers.map_api_headers(Config.map_token())

    base_url = Config.map_url()
    map_name = Config.map_name()
    url = "#{base_url}/#{map_name}/systems/#{system_id}/static"

    # Use high rate limits for internal map API calls
    # These are our own servers so we can afford higher limits
    opts = [
      rate_limit_options: [
        # Much higher limit for internal APIs
        requests_per_second: 1000,
        per_host: true
      ]
    ]

    result = WandererNotifier.Infrastructure.Http.request(:get, url, nil, headers, opts)

    ResponseHandler.handle_response(result,
      success_codes: 200,
      custom_handlers: [
        {404,
         fn _status, _body ->
           Logger.debug("[SystemStaticInfo] System not found",
             system_id: system_id,
             category: :api
           )

           {:error, :not_found}
         end}
      ],
      log_context: %{
        client: "SystemStaticInfo",
        system_id: system_id,
        url: url
      }
    )
  end

  # Helper function to get system_id from both System structs and maps with string keys
  defp get_system_id(%System{solar_system_id: id}), do: id
  defp get_system_id(%{"solar_system_id" => id}), do: id
  defp get_system_id(system), do: Map.get(system, :solar_system_id)
end
