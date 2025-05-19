defmodule WandererNotifier.Killmail.ZKillClient do
  @moduledoc """
  Client for interacting with the ZKillboard API.
  """
  @behaviour WandererNotifier.Killmail.ZKillClientBehaviour

  alias WandererNotifier.Logger.Logger, as: AppLogger
  alias WandererNotifier.ESI.Service, as: ESIService
  require Logger

  # -- Configuration --

  @base_url Application.compile_env(:wanderer_notifier, :zkill_base_url,
               "https://zkillboard.com/api/kills"
             )
  @user_agent Application.compile_env(:wanderer_notifier, :zkill_user_agent,
                "WandererNotifier/1.0"
              )
  @max_retries Application.compile_env(:wanderer_notifier, :zkill_max_retries, 3)
  @retry_backoff_ms Application.compile_env(:wanderer_notifier, :zkill_retry_backoff_ms, 2_000)

  @type date_range :: %{start: DateTime.t(), end: DateTime.t()}

  # -- Public Behaviour Implementation --

  @impl true
  @spec get_single_killmail(integer()) :: {:ok, map()} | {:error, any()}
  def get_single_killmail(kill_id) do
    url = "#{@base_url}/killID/#{kill_id}/"
    handle_single_request(url, kill_id)
  end

  @impl true
  @spec get_recent_kills(non_neg_integer()) :: {:ok, [map()]} | {:error, any()}
  def get_recent_kills(limit \\ 10) do
    url = "#{@base_url}/recent/"
    handle_list_request(url, limit, :get_recent_kills)
  end

  @impl true
  @spec get_system_kills(integer(), non_neg_integer()) :: {:ok, [map()]} | {:error, any()}
  def get_system_kills(system_id, limit \\ 5) do
    url = "#{@base_url}/systemID/#{system_id}/"
    handle_list_request(url, limit, :get_system_kills)
  end

  @impl true
  @spec get_character_kills(integer(), date_range() | nil, non_neg_integer()) ::
          {:ok, [map()]} | {:error, any()}
  def get_character_kills(character_id, date_range \\ nil, limit \\ 100) do
    url = build_character_url(character_id, date_range)
    handle_list_request(url, limit, :get_character_kills)
  end

  # -- Internal Request Handlers --

  defp handle_single_request(url, id) do
    log_api(:get_single_killmail, url: url, kill_id: id)

    with {:ok, body} <- perform_request(url),
         {:ok, parsed} <- parse_response(body),
         {:ok, kill} <- extract_single(parsed, id) do
      {:ok, kill}
    end
  end

  defp handle_list_request(url, limit, method) do
    log_api(method, url: url, limit: limit)

    with {:ok, body} <- perform_request(url),
         {:ok, parsed} <- parse_response(body) do
      items = parsed |> List.wrap() |> Enum.take(limit)

      AppLogger.api_debug("ZKill processed list", %{
        method: method,
        items: length(items),
        limit: limit
      })

      {:ok, format_kills(items)}
    end
  end

  # -- HTTP + Retry Pipeline --

  defp perform_request(url), do: retry(fn -> make_http_request(url) end, 0)

  defp retry(fun, attempt) when attempt < @max_retries do
    case fun.() do
      {:ok, resp} ->
        {:ok, resp}

      {:error, reason} ->
        Logger.warning("ZKill request error: #{inspect(reason)}, retry ##{attempt + 1}")
        :timer.sleep(@retry_backoff_ms * (attempt + 1))
        retry(fun, attempt + 1)
    end
  end

  defp retry(_, attempt), do: {:error, {:max_retries_reached, attempt}}

  # -- Raw HTTP Request (via configured HTTP client) --

  defp make_http_request(url) do
    headers = [
      {"Accept", "application/json"},
      {"User-Agent", @user_agent},
      {"Cache-Control", "no-cache"}
    ]

    opts = [recv_timeout: 5_000, timeout: 5_000, follow_redirect: true]

    client = Application.get_env(
      :wanderer_notifier,
      :http_client,
      WandererNotifier.HttpClient.Httpoison
    )

    case client.get(url, headers, opts) do
      {:ok, %{status_code: 200, body: body}} ->
        AppLogger.api_debug("ZKill response OK", %{url: url, sample: sample(body)})
        {:ok, body}

      {:ok, %{status_code: status, body: body}} ->
        error_info = try_parse_error_body(body)
        AppLogger.api_error("ZKill HTTP error", %{status: status, url: url, error: error_info})
        {:error, {:http_error, status}}

      {:error, reason} ->
        Logger.error("ZKill HTTP client error: #{inspect(reason)}")
        {:error, reason}
    end
  end

  # -- Decode JSON or pass through maps/lists --

  defp parse_response(body) when is_binary(body) do
    case Jason.decode(body) do
      {:ok, decoded} -> {:ok, decoded}
      _ -> {:error, :invalid_json}
    end
  end

  defp parse_response(data), do: {:ok, data}

  # -- Single Kill Extraction --

  defp extract_single(list, id) when is_list(list) do
    case hd(list) do
      %{"killmail_id" => _} = item -> {:ok, item}
      _ -> {:error, {:not_found, id}}
    end
  end

  defp extract_single(%{"killmail_id" => _} = map, _), do: {:ok, map}
  defp extract_single(_, id), do: {:error, {:unexpected_format, id}}

  # -- URL Builders --

  defp build_character_url(id, nil), do: "#{@base_url}/characterID/#{id}/"

  defp build_character_url(id, %{start: s, end: e}) do
    start_iso = DateTime.to_iso8601(s)
    end_iso = DateTime.to_iso8601(e)

    "#{@base_url}/characterID/#{id}/startTime/#{start_iso}/endTime/#{end_iso}/"
  end

  # -- Formatting Kills into Strings --

  defp format_kills(kills), do: Enum.map(kills, &format_kill/1)

  defp format_kill(kill) do
    kill_id = Map.get(kill, "killmail_id", "Unknown")
    zkb = Map.get(kill, "zkb", %{})
    value = Map.get(zkb, "totalValue", 0) || Map.get(zkb, "destroyedValue", 0) || 0
    hash = Map.get(zkb, "hash")

    Logger.info("Formatting kill #{kill_id} hash=#{hash}")

    details = get_kill_details(kill_id, hash)
    {ship_id, victim_id} = extract_ids(details)

    ship   = get_name(ship_id, &ESIService.get_ship_type_name/2, "Unknown Ship")
    victim = get_name(victim_id, &ESIService.get_character_info/2,   "Unknown")
    time   = format_time(details)

    "[#{ship} (#{format_isk(value)})](https://zkillboard.com/kill/#{kill_id}/) - #{victim} #{time}"
  rescue
    e ->
      Logger.warning("Error formatting kill #{Exception.message(e)}")
      "Unknown kill"
  end

  defp get_kill_details(_id, nil), do: nil

  defp get_kill_details(id, hash) do
    case ESIService.get_killmail(id, hash) do
      {:ok, resp}   -> resp
      {:error, _} -> nil
    end
  end

  defp extract_ids(nil), do: {nil, nil}

  defp extract_ids(details) do
    victim = Map.get(details, "victim", %{})
    {Map.get(victim, "ship_type_id"), Map.get(victim, "character_id")}
  end

  defp get_name(nil, _fun, default), do: default

  defp get_name(id, fun, default) do
    case fun.(id, []) do
      {:ok, %{"name" => name}} -> name
      _ -> default
    end
  end

  # -- Relative Time Formatting --

  defp format_time(nil), do: ""

  defp format_time(details) do
    with time_str when is_binary(time_str) <- Map.get(details, "killmail_time"),
         {:ok, dt, _} <- DateTime.from_iso8601(time_str) do
      diff = DateTime.diff(DateTime.utc_now(), dt)
      format_diff(diff)
    else
      _ -> ""
    end
  end

  defp format_diff(sec) when sec < 60,       do: "(just now)"
  defp format_diff(sec) when sec < 3_600,    do: "(#{div(sec, 60)}m ago)"
  defp format_diff(sec) when sec < 86_400,  do: "(#{div(sec, 3_600)}h ago)"
  defp format_diff(sec),                      do: "(#{div(sec, 86_400)}d ago)"

  # -- ISK Formatting --

  defp format_isk(v) when is_number(v) do
    cond do
      v >= 1_000_000_000 -> "#{Float.round(v / 1_000_000_000, 1)}B ISK"
      v >=   1_000_000  -> "#{Float.round(v /   1_000_000, 1)}M ISK"
      v >=     1_000    -> "#{Float.round(v /     1_000, 1)}K ISK"
      true               -> "#{trunc(v)} ISK"
    end
  end

  defp format_isk(_), do: "0 ISK"

  # -- Utilities --

  defp sample(body) when is_binary(body), do: String.slice(body, 0, 200)
  defp sample(_),                       do: ""

  defp try_parse_error_body(body) when is_binary(body) do
    case Jason.decode(body) do
      {:ok, json} -> json
      _           -> nil
    end
  end

  defp log_api(method, meta), do: AppLogger.api_info("ZKill #{method}", meta)
end
