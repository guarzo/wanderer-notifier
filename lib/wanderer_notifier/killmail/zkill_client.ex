defmodule WandererNotifier.Killmail.ZKillClient do
  @moduledoc """
  Client for interacting with the ZKillboard API.
  """

  @behaviour WandererNotifier.Killmail.ZKillClientBehaviour

  alias WandererNotifier.Logger.Logger, as: AppLogger
  alias WandererNotifier.HttpClient.Httpoison, as: HttpClient

  @base_url "https://zkillboard.com/api/kills"
  @user_agent "WandererNotifier/1.0"
  @rate_limit_ms 1000
  @max_retries 3
  @retry_backoff_ms 2000

  @impl true
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

  @impl true
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

  @impl true
  @doc """
  Gets kills for a specific system with an optional limit.
  """
  def get_system_kills(system_id, limit \\ 5) do
    url = "#{@base_url}/systemID/#{system_id}/"
    headers = build_headers()

    :timer.sleep(@rate_limit_ms)

    with {:ok, body} <- make_http_request(url, headers),
         {:ok, kills} <- decode_kills_response(body) do
      {:ok, Enum.take(kills, limit)}
    end
  end

  @impl true
  @doc """
  Gets kills for a specific character.

  ## Parameters
    - character_id: The character ID to fetch kills for
    - date_range: Map with :start and :end DateTime (optional)
    - limit: Maximum number of kills to fetch (default: 100)
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
    # Increase timeout for debugging
    options = [recv_timeout: 10_000, timeout: 10_000]

    case HttpClient.get(url, headers, options) do
      {:ok, %{status_code: 200, body: body}} ->
        {:ok, body}

      {:ok, %{status_code: status, body: body}} ->
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

  defp handle_decode_error(reason, body, kill_id) do
    AppLogger.api_error("ZKill JSON decode error", %{
      error: inspect(reason),
      body_sample: String.slice(body || "", 0, 200),
      kill_id: kill_id
    })

    {:error, {:json_decode_error, reason}}
  end

  defp decode_kills_response(body) do
    case Jason.decode(body) do
      {:ok, kills} when is_list(kills) ->
        {:ok, kills}

      {:ok, _non_list} ->
        {:error, {:domain_error, :zkill, :invalid_kills_format}}

      {:error, reason} ->
        {:error, {:json_decode_error, reason}}
    end
  end

  defp build_character_kills_url(character_id, date_range) do
    base = "#{@base_url}/characterID/#{character_id}/"

    case date_range do
      nil ->
        base

      %{start: start_time, end: end_time} when not is_nil(start_time) and not is_nil(end_time) ->
        start_str = DateTime.to_date(start_time) |> Date.to_iso8601()
        end_str = DateTime.to_date(end_time) |> Date.to_iso8601()
        "#{base}startTime/#{start_str}/endTime/#{end_str}/"

      _ ->
        base
    end
  end

  defp make_request_with_retry(request_fn, retries \\ 0) do
    case request_fn.() do
      {:ok, result} ->
        {:ok, result}

      {:error, _reason} when retries < @max_retries ->
        :timer.sleep(@retry_backoff_ms * (retries + 1))
        make_request_with_retry(request_fn, retries + 1)

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp log_zkill_warning(kill_id, type, message, extra_fields \\ %{}) do
    AppLogger.api_warn(
      "ZKill #{message}",
      Map.merge(
        %{
          kill_id: kill_id,
          warning_type: type
        },
        extra_fields
      )
    )
  end

  defp typeof(term) when is_nil(term), do: "nil"
  defp typeof(term) when is_binary(term), do: "string"
  defp typeof(term) when is_boolean(term), do: "boolean"
  defp typeof(term) when is_number(term), do: "number"
  defp typeof(term) when is_map(term), do: "map"
  defp typeof(term) when is_list(term), do: "list"
  defp typeof(term) when is_atom(term), do: "atom"
  defp typeof(_term), do: "unknown"

  defp validate_killmail_format(killmail, _kill_id), do: {:ok, killmail}
end
