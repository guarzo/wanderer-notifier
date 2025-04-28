defmodule WandererNotifier.Killmail.ZKill.Client do
  @moduledoc """
  Client for interacting with the ZKillboard API.
  """

  @behaviour WandererNotifier.Killmail.ZKill.ClientBehaviour

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

    alias WandererNotifier.Logger.Logger, as: AppLogger
    alias WandererNotifier.HttpClient

    @http_client Application.compile_env(:wanderer_notifier, :http_client, HttpClient.HTTPoison)
    @base_url "https://zkillboard.com/api"
    @user_agent "WandererNotifier/1.0"
    @rate_limit_ms 1000
    @max_retries 3
    @retry_backoff_ms 2000

    @doc """
    Gets a single killmail by its ID.
    """
    def get_single_killmail(kill_id) do
      AppLogger.api_debug("ZKill requesting single killmail", %{
        kill_id: kill_id,
        method: "get_single_killmail"
      })

      url = "#{@base_url}/killID/#{kill_id}/"
      headers = build_headers()

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

      AppLogger.api_info("ZKill requesting recent kills", %{
        limit: limit,
        method: "get_recent_kills"
      })

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

      AppLogger.api_info("ZKill requesting system kills", %{
        system_id: system_id,
        limit: limit,
        method: "get_system_kills"
      })

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

      date_range_info =
        if date_range,
          do: %{
            start_time: date_range.start && DateTime.to_iso8601(date_range.start),
            end_time: date_range.end && DateTime.to_iso8601(date_range.end)
          },
          else: %{date_range: "none"}

      AppLogger.api_info(
        "ZKill requesting character kills",
        Map.merge(
          %{
            character_id: character_id,
            limit: limit,
            method: "get_character_kills",
            url: url
          },
          date_range_info
        )
      )

      :timer.sleep(@rate_limit_ms)

      with {:ok, body} <- make_http_request(url, headers),
           {:ok, kills} <- decode_kills_response(body) do
        kill_count = length(kills)
        limited_kills = Enum.take(kills, limit)

        AppLogger.api_debug("ZKill character kills retrieved", %{
          character_id: character_id,
          total_kills: kill_count,
          limited_kills: length(limited_kills)
        })

        {:ok, limited_kills}
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
      case @http_client.request(:get, url, headers, nil, follow_redirect: true) do
        {:ok, %{status_code: 200, body: body}} ->
          {:ok, body}

        {:ok, %{status_code: status_code, body: body}} ->
          AppLogger.api_error("ZKill HTTP error", %{
            status: status_code,
            body_sample: String.slice(inspect(body) || "", 0, 200),
            url: url
          })

          {:error, {:http_error, status_code}}

        {:error, reason} ->
          AppLogger.api_error("ZKill HTTP request failed", %{
            error: inspect(reason),
            url: url
          })

          {:error, reason}
      end
    end

    defp decode_killmail_response(body, kill_id) do
      case Jason.decode(body) do
        {:ok, [killmail | _]} when is_map(killmail) ->
          {:ok, killmail}

        {:ok, []} ->
          AppLogger.api_error("ZKill empty response for kill_id", %{kill_id: kill_id})
          {:error, :killmail_not_found}

        {:ok, non_list_response} ->
          AppLogger.api_error("ZKill unexpected response format", %{
            response: inspect(non_list_response)
          })

          {:error, :invalid_response_format}

        {:error, %Jason.DecodeError{} = error} ->
          AppLogger.api_error("ZKill JSON decode error", %{
            error: inspect(error),
            body_sample: String.slice(body || "", 0, 200)
          })

          {:error, {:json_decode_error, error}}
      end
    end

    defp decode_kills_response(body) do
      case Jason.decode(body) do
        {:ok, kills} when is_list(kills) ->
          {:ok, kills}

        {:ok, data} ->
          AppLogger.api_error("ZKill unexpected response format", %{
            type: inspect(data),
            sample: String.slice(inspect(data), 0, 100)
          })

          {:error, :invalid_response_format}

        {:error, %Jason.DecodeError{} = error} ->
          AppLogger.api_error("ZKill JSON decode error", %{
            error: inspect(error),
            body_sample: String.slice(body || "", 0, 200)
          })

          {:error, {:json_decode_error, error}}
      end
    end

    defp validate_killmail_format(killmail, kill_id) do
      with true <- is_map(killmail),
           true <- Map.has_key?(killmail, "killmail_id"),
           true <- validate_zkb_section(killmail) do
        # Successful validation
        {:ok, killmail}
      else
        false ->
          # Validation failed
          AppLogger.api_error("ZKill invalid killmail format", %{
            kill_id: kill_id,
            killmail_keys: Map.keys(killmail),
            has_zkb: Map.has_key?(killmail, "zkb")
          })

          {:error, :invalid_killmail_format}

        error ->
          # Other error
          AppLogger.api_error("ZKill killmail validation failed", %{
            kill_id: kill_id,
            error: inspect(error)
          })

          {:error, error}
      end
    end

    defp validate_zkb_section(killmail) do
      Map.has_key?(killmail, "zkb") and is_map(killmail["zkb"])
    end

    defp make_request_with_retry(request_fun, retries \\ 0)

    defp make_request_with_retry(request_fun, retries) when retries < @max_retries do
      case request_fun.() do
        {:error, reason} ->
          AppLogger.api_debug("ZKill request failed, attempting retry", %{
            retry: retries + 1,
            max_retries: @max_retries,
            reason: inspect(reason)
          })

          # Exponential backoff
          :timer.sleep(@retry_backoff_ms * 2 ** retries)
          make_request_with_retry(request_fun, retries + 1)

        result ->
          result
      end
    end

    defp make_request_with_retry(_request_fun, retries) do
      AppLogger.api_error("ZKill max retries exceeded", %{retries: retries})
      {:error, :max_retries_exceeded}
    end

    defp build_character_kills_url(character_id, date_range) do
      base = "#{@base_url}/characterID/#{character_id}/"

      if date_range do
        # Add date parameters if a range was provided
        params = []

        params =
          if date_range.start do
            [
              "startTime=#{date_range.start |> Calendar.strftime("%Y%m%d%H%M")}"
              | params
            ]
          else
            params
          end

        params =
          if date_range.end do
            [
              "endTime=#{date_range.end |> Calendar.strftime("%Y%m%d%H%M")}"
              | params
            ]
          else
            params
          end

        if Enum.empty?(params) do
          base
        else
          base <> "?" <> Enum.join(params, "&")
        end
      else
        base
      end
    end
  end
end
