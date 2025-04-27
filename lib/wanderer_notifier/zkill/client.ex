defmodule WandererNotifier.ZKill.Client do
  @moduledoc """
  Client for interacting with the ZKillboard API.
  """

  @behaviour WandererNotifier.ZKill.ClientBehaviour

  alias WandererNotifier.Logger.Logger, as: AppLogger

  @doc """
  Gets a single killmail by its ID.
  """
  @impl WandererNotifier.ZKill.ClientBehaviour
  def get_single_killmail(kill_id) do
    client_module().get_single_killmail(kill_id)
  end

  @doc """
  Gets recent kills with an optional limit.
  """
  @impl WandererNotifier.ZKill.ClientBehaviour
  def get_recent_kills(limit \\ 10) do
    client_module().get_recent_kills(limit)
  end

  @doc """
  Gets kills for a specific system with an optional limit.
  """
  @impl WandererNotifier.ZKill.ClientBehaviour
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
  @impl WandererNotifier.ZKill.ClientBehaviour
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

    @behaviour WandererNotifier.ZKill.ClientBehaviour

    @http_client Application.compile_env(:wanderer_notifier, :http_client, HttpClient.Httpoison)
    @base_url "https://zkillboard.com/api"
    @user_agent "WandererNotifier"
    @rate_limit_ms 1000
    @max_retries 3
    @retry_backoff_ms 2000

    @doc """
    Gets a single killmail by its ID.
    """
    @impl WandererNotifier.ZKill.ClientBehaviour
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
    @impl WandererNotifier.ZKill.ClientBehaviour
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
    @impl WandererNotifier.ZKill.ClientBehaviour
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
    @impl WandererNotifier.ZKill.ClientBehaviour
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

    # Helper functions

    defp build_headers do
      [
        {"Accept", "application/json"},
        {"User-Agent", @user_agent},
        {"Cache-Control", "no-cache"}
      ]
    end

    defp build_character_kills_url(character_id, nil) do
      "#{@base_url}/characterID/#{character_id}/"
    end

    defp build_character_kills_url(character_id, %{start: start, end: ending}) do
      start_param = if start, do: "startTime/#{DateTime.to_iso8601(start)}/", else: ""
      end_param = if ending, do: "endTime/#{DateTime.to_iso8601(ending)}/", else: ""

      "#{@base_url}/characterID/#{character_id}/#{start_param}#{end_param}"
    end

    defp make_http_request(url, headers) do
      case @http_client.get(url, headers) do
        {:ok, %{status_code: 200, body: body}} -> {:ok, body}
        {:ok, %{status_code: status_code}} -> {:error, {:http_error, status_code}}
        {:error, reason} -> {:error, reason}
      end
    end

    defp decode_killmail_response(body, kill_id) do
      case Jason.decode(body) do
        {:ok, [killmail]} when is_map(killmail) -> {:ok, killmail}
        {:ok, []} -> {:error, {:not_found, kill_id}}
        {:ok, _other} -> {:error, :invalid_data}
        {:error, reason} -> {:error, {:json_error, reason}}
      end
    end

    defp decode_kills_response(body) do
      case Jason.decode(body) do
        {:ok, kills} when is_list(kills) -> {:ok, kills}
        {:ok, %{"error" => error_msg}} -> {:error, {:api_error, error_msg}}
        {:ok, _} -> {:error, :invalid_data}
        {:error, reason} -> {:error, {:json_error, reason}}
      end
    end

    defp validate_killmail_format(killmail, kill_id) do
      cond do
        not is_map(killmail) ->
          {:error, {:invalid_killmail_format, :not_a_map}}

        is_nil(Map.get(killmail, "killmail_id")) ->
          {:error, {:invalid_killmail_format, :missing_killmail_id}}

        not is_map(Map.get(killmail, "zkb", nil)) ->
          {:error, {:invalid_killmail_format, :missing_zkb_data}}

        true ->
          {:ok, killmail}
      end
    end

    defp make_request_with_retry(request_fn, retry_count \\ 0) do
      case request_fn.() do
        {:ok, _} = result ->
          result

        {:error, reason} when retry_count < @max_retries ->
          AppLogger.api_warn("ZKill request failed, retrying", %{
            retry_count: retry_count + 1,
            max_retries: @max_retries,
            error: inspect(reason)
          })

          :timer.sleep(@retry_backoff_ms * (retry_count + 1))
          make_request_with_retry(request_fn, retry_count + 1)

        {:error, reason} ->
          AppLogger.api_error("ZKill request failed after retries", %{
            retry_count: retry_count,
            max_retries: @max_retries,
            error: inspect(reason)
          })

          {:error, reason}
      end
    end
  end
end
