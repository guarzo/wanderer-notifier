defmodule WandererNotifier.Api.ZKill.Client do
  @moduledoc """
  Client for interacting with the ZKillboard API.
  """

  @behaviour WandererNotifier.Api.ZKill.ClientBehaviour

  @base_url "https://zkillboard.com/api"

  alias WandererNotifier.Logger.Logger, as: AppLogger

  @doc """
  Gets a single killmail by its ID.
  """
  @impl true
  @spec get_single_killmail(integer() | binary()) :: {:ok, map() | list(map())} | {:error, any()}
  def get_single_killmail(kill_id) when is_integer(kill_id) do
    url = "#{@base_url}/killID/#{kill_id}/"

    case HTTPoison.get(url) do
      {:ok, %HTTPoison.Response{status_code: 200, body: body}} when is_binary(body) ->
        case Jason.decode(body) do
          {:ok, []} ->
            AppLogger.api_debug("No killmail found for ID #{kill_id}")
            {:error, :not_found}

          {:ok, data} when is_list(data) or is_map(data) ->
            AppLogger.api_debug("Successfully fetched killmail #{kill_id}")
            {:ok, data}

          {:error, reason} ->
            AppLogger.api_error("Failed to decode zKillboard response: #{inspect(reason)}")
            {:error, {:decode_error, reason}}
        end

      {:error, reason} ->
        AppLogger.api_error("Failed to fetch killmail #{kill_id}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  def get_single_killmail(kill_id) when is_binary(kill_id) do
    case Integer.parse(kill_id) do
      {id, _} -> get_single_killmail(id)
      :error -> {:error, :invalid_kill_id}
    end
  end

  @doc """
  Gets recent kills with an optional limit.
  """
  @impl true
  def get_recent_kills(limit \\ 10) do
    client_module().get_recent_kills(limit)
  end

  @doc """
  Gets kills for a specific system with an optional limit.
  """
  @impl true
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
  @impl true
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

    @behaviour WandererNotifier.Api.ZKill.ClientBehaviour

    alias WandererNotifier.Logger.Logger, as: AppLogger

    @base_url "https://zkillboard.com/api"
    @user_agent "WandererNotifier/1.0"
    @rate_limit_ms 1000
    @max_retries 3
    @retry_backoff_ms 2000

    @doc """
    Gets a single killmail by its ID.
    """
    @impl true
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
    @impl true
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
    @impl true
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
    @impl true
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
          # Add validation to ensure every killmail has a killmail_id
          {valid_kills, invalid_count} = validate_kill_list(kills)

          if invalid_count > 0 do
            AppLogger.api_warn("ZKill response contained invalid killmails", %{
              total_kills: length(kills),
              invalid_kills: invalid_count,
              reason: "missing_killmail_id"
            })
          end

          if valid_kills == [] do
            AppLogger.api_warn("ZKill response contained no valid killmails", %{
              original_count: length(kills)
            })
          end

          {:ok, valid_kills}

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

    # Validate that each kill in the list has a killmail_id
    defp validate_kill_list(kills) do
      {valid, invalid} =
        Enum.split_with(kills, fn kill ->
          # Check that killmail_id exists and is not nil
          kill_has_id = kill_has_valid_id?(kill)

          unless kill_has_id do
            # Log the problematic killmail format
            AppLogger.api_warn("ZKill invalid killmail in response", %{
              reason: "missing_killmail_id",
              killmail_keys: Map.keys(kill),
              sample_data: inspect(kill, limit: 100)
            })
          end

          kill_has_id
        end)

      # Enhance valid kills with defaults and normalization
      enhanced_kills = Enum.map(valid, &ensure_killmail_format/1)

      {enhanced_kills, length(invalid)}
    end

    # Check if a killmail has a valid ID
    defp kill_has_valid_id?(kill) when is_map(kill) do
      cond do
        Map.has_key?(kill, "killmail_id") && not is_nil(kill["killmail_id"]) ->
          true

        Map.has_key?(kill, :killmail_id) && not is_nil(kill.killmail_id) ->
          true

        Map.has_key?(kill, "zkb") && Map.has_key?(kill["zkb"], "killmail_id") &&
            not is_nil(kill["zkb"]["killmail_id"]) ->
          true

        true ->
          false
      end
    end

    defp kill_has_valid_id?(_), do: false

    # Ensure the killmail has a standard format with all required fields
    defp ensure_killmail_format(kill) when is_map(kill) do
      # Make sure the kill has a killmail_id in the top-level
      kill_id =
        cond do
          Map.has_key?(kill, "killmail_id") ->
            kill["killmail_id"]

          Map.has_key?(kill, :killmail_id) ->
            kill.killmail_id

          Map.has_key?(kill, "zkb") && Map.has_key?(kill["zkb"], "killmail_id") ->
            # If ID is in zkb field, move it to top-level
            kill["zkb"]["killmail_id"]

          # This shouldn't happen due to prior validation
          true ->
            nil
        end

      # Make sure the zkb field exists
      zkb_data = Map.get(kill, "zkb", Map.get(kill, :zkb, %{}))

      # Ensure both ID and hash are present
      Map.merge(kill, %{
        "killmail_id" => kill_id,
        "zkb" => ensure_zkb_format(zkb_data, kill_id)
      })
    end

    # Ensure zkb data has required fields
    defp ensure_zkb_format(zkb, kill_id) when is_map(zkb) do
      # Ensure there's a hash field
      Map.put_new(
        zkb,
        "hash",
        Map.get(zkb, :hash, Map.get(zkb, "hash", generate_fallback_hash(kill_id)))
      )
    end

    defp ensure_zkb_format(_, kill_id) do
      # If zkb is missing or not a map, create a minimal valid one
      %{"hash" => generate_fallback_hash(kill_id)}
    end

    # Generate a fallback hash in case it's missing
    # This will only be used for verification but won't work for ESI
    defp generate_fallback_hash(kill_id) when is_integer(kill_id) or is_binary(kill_id) do
      "fallback_#{kill_id}"
    end

    defp generate_fallback_hash(_), do: "invalid"

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
