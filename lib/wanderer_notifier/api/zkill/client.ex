defmodule WandererNotifier.Api.ZKill.Client do
  @moduledoc """
  Client for interacting with the ZKillboard API.
  """

  @behaviour WandererNotifier.Api.ZKill.ClientBehaviour

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
      case HTTPoison.get(url, headers, follow_redirect: true) do
        {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
          {:ok, body}

        {:ok, %HTTPoison.Response{status_code: status, body: body}} ->
          AppLogger.api_error("ZKill HTTP error", %{
            status: status,
            body_sample: String.slice(body || "", 0, 200),
            url: url
          })

          {:error, {:http_error, status}}

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
        {:ok, response} ->
          handle_decoded_response(response, kill_id)

        {:error, reason} ->
          handle_decode_error(reason, body, kill_id)
      end
    end

    # Handle different types of successful response formats
    defp handle_decoded_response(response, kill_id) do
      cond do
        # Single killmail map
        is_map(response) ->
          {:ok, response}

        # Single killmail in a list
        is_list(response) && length(response) == 1 ->
          [killmail] = response
          {:ok, killmail}

        # Empty list - no killmail found
        is_list(response) && response == [] ->
          log_zkill_warning(kill_id, "empty_response", "No killmail found")
          {:error, {:domain_error, :zkill, {:not_found, kill_id}}}

        # Multiple killmails - unexpected but we can take the first one
        is_list(response) ->
          log_zkill_warning(
            kill_id,
            "multiple_killmails",
            "Multiple killmails returned for single ID",
            %{count: length(response)}
          )

          [killmail | _] = response
          {:ok, killmail}

        # Boolean or other unexpected formats
        true ->
          format_type = typeof(response)

          log_zkill_warning(kill_id, "unexpected_format", "Unexpected response format", %{
            format_type: format_type
          })

          {:error, {:domain_error, :zkill, {:unexpected_format, format_type}}}
      end
    end

    # Handle JSON decode errors
    defp handle_decode_error(reason, body, kill_id) do
      AppLogger.api_error("ZKill JSON decode error", %{
        kill_id: kill_id,
        error: inspect(reason),
        body_sample: String.slice(body || "", 0, 200)
      })

      {:error, {:domain_error, :zkill, {:json_decode_error, reason}}}
    end

    # Helper to log ZKill warnings consistently
    defp log_zkill_warning(kill_id, reason, message, extra_metadata \\ %{}) do
      metadata = Map.merge(%{kill_id: kill_id, reason: reason}, extra_metadata)
      AppLogger.api_warn("ZKill #{message}", metadata)
    end

    defp decode_kills_response(body) do
      case Jason.decode(body) do
        {:ok, kills} when is_list(kills) ->
          {:ok, kills}

        {:ok, response} ->
          AppLogger.api_error("ZKill invalid kills response format", %{
            response_type: typeof(response),
            response_sample: inspect(response, limit: 50)
          })

          {:error, :invalid_response_format}

        {:error, reason} ->
          AppLogger.api_error("ZKill JSON decode error for kills", %{
            error: inspect(reason),
            body_sample: String.slice(body || "", 0, 200)
          })

          {:error, {:json_decode_error, reason}}
      end
    end

    defp validate_killmail_format(killmail, kill_id) do
      if Map.has_key?(killmail, "killmail_id") do
        {:ok, killmail}
      else
        AppLogger.api_warn("ZKill invalid killmail format", %{
          kill_id: kill_id,
          reason: "missing_killmail_id",
          response_keys: Map.keys(killmail)
        })

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

          AppLogger.api_warn("ZKill retrying request after error", %{
            status_code: status,
            retry_count: retry_count + 1,
            max_retries: @max_retries,
            backoff_ms: backoff_time
          })

          :timer.sleep(backoff_time)
          make_request_with_retry(request_fn, retry_count + 1)

        result ->
          result
      end
    end

    defp typeof(term) when is_boolean(term), do: "boolean"
    defp typeof(term) when is_binary(term), do: "string"
    defp typeof(term) when is_number(term), do: "number"
    defp typeof(term) when is_list(term), do: "list"
    defp typeof(term) when is_map(term), do: "map"
    defp typeof(term) when is_atom(term), do: "atom"
    defp typeof(term) when is_function(term), do: "function"
    defp typeof(term) when is_pid(term), do: "pid"
    defp typeof(term) when is_reference(term), do: "reference"
    defp typeof(term) when is_tuple(term), do: "tuple"
    defp typeof(term) when is_struct(term), do: "struct:#{term.__struct__}"
    defp typeof(_), do: "unknown"
  end
end
