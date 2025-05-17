defmodule WandererNotifier.Killmail.ZKillClient do
  @moduledoc """
  Client for interacting with the ZKillboard API.
  """

  @behaviour WandererNotifier.Killmail.ZKillClientBehaviour

  alias WandererNotifier.Logger.Logger, as: AppLogger
  require Logger

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

    with {:ok, decoded} <- request_and_decode(url) do
      decode_single(decoded, Keyword.get(opts, :kill_id))
    end
  end

  defp fetch_list(url, opts) do
    method = Keyword.get(opts, :method)
    log_info(method, opts)

    with {:ok, decoded} <- request_and_decode(url) do
      # At this point, decoded should either be already processed strings or an empty list
      if is_list(decoded) do
        # Just take the number of items we need
        limit = Keyword.get(opts, :limit, 10)
        result = Enum.take(decoded, limit)

        # Log that we processed and limited the results
        AppLogger.api_debug("ZKill processed list", %{
          items: length(result),
          method: method,
          limit: limit
        })

        {:ok, result}
      else
        AppLogger.api_warn("Unexpected decoded data format", %{
          format: inspect(decoded)
        })

        {:ok, []}
      end
    end
  end

  defp request_and_decode(url) do
    :timer.sleep(@rate_limit_ms)

    fn_request = fn -> make_http_request(url) end

    case make_request_with_retry(fn_request, 0) do
      {:ok, response} ->
        # Log response type for debugging
        require Logger

        # Safe type analysis
        response_type = typemap(response)

        response_keys =
          cond do
            is_map(response) ->
              Map.keys(response)

            is_list(response) && length(response) > 0 && is_map(hd(response)) ->
              Map.keys(hd(response))

            true ->
              []
          end

        response_sample =
          if is_map(response),
            do: inspect(Map.get(response, :body, "no body")),
            else: inspect(response)

        Logger.info(
          "ZKill response analysis: type=#{response_type}, keys=#{inspect(response_keys)}, sample=#{String.slice(response_sample, 0, 100)}"
        )

        # Process the response based on its type
        process_zkill_response(response, url)

      {:error, error_details} = _error ->
        # Get detailed info about the error type and what happened
        error_type = typemap(error_details)
        status_code = Process.get(:last_zkill_status, nil)
        error_str = inspect(error_details)

        # Log with detailed information
        Logger.error(
          "[ZKill API] Failed after retries: Error type: #{error_type}, Status: #{status_code}, Details: #{error_str}"
        )

        {:error, error_details}
    end
  rescue
    e ->
      Logger.error("Exception in ZKill request_and_decode: #{inspect(e)}")
      {:ok, ["Error retrieving zkill data"]}
  end

  # Helper function to process ZKill responses
  defp process_zkill_response(response, url) do
    if is_list(response) do
      # Handle list type responses (direct JSON array)
      # Take the limit from the URL if possible
      limit =
        case Regex.run(~r/limit\/(\d+)\//, url) do
          [_, limit_str] -> String.to_integer(limit_str)
          # Default limit
          _ -> 10
        end

      # Only take the number we need before formatting
      kills = Enum.take(response, limit)

      # Try to format them - if it fails, return a safe message
      try do
        kill_strings = format_kills_from_list(kills)
        {:ok, kill_strings}
      rescue
        e ->
          Logger.error("Error formatting kills list: #{Exception.message(e)}")
          {:ok, ["Error processing kill data"]}
      end
    else
      # Try to decode JSON if it's a string
      if is_binary(response) do
        try do
          case Jason.decode(response) do
            {:ok, decoded} when is_list(decoded) ->
              process_zkill_response(decoded, url)

            {:ok, decoded} when is_map(decoded) ->
              Logger.info("Received map response from ZKill, expected list")
              {:ok, ["ZKill API response format changed"]}

            _ ->
              {:ok, ["ZKill API data unavailable at this time"]}
          end
        rescue
          e ->
            Logger.error("Error decoding JSON response: #{Exception.message(e)}")
            {:ok, ["Error processing ZKill data"]}
        end
      else
        # Handle any other response types with a safe fallback
        {:ok, ["ZKill API data unavailable at this time"]}
      end
    end
  end

  # Format a list of kill data maps into simple strings
  defp format_kills_from_list(kills) when is_list(kills) do
    require Logger

    # Get the ESI service
    esi_service = get_esi_service()

    # Process each kill individually, with safe handling
    kills
    |> Enum.map(fn kill ->
      try do
        format_single_kill(kill, esi_service)
      rescue
        e ->
          Logger.warning("Error formatting kill: #{Exception.message(e)}")
          "Unknown kill"
      end
    end)
  end

  # Fallback for non-list inputs
  defp format_kills_from_list(_), do: ["No kill data available"]

  # Get the configured ESI service
  defp get_esi_service do
    Application.get_env(:wanderer_notifier, :esi_service, WandererNotifier.ESI.Service)
  end

  # Format a single kill record into a formatted string
  defp format_single_kill(kill, esi_service) do
    require Logger

    try do
      # Extract the basic information we need
      kill_id = Map.get(kill, "killmail_id", "Unknown")

      # Get value from zkb object
      zkb = Map.get(kill, "zkb", %{})
      value = extract_kill_value(zkb)
      hash = Map.get(zkb, "hash")

      # Log for debugging
      Logger.info("Processing kill: #{kill_id} with hash: #{hash}")

      # Get kill details from ESI
      kill_details = get_kill_details(kill_id, hash, esi_service)

      # Parse kill_details if it's a string (JSON)
      kill_details = parse_if_string(kill_details)

      # Extract ship and victim information
      {ship_type_id, victim_id} = extract_ship_and_victim_ids(kill_details)

      # Get ship and victim names
      ship_name = get_ship_name(ship_type_id, esi_service)
      victim_name = get_victim_name(victim_id, esi_service)

      # Format time string
      time_ago = format_kill_time(kill_details)

      # Format the kill data into a detailed string with link
      "[#{ship_name} (#{format_isk(value)})](https://zkillboard.com/kill/#{kill_id}/) - #{victim_name} #{time_ago}"
    rescue
      e ->
        Logger.warning("Error formatting kill data: #{Exception.message(e)}")
        "Unknown Ship (0 ISK) - Unknown"
    end
  end

  # Parse a string to JSON if needed
  defp parse_if_string(nil), do: nil

  defp parse_if_string(data) when is_binary(data) do
    case Jason.decode(data) do
      {:ok, parsed} -> parsed
      {:error, _} -> %{}
    end
  end

  defp parse_if_string(data), do: data

  # Extract the kill value from ZKB data
  defp extract_kill_value(zkb) do
    Map.get(zkb, "totalValue", 0) || Map.get(zkb, "destroyedValue", 0) || 0
  end

  # Get kill details from ESI
  defp get_kill_details(_kill_id, nil, _esi_service), do: nil

  defp get_kill_details(kill_id, hash, esi_service) do
    require Logger

    case esi_service.get_killmail(kill_id, hash) do
      {:ok, details} ->
        # Log a small portion of the response to help with debugging
        response_preview =
          case details do
            str when is_binary(str) -> String.slice(str, 0, 100)
            map when is_map(map) -> inspect(map, limit: 2)
            other -> inspect(other)
          end

        Logger.debug(
          "ESI killmail response format: type=#{typemap(details)}, preview=#{response_preview}"
        )

        details

      {:error, reason} ->
        Logger.warning("Failed to get kill details from ESI: #{inspect(reason)}")
        nil
    end
  end

  # Extract ship type ID and victim ID from kill details
  defp extract_ship_and_victim_ids(nil), do: {nil, nil}

  defp extract_ship_and_victim_ids(kill_details) do
    require Logger

    try do
      victim = Map.get(kill_details, "victim", %{})

      ship_type_id = Map.get(victim, "ship_type_id")
      character_id = Map.get(victim, "character_id")

      Logger.debug(
        "Extracted IDs from kill details - Ship Type ID: #{inspect(ship_type_id)}, Character ID: #{inspect(character_id)}"
      )

      {ship_type_id, character_id}
    rescue
      e ->
        Logger.warning(
          "Error extracting ship/victim IDs: #{Exception.message(e)}, data type: #{typemap(kill_details)}, data: #{inspect(kill_details, limit: 5)}"
        )

        {nil, nil}
    end
  end

  # Get ship name from ship type ID
  defp get_ship_name(nil, _esi_service), do: "Unknown Ship"

  defp get_ship_name(ship_type_id, esi_service) do
    require Logger

    # Convert ship_type_id to integer if it's a string
    ship_type_id =
      if is_binary(ship_type_id) do
        case Integer.parse(ship_type_id) do
          {id, _} -> id
          :error -> ship_type_id
        end
      else
        ship_type_id
      end

    case esi_service.get_ship_type_name(ship_type_id, []) do
      {:ok, %{"name" => name}} ->
        name

      {:ok, data} when is_map(data) ->
        Map.get(data, "name", "Unknown Ship")

      {:ok, data} when is_binary(data) ->
        case Jason.decode(data) do
          {:ok, %{"name" => name}} -> name
          _ -> "Unknown Ship"
        end

      error ->
        Logger.debug("Failed to get ship name: #{inspect(error)}")
        "Unknown Ship"
    end
  end

  # Get victim name from victim ID
  defp get_victim_name(nil, _esi_service), do: "Unknown"

  defp get_victim_name(victim_id, esi_service) do
    require Logger

    # Convert victim_id to integer if it's a string
    victim_id =
      if is_binary(victim_id) do
        case Integer.parse(victim_id) do
          {id, _} -> id
          :error -> victim_id
        end
      else
        victim_id
      end

    case esi_service.get_character_info(victim_id, []) do
      {:ok, %{"name" => name}} ->
        name

      {:ok, data} when is_map(data) ->
        Map.get(data, "name", "Unknown")

      {:ok, data} when is_binary(data) ->
        case Jason.decode(data) do
          {:ok, %{"name" => name}} -> name
          _ -> "Unknown"
        end

      error ->
        Logger.debug("Failed to get character name: #{inspect(error)}")
        "Unknown"
    end
  end

  # Format kill time into a relative time string
  defp format_kill_time(nil), do: ""

  defp format_kill_time(kill_details) do
    kill_time = Map.get(kill_details, "killmail_time")
    format_time_string(kill_time)
  end

  # Format time string from kill data
  defp format_time_string(nil), do: ""

  defp format_time_string(time_str) do
    try do
      case DateTime.from_iso8601(time_str) do
        {:ok, datetime, _} ->
          now = DateTime.utc_now()
          diff_seconds = DateTime.diff(now, datetime)
          format_time_diff(diff_seconds)

        _ ->
          ""
      end
    rescue
      _ -> ""
    end
  end

  # Format time difference
  defp format_time_diff(seconds) when seconds < 60, do: "(just now)"
  defp format_time_diff(seconds) when seconds < 3600, do: "(#{div(seconds, 60)}m ago)"
  defp format_time_diff(seconds) when seconds < 86_400, do: "(#{div(seconds, 3600)}h ago)"
  defp format_time_diff(seconds), do: "(#{div(seconds, 86_400)}d ago)"

  # Format ISK value
  defp format_isk(value) when is_number(value) do
    cond do
      value >= 1_000_000_000 -> "#{Float.round(value / 1_000_000_000, 1)}B ISK"
      value >= 1_000_000 -> "#{Float.round(value / 1_000_000, 1)}M ISK"
      value >= 1_000 -> "#{Float.round(value / 1_000, 1)}K ISK"
      true -> "#{trunc(value)} ISK"
    end
  end

  defp format_isk(_), do: "0 ISK"

  # Helper function to get the type of any value as a string
  defp typemap(value) when is_binary(value), do: "binary"
  defp typemap(value) when is_list(value), do: "list"
  defp typemap(value) when is_map(value), do: "map"
  defp typemap(value) when is_struct(value), do: "struct:#{inspect(value.__struct__)}"
  defp typemap(value) when is_tuple(value), do: "tuple:#{tuple_size(value)}"
  defp typemap(value) when is_atom(value), do: "atom:#{value}"
  defp typemap(value) when is_integer(value), do: "integer:#{value}"
  defp typemap(value) when is_float(value), do: "float:#{value}"
  defp typemap(value) when is_function(value), do: "function"
  defp typemap(value) when is_pid(value), do: "pid"
  defp typemap(value) when is_port(value), do: "port"
  defp typemap(value) when is_reference(value), do: "reference"
  defp typemap(_), do: "unknown"

  defp log_info(method, meta) do
    AppLogger.api_info("ZKill #{method}", Map.new(meta))
  end

  @spec make_http_request(String.t()) :: {:ok, String.t() | map()} | {:error, any()}
  defp make_http_request(url) do
    headers = build_headers()
    opts = [recv_timeout: 5_000, timeout: 5_000, follow_redirect: true]

    try do
      case http_client().get(url, headers, opts) do
        {:ok, %{status_code: 200, body: body}} ->
          AppLogger.api_debug("ZKill response OK", %{url: url, sample: sample(body)})
          {:ok, body}

        {:ok, %{status_code: status, body: body}} ->
          # Parse body to see if there's additional error information
          body_preview = sample(body)
          parsed_error = try_parse_error_body(body)

          AppLogger.api_error("ZKill HTTP error", %{
            status: status,
            url: url,
            sample: body_preview,
            parsed_error: parsed_error
          })

          # Log the error with more details
          Logger.error(
            "[ZKill API] HTTP error: Status #{status}, URL: #{url}, Response: #{body_preview}, Parsed: #{inspect(parsed_error)}"
          )

          {:error, {:http_error, status}}

        {:error, %HTTPoison.Error{reason: :timeout}} ->
          AppLogger.api_error("ZKill request timeout", %{url: url})
          {:error, :timeout}

        {:error, %HTTPoison.Error{reason: :econnrefused}} ->
          AppLogger.api_error("ZKill connection refused", %{url: url})
          {:error, :connection_refused}

        {:error, %HTTPoison.Error{reason: :closed}} ->
          AppLogger.api_error("ZKill connection closed", %{url: url})
          {:error, :connection_closed}

        {:error, %HTTPoison.Error{reason: reason}} ->
          AppLogger.api_error("ZKill HTTPoison error", %{
            error_type: "HTTPoison.Error",
            reason: inspect(reason),
            url: url
          })

          {:error, {:httpoison_error, reason}}

        {:error, reason} ->
          AppLogger.api_error("ZKill request failed", %{error: inspect(reason), url: url})
          {:error, reason}
      end
    rescue
      e ->
        stacktrace = Exception.format_stacktrace(__STACKTRACE__)
        error_struct = inspect(e.__struct__)
        error_message = Exception.message(e)

        AppLogger.api_error("Exception in ZKill HTTP request", %{
          error_type: error_struct,
          message: error_message,
          url: url,
          stacktrace: stacktrace
        })

        Logger.error("[ZKill API] Exception: #{error_struct} - #{error_message}\n#{stacktrace}")
        {:error, {:exception, error_message, error_struct}}
    catch
      kind, reason ->
        stacktrace = Exception.format_stacktrace(__STACKTRACE__)
        reason_type = typemap(reason)
        reason_str = inspect(reason)

        AppLogger.api_error("Caught error in ZKill HTTP request", %{
          kind: kind,
          reason_type: reason_type,
          reason: reason_str,
          url: url,
          stacktrace: stacktrace
        })

        Logger.error("[ZKill API] Caught #{kind}: #{reason_type} - #{reason_str}\n#{stacktrace}")
        {:error, {:caught, {kind, reason}}}
    end
  end

  defp decode_single([single] = _list, _id) when is_map(single), do: {:ok, single}
  defp decode_single(%{} = single, _id), do: {:ok, single}

  defp decode_single(list, id) when is_list(list) and length(list) > 0 do
    # The API sometimes returns a list of maps, try to extract the first one
    case hd(list) do
      %{"killmail_id" => _} = single ->
        # If we have a killmail_id, it's a valid killmail response
        {:ok, single}

      _ ->
        AppLogger.api_warn("No killmail found in list", %{kill_id: id})
        {:error, {:not_found, id}}
    end
  end

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

  defp sample(body) when is_binary(body) do
    if String.valid?(body) do
      String.slice(body, 0, 200)
    else
      inspect(binary_part(body, 0, min(200, byte_size(body))))
    end
  end

  defp sample(other), do: inspect(other)

  defp build_headers do
    [
      {"Accept", "application/json"},
      {"User-Agent", @user_agent},
      {"Cache-Control", "no-cache"}
    ]
  end

  defp http_client do
    # Use the HttpClient.Httpoison module directly, which has the get/3 function
    # This is the HTTP client that was originally expected here
    WandererNotifier.HttpClient.Httpoison
  end

  defp make_request_with_retry(request_fn, r) when r < @max_retries do
    case request_fn.() do
      {:ok, res} ->
        {:ok, res}

      {:error, :timeout} ->
        # Timeouts are transient, we should retry
        Process.put(:last_zkill_error, :timeout)
        Process.put(:last_zkill_status, nil)
        AppLogger.api_warn("ZKill API timeout, retrying", %{attempt: r + 1, max: @max_retries})
        :timer.sleep(@retry_backoff_ms * (r + 1))
        make_request_with_retry(request_fn, r + 1)

      {:error, :connection_refused} ->
        # Connection refusals indicate service might be down, long backoff
        Process.put(:last_zkill_error, :connection_refused)
        Process.put(:last_zkill_status, nil)

        AppLogger.api_warn("ZKill API connection refused, retrying with longer delay", %{
          attempt: r + 1,
          max: @max_retries
        })

        :timer.sleep(@retry_backoff_ms * (r + 1) * 2)
        make_request_with_retry(request_fn, r + 1)

      {:error, :connection_closed} ->
        # Connection closed might be temporary
        Process.put(:last_zkill_error, :connection_closed)
        Process.put(:last_zkill_status, nil)

        AppLogger.api_warn("ZKill API connection closed, retrying", %{
          attempt: r + 1,
          max: @max_retries
        })

        :timer.sleep(@retry_backoff_ms * (r + 1))
        make_request_with_retry(request_fn, r + 1)

      {:error, {:exception, message, type}} ->
        # Log detailed exception information
        Process.put(:last_zkill_error, {:exception, message, type})
        Process.put(:last_zkill_status, nil)

        AppLogger.api_error("ZKill API exception, retrying", %{
          attempt: r + 1,
          max: @max_retries,
          error_type: type,
          message: message
        })

        :timer.sleep(@retry_backoff_ms * (r + 1))
        make_request_with_retry(request_fn, r + 1)

      {:error, {:httpoison_error, reason}} ->
        # Log specific HTTPoison error
        Process.put(:last_zkill_error, {:httpoison_error, reason})
        Process.put(:last_zkill_status, nil)

        AppLogger.api_error("ZKill API HTTPoison error, retrying", %{
          attempt: r + 1,
          max: @max_retries,
          reason: inspect(reason)
        })

        :timer.sleep(@retry_backoff_ms * (r + 1))
        make_request_with_retry(request_fn, r + 1)

      {:error, {:http_error, status}} ->
        # Store HTTP status code separately
        Process.put(:last_zkill_error, :http_error)
        Process.put(:last_zkill_status, status)

        AppLogger.api_error("ZKill API HTTP error, retrying", %{
          attempt: r + 1,
          max: @max_retries,
          status: status
        })

        :timer.sleep(@retry_backoff_ms * (r + 1))
        make_request_with_retry(request_fn, r + 1)

      {:error, error} ->
        # Log the actual error data structure in detail
        error_type = typemap(error)
        Process.put(:last_zkill_error, {error_type, inspect(error)})
        Process.put(:last_zkill_status, nil)

        AppLogger.api_error("ZKill API error, retrying", %{
          attempt: r + 1,
          max: @max_retries,
          error_type: error_type,
          error: inspect(error)
        })

        :timer.sleep(@retry_backoff_ms * (r + 1))
        make_request_with_retry(request_fn, r + 1)
    end
  end

  defp make_request_with_retry(_request_fn, retries) do
    # Improve error logging with more detailed information
    AppLogger.api_error("ZKill API max retries reached", %{
      retries: retries,
      max_allowed: @max_retries,
      last_error: Process.get(:last_zkill_error, "unknown"),
      last_status: Process.get(:last_zkill_status, "unknown")
    })

    {:error, :max_retries_reached}
  end

  # Try to parse error body for additional information
  defp try_parse_error_body(body) when is_binary(body) do
    try do
      case Jason.decode(body) do
        {:ok, json} when is_map(json) ->
          # Extract common error fields from JSON responses
          %{
            error: Map.get(json, "error"),
            message: Map.get(json, "message"),
            code: Map.get(json, "code"),
            description: Map.get(json, "description")
          }
          |> Enum.filter(fn {_, v} -> v != nil end)
          |> Map.new()

        _ ->
          # If it's not JSON or not a map, return nil
          nil
      end
    rescue
      _ -> nil
    end
  end

  defp try_parse_error_body(_), do: nil
end
