defmodule WandererNotifier.Domains.Killmail.Enrichment do
  @moduledoc """
  Handles fetching recent kills via WandererKills API for system notifications
  and provides caching utilities for killmail-related data.

  This module was previously responsible for ESI enrichment, but with the migration
  to WebSocket with pre-enriched data, it now handles recent kills lookup and
  system name caching (merged from Killmail.Cache).
  """

  alias WandererNotifier.Infrastructure.{Http, Cache}
  alias WandererNotifier.Shared.Utils.ErrorHandler
  require Logger

  @doc """
  Fetches and formats the latest kills for a system (default 3).
  """
  @spec recent_kills_for_system(integer(), non_neg_integer()) :: String.t()
  def recent_kills_for_system(system_id, limit \\ 3) do
    ErrorHandler.safe_execute_string(
      fn -> process_system_kills_request(system_id, limit) end,
      fallback: "Error retrieving kill data",
      context: %{system_id: system_id, limit: limit}
    )
  end

  # Process system kills request and format response
  defp process_system_kills_request(system_id, limit) do
    case get_system_kills(system_id, limit) do
      {:ok, kills} when is_list(kills) and length(kills) > 0 ->
        format_kills_list(kills)

      {:ok, []} ->
        "No recent kills found"

      {:error, _reason} ->
        "Error retrieving kill data"

      _resp ->
        "Unexpected kill data response"
    end
  end

  # Format list of kills into a string
  defp format_kills_list(kills) do
    kills
    |> Enum.map(&format_wanderer_kill/1)
    |> Enum.join("\n")
  end

  @doc """
  Gets a system name from the cache or from the API.
  Merged from WandererNotifier.Domains.Killmail.Cache.

  ## Parameters
  - system_id: The ID of the system to get name for

  ## Returns
  - System name string or "System [ID]" if not found
  """
  def get_system_name(nil), do: "Unknown"

  def get_system_name(system_id) when is_integer(system_id) do
    # Use the simplified cache directly
    cache_key = "esi:system_name:#{system_id}"

    case Cache.get(cache_key) do
      {:ok, name} when is_binary(name) ->
        name

      _ ->
        # No cached name, fetch from ESI
        case esi_service().get_system(system_id, []) do
          {:ok, %{"name" => name}} when is_binary(name) ->
            # Cache the name with 1 hour TTL
            Cache.put(cache_key, name, :timer.hours(1))
            name

          _ ->
            "System #{system_id}"
        end
    end
  end

  def get_system_name(system_id) when is_binary(system_id) do
    case Integer.parse(system_id) do
      {id, ""} -> get_system_name(id)
      _ -> "System #{system_id}"
    end
  end

  # --- Private Functions ---

  @spec get_system_kills(integer(), non_neg_integer()) :: {:ok, [map()]} | {:error, any()}
  defp get_system_kills(system_id, limit) do
    url = build_system_kills_url(system_id, limit)

    case fetch_with_fallback(url) do
      {:ok, result} ->
        parse_kills_response({:ok, result})

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp build_system_kills_url(system_id, limit) do
    base_url =
      Application.get_env(
        :wanderer_notifier,
        :wanderer_kills_base_url,
        "http://host.docker.internal:4004"
      )

    # Back to the original endpoint that works
    "#{base_url}/api/v1/kills/system/#{system_id}?limit=#{limit}&since_hours=48"
  end

  defp fetch_with_fallback(url) do
    case Req.get(url, retry: false, connect_options: [timeout: 10_000]) do
      {:ok, %Req.Response{status: status, body: body}} ->
        json_body = safely_encode_json(body)
        log_request_result(status, body, url)
        {:ok, %{status_code: status, body: json_body}}

      {:error, reason} ->
        Logger.error("[Enrichment] Direct Req failed", reason: inspect(reason), url: url)
        Logger.warning("[Enrichment] Falling back to Http client")
        Http.request(:get, url, nil, [], service: :wanderer_kills)
    end
  end

  defp log_request_result(200, _body, _url) do
    Logger.debug("[Enrichment] Direct Req success - status: 200")
  end

  defp log_request_result(status, body, url) do
    body_preview = inspect(body) |> String.slice(0, 200)

    Logger.info(
      "[Enrichment] Direct Req non-200 status - status: #{status}, url: #{url}, body: #{body_preview}"
    )
  end

  defp parse_kills_response({:ok, %{status_code: 200, body: body}}) when is_binary(body) do
    case Jason.decode(body) do
      {:ok, decoded} -> handle_decoded_response(decoded)
      {:error, _} -> handle_json_decode_error()
    end
  end

  defp parse_kills_response({:ok, %{status_code: status, body: body}}) do
    Logger.error("[Enrichment] HTTP error", status: status, body: inspect(body))
    {:error, {:http_error, status}}
  end

  # Handle different decoded response formats
  defp handle_decoded_response(decoded) do
    case decoded do
      # Handle wrapped response format: {"data": {"kills": [...]}}
      %{"data" => %{"kills" => kills}} when is_list(kills) ->
        log_kills_found(kills, "wrapped response")
        {:ok, kills}

      # Handle direct array response: [...]
      kills when is_list(kills) ->
        log_kills_found(kills, "direct response")
        {:ok, kills}

      # Handle systems endpoint response: {"kills": [...]}
      %{"kills" => kills} when is_list(kills) ->
        log_kills_found(kills, "systems endpoint")
        {:ok, kills}

      # Handle other potential formats
      other ->
        handle_unexpected_format(other)
    end
  end

  # Log kills found with source
  defp log_kills_found(kills, source) do
    Logger.debug("[Enrichment] Got #{length(kills)} kills from #{source}")
  end

  # Handle unexpected response format
  defp handle_unexpected_format(other) do
    Logger.error("[Enrichment] Unexpected response format",
      response: inspect(other) |> String.slice(0, 200)
    )

    {:ok, []}
  end

  # Handle JSON decode error
  defp handle_json_decode_error do
    Logger.error("[Enrichment] Invalid JSON response")
    {:error, :invalid_json}
  end

  # Format a kill from WandererKills API
  defp format_wanderer_kill(kill) do
    killmail_id = Map.get(kill, "killmail_id", "Unknown")

    ErrorHandler.safe_execute_string(
      fn ->
        case get_detailed_killmail(killmail_id) do
          {:ok, detailed_kill} ->
            format_detailed_kill(detailed_kill, killmail_id)

          {:error, _reason} ->
            format_enhanced_zkb_kill(kill, killmail_id)
        end
      end,
      fallback: "Unknown kill",
      context: %{kill_data: kill}
    )
  end

  # Fetch detailed killmail data from WandererKills API
  defp get_detailed_killmail(killmail_id) do
    url = build_killmail_url(killmail_id)

    case fetch_killmail_data(url, killmail_id) do
      {:ok, result} ->
        parse_killmail_response({:ok, result}, killmail_id)

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp build_killmail_url(killmail_id) do
    base_url =
      Application.get_env(
        :wanderer_notifier,
        :wanderer_kills_base_url,
        "http://host.docker.internal:4004"
      )

    "#{base_url}/api/v1/killmail/#{killmail_id}"
  end

  defp fetch_killmail_data(url, killmail_id) do
    case Req.get(url, retry: false, connect_options: [timeout: 10_000]) do
      {:ok, %Req.Response{status: status, body: body}} ->
        json_body = safely_encode_json(body)
        {:ok, %{status_code: status, body: json_body}}

      {:error, reason} ->
        Logger.debug("Failed to fetch detailed killmail",
          killmail_id: killmail_id,
          reason: inspect(reason)
        )

        {:error, reason}
    end
  end

  defp safely_encode_json(body) when is_map(body) do
    case Jason.encode(body) do
      {:ok, json} ->
        json

      {:error, _} ->
        Logger.warning("[Enrichment] Failed to encode response body to JSON")
        "{}"
    end
  end

  defp safely_encode_json(body) when is_binary(body), do: body

  defp safely_encode_json(_body) do
    Logger.warning("[Enrichment] Unexpected body type, using empty JSON")
    "{}"
  end

  defp parse_killmail_response({:ok, %{status_code: 200, body: body}}, _killmail_id)
       when is_binary(body) do
    case Jason.decode(body) do
      {:ok, %{"data" => kill_data}} -> {:ok, kill_data}
      {:ok, decoded} -> {:ok, decoded}
      {:error, _} -> {:error, :invalid_json}
    end
  end

  defp parse_killmail_response({:ok, %{status_code: 404, body: _body}}, killmail_id) do
    Logger.debug(
      "[Enrichment] Detailed killmail not found (expected for some older kills) - killmail_id: #{killmail_id}"
    )

    {:error, :not_found}
  end

  defp parse_killmail_response({:ok, %{status_code: status, body: body}}, killmail_id) do
    body_preview = inspect(body) |> String.slice(0, 200)

    Logger.warning(
      "[Enrichment] Detailed killmail HTTP error - status: #{status}, killmail_id: #{killmail_id}, body: #{body_preview}"
    )

    {:error, {:http_error, status}}
  end

  # Format detailed kill with player name, corp ticker, ship, value, and time
  defp format_detailed_kill(detailed_kill, killmail_id) do
    victim = Map.get(detailed_kill, "victim", %{})
    zkb_data = Map.get(detailed_kill, "zkb", %{})

    # Extract victim info
    character_name = Map.get(victim, "character_name", "Unknown")
    corporation_id = Map.get(victim, "corporation_id")

    corp_ticker = get_corporation_ticker_from_victim(victim, corporation_id)
    corp_ticker_link = create_corporation_link(corp_ticker, corporation_id)
    ship_name = Map.get(victim, "ship_name", "Unknown Ship")

    # Extract value and time
    value = Map.get(zkb_data, "totalValue", 0)
    kill_time = Map.get(detailed_kill, "kill_time")

    # Format components
    value_str = format_isk_value(value)
    time_str = if kill_time, do: " #{format_kill_time(kill_time)}", else: ""

    "[#{character_name}](https://zkillboard.com/kill/#{killmail_id}/) (#{corp_ticker_link}) - #{ship_name} - #{value_str}#{time_str}"
  end

  # Enhanced formatting using available zkb data when detailed data fails
  defp format_enhanced_zkb_kill(kill, killmail_id) do
    zkb_data = Map.get(kill, "zkb", %{})

    kill_components = extract_kill_components(zkb_data)
    time_str = format_time_from_kill(kill)

    build_enhanced_kill_string(kill_components, killmail_id, time_str)
  end

  # Extract kill components to reduce complexity
  defp extract_kill_components(zkb_data) do
    %{
      kill_type: determine_kill_type(zkb_data),
      location_info: extract_location_info(zkb_data),
      value: Map.get(zkb_data, "totalValue", 0),
      points: Map.get(zkb_data, "points", 0)
    }
  end

  # Build the enhanced kill string from components
  defp build_enhanced_kill_string(components, killmail_id, time_str) do
    value_str = format_isk_value(components.value)

    "[#{value_str} #{components.kill_type}](https://zkillboard.com/kill/#{killmail_id}/)#{components.location_info} (#{components.points} pts)#{time_str}"
  end

  defp format_kill_time(time_str) when is_binary(time_str) do
    case DateTime.from_iso8601(time_str) do
      {:ok, dt, _} ->
        diff_seconds = DateTime.diff(DateTime.utc_now(), dt, :second)
        format_time_diff(diff_seconds)

      _ ->
        ""
    end
  end

  defp format_kill_time(_), do: ""

  defp format_time_diff(sec) when sec < 60, do: "(just now)"
  defp format_time_diff(sec) when sec < 3_600, do: "(#{div(sec, 60)}m ago)"
  defp format_time_diff(sec) when sec < 86_400, do: "(#{div(sec, 3_600)}h ago)"
  defp format_time_diff(sec), do: "(#{div(sec, 86_400)}d ago)"

  defp format_isk_value(v) when is_number(v) do
    cond do
      v >= 1_000_000_000 -> "#{Float.round(v / 1_000_000_000, 1)}B ISK"
      v >= 1_000_000 -> "#{Float.round(v / 1_000_000, 1)}M ISK"
      v >= 1_000 -> "#{Float.round(v / 1_000, 1)}K ISK"
      true -> "#{trunc(v)} ISK"
    end
  end

  defp format_isk_value(_), do: "0 ISK"

  # Get corporation ticker from corporation ID via ESI API
  defp get_corporation_ticker(nil), do: "UNKN"

  defp get_corporation_ticker(corporation_id) when is_integer(corporation_id) do
    cache_key = "esi:corporation:#{corporation_id}"

    case Cache.get(cache_key) do
      {:ok, %{"ticker" => ticker}} when is_binary(ticker) ->
        ticker

      _ ->
        # Fetch from ESI and cache the result
        case esi_service().get_corporation_info(corporation_id, []) do
          {:ok, %{"ticker" => ticker}} when is_binary(ticker) ->
            # Cache corporation data for 24 hours
            Cache.put(cache_key, %{"ticker" => ticker}, :timer.hours(24))
            ticker

          _ ->
            "UNKN"
        end
    end
  end

  defp get_corporation_ticker(_), do: "UNKN"

  # Get corporation ticker from victim data or fetch via ESI
  defp get_corporation_ticker_from_victim(victim, corporation_id) do
    case get_in(victim, ["corporation", "ticker"]) do
      ticker when is_binary(ticker) -> ticker
      _ -> get_corporation_ticker(corporation_id)
    end
  end

  defp create_corporation_link(corp_ticker, corporation_id) do
    if corporation_id do
      "[#{corp_ticker}](https://zkillboard.com/corporation/#{corporation_id}/)"
    else
      corp_ticker
    end
  end

  # Helper functions for enhanced zkb kill formatting

  defp determine_kill_type(zkb_data) do
    cond do
      Map.get(zkb_data, "npc", false) -> "NPC Kill"
      Map.get(zkb_data, "solo", false) -> "Solo Kill"
      Map.get(zkb_data, "awox", false) -> "Awox Kill"
      true -> "Kill"
    end
  end

  defp extract_location_info(zkb_data) do
    case Map.get(zkb_data, "locationID") do
      location_id when is_integer(location_id) -> " in #{location_id}"
      _ -> ""
    end
  end

  defp format_time_from_kill(kill) do
    case Map.get(kill, "killmail_time") do
      time_str when is_binary(time_str) -> format_kill_time(time_str)
      _ -> ""
    end
  end

  # Dependency injection helper (merged from Cache module)
  defp esi_service,
    do:
      Application.get_env(
        :wanderer_notifier,
        :esi_service,
        WandererNotifier.Infrastructure.Adapters.ESI.Service
      )
end
