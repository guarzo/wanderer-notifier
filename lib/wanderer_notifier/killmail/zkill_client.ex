defmodule WandererNotifier.Killmail.ZKillClient do
  @moduledoc """
  Client for interacting with the ZKillboard API.
  """

  @behaviour WandererNotifier.Killmail.ZKillClientBehaviour

  alias WandererNotifier.Logger.Logger, as: AppLogger

  @base_url Application.compile_env(
              :wanderer_notifier,
              :zkill_base_url,
              "https://zkillboard.com/api/kills"
            )
  @user_agent Application.compile_env(
                :wanderer_notifier,
                :zkill_user_agent,
                "WandererNotifier/1.0"
              )
  @rate_limit_ms Application.compile_env(:wanderer_notifier, :zkill_rate_limit_ms, 1_000)
  @max_retries Application.compile_env(:wanderer_notifier, :zkill_max_retries, 3)
  @retry_backoff_ms Application.compile_env(:wanderer_notifier, :zkill_retry_backoff_ms, 2_000)

  @type date_range :: %{start: DateTime.t(), end: DateTime.t()}

  @impl true
  @spec get_single_killmail(integer()) :: {:ok, map()} | {:error, any()}
  def get_single_killmail(kill_id) do
    fetch_kill("#{@base_url}/killID/#{kill_id}/", kill_id: kill_id)
  end

  @impl true
  @spec get_recent_kills(non_neg_integer()) :: {:ok, [map()]} | {:error, any()}
  def get_recent_kills(limit \\ 10) do
    fetch_list("#{@base_url}/recent/", limit: limit, method: "get_recent_kills")
  end

  @impl true
  @spec get_system_kills(integer(), non_neg_integer()) :: {:ok, [map()]} | {:error, any()}
  def get_system_kills(system_id, limit \\ 5) do
    fetch_list("#{@base_url}/systemID/#{system_id}/",
      limit: limit,
      method: "get_system_kills",
      system_id: system_id
    )
  end

  @impl true
  @spec get_character_kills(integer(), date_range() | nil, non_neg_integer()) ::
          {:ok, [map()]} | {:error, any()}
  def get_character_kills(character_id, date_range \\ nil, limit \\ 100) do
    url = build_character_url(character_id, date_range)

    fetch_list(url,
      limit: limit,
      method: "get_character_kills",
      character_id: character_id,
      date_range: format_date_range(date_range)
    )
  end

  # PRIVATE PIPELINE

  defp fetch_kill(url, opts) do
    method = Keyword.get(opts, :method, "get_single_killmail")
    log_info(method, opts)

    with {:ok, decoded} <- request_and_decode(url),
         {:ok, result} <- decode_single(decoded, Keyword.get(opts, :kill_id)) do
      {:ok, result}
    end
  end

  defp fetch_list(url, opts) do
    method = Keyword.get(opts, :method)
    log_info(method, opts)

    with {:ok, decoded} <- request_and_decode(url) do
      list = if is_list(decoded), do: decoded, else: []
      {:ok, Enum.take(list, Keyword.get(opts, :limit, 10))}
    end
  end

  defp request_and_decode(url) do
    :timer.sleep(@rate_limit_ms)

    fn_request = fn -> make_http_request(url) end

    make_request_with_retry(fn_request)
    |> case do
      {:ok, body} -> decode_response(body)
      err -> err
    end
  end

  defp log_info(method, meta) do
    AppLogger.api_info("ZKill #{method}", Map.new(meta))
  end

  @spec make_http_request(String.t()) :: {:ok, String.t()} | {:error, any()}
  defp make_http_request(url) do
    headers = build_headers()
    opts = [recv_timeout: 10_000, timeout: 10_000]

    case http_client().get(url, headers, opts) do
      {:ok, %{status_code: 200, body: body}} ->
        AppLogger.api_debug("ZKill response OK", %{url: url, sample: sample(body)})
        {:ok, body}

      {:ok, %{status_code: status, body: body}} ->
        AppLogger.api_error("ZKill HTTP error", %{status: status, url: url, sample: sample(body)})
        {:error, {:http_error, status}}

      {:error, reason} ->
        AppLogger.api_error("ZKill request failed", %{error: inspect(reason), url: url})
        {:error, reason}
    end
  end

  defp decode_response(body) do
    case Jason.decode(body) do
      {:ok, %{"error" => err}} ->
        AppLogger.api_warn("ZKill returned error", %{error: err})
        {:ok, []}

      other ->
        other
    end
  end

  defp decode_single([single] = _list, _id) when is_map(single), do: {:ok, single}
  defp decode_single(single = %{}, _id), do: {:ok, single}

  defp decode_single([], id) do
    AppLogger.api_warn("No killmail found", %{kill_id: id})
    {:error, {:not_found, id}}
  end

  defp decode_single(_other, id) do
    AppLogger.api_warn("Unexpected format", %{kill_id: id})
    {:error, {:unexpected_format, id}}
  end

  defp build_character_url(id, nil), do: "#{@base_url}/characterID/#{id}/"

  defp build_character_url(id, %{start: s, end: e}) do
    start_iso = DateTime.to_iso8601(s)
    end_iso = DateTime.to_iso8601(e)

    "#{@base_url}/characterID/#{id}/startTime/#{start_iso}/endTime/#{end_iso}/"
  end

  defp format_date_range(nil), do: "none"

  defp format_date_range(%{start: s, end: e}),
    do: %{start_time: DateTime.to_iso8601(s), end_time: DateTime.to_iso8601(e)}

  defp sample(body) when is_binary(body), do: String.slice(body, 0, 200)
  defp sample(other), do: inspect(other)

  defp build_headers do
    [
      {"Accept", "application/json"},
      {"User-Agent", @user_agent},
      {"Cache-Control", "no-cache"}
    ]
  end

  defp http_client do
    Application.get_env(:wanderer_notifier, :http_client, WandererNotifier.HttpClient.Httpoison)
  end

  defp make_request_with_retry(request_fn, retries \\ 0)

  defp make_request_with_retry(request_fn, r) when r < @max_retries do
    case request_fn.() do
      {:ok, res} ->
        {:ok, res}

      {:error, _} ->
        :timer.sleep(@retry_backoff_ms * (r + 1))
        make_request_with_retry(request_fn, r + 1)
    end
  end

  defp make_request_with_retry(request_fn, _), do: request_fn.()
end
