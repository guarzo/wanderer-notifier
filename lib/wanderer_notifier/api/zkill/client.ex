defmodule WandererNotifier.Api.ZKill.Client do
  @moduledoc """
  Client for interacting with the ZKillboard API.
  """

  @behaviour WandererNotifier.Api.ZKill.ClientBehaviour

  require Logger
  alias WandererNotifier.Logger.Logger, as: AppLogger

  @doc """
  Gets a single killmail by its ID.
  """
  def get_single_killmail(kill_id) do
    client_module().get_single_killmail(kill_id)
  end

  @doc """
  Gets recent kills with an optional limit.
  """
  def get_recent_kills(limit \\ 10) do
    client_module().get_recent_kills(limit)
  end

  @doc """
  Gets kills for a specific system with an optional limit.
  """
  def get_system_kills(system_id, limit \\ 5) do
    client_module().get_system_kills(system_id, limit)
  end

  @doc """
  Gets kills for a specific character.

  ## Parameters
    - character_id: The character ID to fetch kills for
    - date_range: Map with :start and :end DateTime (optional)
    - limit: Maximum number of kills to fetch (default: 100)
  """
  def get_character_kills(character_id, date_range \\ nil, limit \\ 100) do
    client_module().get_character_kills(character_id, date_range, limit)
  end

  defp client_module do
    Application.get_env(:wanderer_notifier, :zkill_client, __MODULE__.HTTP)
  end

  defmodule HTTP do
    @moduledoc """
    HTTP client implementation for ZKillboard API.
    """

    require Logger
    alias WandererNotifier.Logger.Logger, as: AppLogger

    @base_url "https://zkillboard.com/api"
    @user_agent "WandererNotifier/1.0"
    @rate_limit_ms 1000
    @max_retries 3
    @retry_backoff_ms 2000

    @doc """
    Gets a single killmail by its ID.
    """
    def get_single_killmail(kill_id) do
      AppLogger.kill_debug("ZKill single_killmail HTTP request for kill_id: #{kill_id}")

      url = "#{@base_url}/killID/#{kill_id}/"
      headers = build_headers()

      AppLogger.kill_debug("[ZKill] Requesting killmail #{kill_id}")
      :timer.sleep(@rate_limit_ms)

      make_request_with_retry(fn ->
        with {:ok, body} <- make_http_request(url, headers),
             {:ok, decoded} <- decode_killmail_response(body, kill_id) do
          validate_killmail_format(decoded, kill_id)
        end
      end)
    end

    @doc """
    Gets recent kills with an optional limit.
    """
    def get_recent_kills(limit \\ 10) do
      url = "#{@base_url}/recent/"
      headers = build_headers()

      Logger.info("[ZKill] Requesting recent kills (limit: #{limit})")
      :timer.sleep(@rate_limit_ms)

      with {:ok, body} <- make_http_request(url, headers),
           {:ok, kills} <- decode_kills_response(body) do
        {:ok, Enum.take(kills, limit)}
      end
    end

    @doc """
    Gets kills for a specific system with an optional limit.
    """
    def get_system_kills(system_id, limit \\ 5) do
      url = "#{@base_url}/systemID/#{system_id}/"
      headers = build_headers()

      Logger.info("[ZKill] Requesting system kills for #{system_id} (limit: #{limit})")
      :timer.sleep(@rate_limit_ms)

      with {:ok, body} <- make_http_request(url, headers),
           {:ok, kills} <- decode_kills_response(body) do
        {:ok, Enum.take(kills, limit)}
      end
    end

    @doc """
    Gets kills for a specific character.
    """
    def get_character_kills(character_id, date_range \\ nil, limit \\ 100) do
      url = build_character_kills_url(character_id, date_range)
      headers = build_headers()

      Logger.info("[ZKill] Requesting character kills for #{url} (limit: #{limit})")
      :timer.sleep(@rate_limit_ms)

      with {:ok, body} <- make_http_request(url, headers),
           {:ok, kills} <- decode_kills_response(body) do
        {:ok, Enum.take(kills, limit)}
      end
    end

    defp build_headers do
      [
        {"Accept", "application/json"},
        {"User-Agent", @user_agent},
        {"Cache-Control", "no-cache"}
      ]
    end

    defp make_http_request(url, headers) do
      case HTTPoison.get(url, headers, follow_redirect: true) do
        {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
          {:ok, body}

        {:ok, %HTTPoison.Response{status_code: status, body: body}} ->
          AppLogger.api_error("[ZKill] HTTP error",
            status: status,
            body: body
          )

          {:error, {:http_error, status}}

        {:error, reason} ->
          AppLogger.api_error("[ZKill] HTTP request failed",
            error: inspect(reason)
          )

          {:error, reason}
      end
    end

    defp decode_killmail_response(body, kill_id) do
      case Jason.decode(body) do
        {:ok, killmail} when is_map(killmail) ->
          {:ok, killmail}

        {:ok, [killmail]} when is_map(killmail) ->
          {:ok, killmail}

        {:ok, []} ->
          AppLogger.api_warn("[ZKill] No killmail found for ID #{kill_id}")
          {:error, {:domain_error, :zkill, {:not_found, kill_id}}}

        {:ok, killmails} when is_list(killmails) ->
          AppLogger.api_warn("[ZKill] Multiple killmails returned for single ID",
            kill_id: kill_id,
            count: length(killmails)
          )

          [killmail | _] = killmails
          {:ok, killmail}

        {:ok, true} ->
          AppLogger.api_warn("[ZKill] Warning: got `true` from zKill for killmail #{kill_id}")
          {:error, {:domain_error, :zkill, {:unexpected_format, :boolean_true}}}

        {:ok, false} ->
          AppLogger.api_warn("[ZKill] Warning: got `false` from zKill for killmail #{kill_id}")
          {:error, {:domain_error, :zkill, {:unexpected_format, :boolean_false}}}

        {:ok, response} ->
          AppLogger.api_warn("[ZKill] Unexpected response format",
            kill_id: kill_id,
            response_type: typeof(response),
            response: inspect(response, limit: 50)
          )

          {:error, {:domain_error, :zkill, {:unexpected_format, typeof(response)}}}

        {:error, reason} ->
          AppLogger.api_error("[ZKill] JSON decode error",
            kill_id: kill_id,
            error: inspect(reason)
          )

          {:error, {:domain_error, :zkill, {:json_decode_error, reason}}}
      end
    end

    defp decode_kills_response(body) do
      case Jason.decode(body) do
        {:ok, kills} when is_list(kills) ->
          {:ok, kills}

        {:ok, _} ->
          {:error, :invalid_response_format}

        error ->
          error
      end
    end

    defp validate_killmail_format(killmail, kill_id) do
      if Map.has_key?(killmail, "killmail_id") do
        {:ok, killmail}
      else
        AppLogger.api_warn("[ZKill] Invalid killmail format: missing killmail_id",
          kill_id: kill_id,
          response_keys: Map.keys(killmail)
        )

        {:error, {:domain_error, :zkill, {:invalid_format, :missing_killmail_id}}}
      end
    end

    defp build_character_kills_url(character_id, date_range) do
      base_url = "#{@base_url}/characterID/#{character_id}/"

      if date_range do
        params = build_date_range_params(date_range)
        if params != "", do: base_url <> "?#{params}", else: base_url
      else
        base_url
      end
    end

    defp build_date_range_params(date_range) do
      start_param =
        if date_range.start,
          do: "startTime=#{DateTime.to_iso8601(date_range.start)}",
          else: ""

      end_param =
        if date_range.end,
          do: "endTime=#{DateTime.to_iso8601(date_range.end)}",
          else: ""

      Enum.join([start_param, end_param], "&")
    end

    defp make_request_with_retry(request_fn, retry_count \\ 0) do
      case request_fn.() do
        {:error, {:http_error, status}}
        when status in [429, 500, 502, 503, 504] and retry_count < @max_retries ->
          backoff_time = (@retry_backoff_ms * :math.pow(2, retry_count)) |> round()

          Logger.warning(
            "[ZKill] Retrying request after #{backoff_time}ms (attempt #{retry_count + 1}/#{@max_retries})"
          )

          :timer.sleep(backoff_time)
          make_request_with_retry(request_fn, retry_count + 1)

        result ->
          result
      end
    end

    defp typeof(term) when is_struct(term), do: "struct:#{term.__struct__}"
    defp typeof(_), do: "unknown"
  end
end
