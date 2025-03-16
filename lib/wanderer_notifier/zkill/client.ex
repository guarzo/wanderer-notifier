defmodule WandererNotifier.ZKill.Client do
  @moduledoc """
  Low-level zKillboard API client.
  """

  require Logger
  alias WandererNotifier.Http.Client, as: HttpClient

  @user_agent "my-corp-killbot/1.0 (contact me@example.com)"
  # ^ Adjust or move this to config so that zKill sees you as a real user.

  def get_single_killmail(kill_id) do
    url = "https://zkillboard.com/api/killID/#{kill_id}/"

    headers = [
      {"User-Agent", @user_agent}
      # {"Accept", "application/json"} or others if you like
    ]

    # Centralized building of cURL command (in Http.Client now):
    curl_example = HttpClient.build_curl_command("GET", url, headers)

    case HttpClient.request("GET", url, headers) do
      {:ok, %{status_code: 200, body: body}} ->
        case Jason.decode(body) do
          # zKill sometimes returns just "true" or "false" as bare JSON.
          {:ok, true} ->
            Logger.warning("""
            [ZKill] Warning: got `true` from zKill for killmail #{kill_id}.
            This often means rate-limiting or kill not found.
            Sample cURL to reproduce:
            #{curl_example}
            """)

            {:error, :zkb_returned_true}

          {:ok, parsed} ->
            {:ok, parsed}

          {:error, decode_err} ->
            Logger.error("""
            [ZKill] JSON decode error for killmail #{kill_id}: #{inspect(decode_err)}
            Sample cURL to reproduce:
            #{curl_example}
            """)

            {:error, :json_error}

          _other ->
            Logger.error("[ZKill] Unexpected JSON decode result for killmail #{kill_id}.")
            {:error, :unexpected_json_decode}
        end

      {:ok, %{status_code: status, body: body}} ->
        Logger.error("""
        [ZKill] Unexpected HTTP status=#{status} for killmail #{kill_id}.
        Body: #{body}
        Sample cURL to reproduce:
        #{curl_example}
        """)

        {:error, {:unexpected_status, status}}

      {:error, reason} ->
        Logger.error("""
        [ZKill] HTTP request error for killmail #{kill_id}: #{inspect(reason)}
        Sample cURL to reproduce:
        #{curl_example}
        """)

        {:error, reason}

      _other ->
        Logger.error("[ZKill] Unhandled response for killmail #{kill_id}.")
        {:error, :unhandled_response}
    end
  end

  @doc """
  Retrieves recent kills from zKillboard.

  ## Parameters

  - `limit`: The maximum number of kills to retrieve (default: 10)

  ## Returns

  - `{:ok, kills}`: A list of recent kills
  - `{:error, reason}`: If an error occurred
  """
  def get_recent_kills(limit \\ 10) do
    url = "https://zkillboard.com/api/kills/"

    headers = [
      {"User-Agent", @user_agent}
    ]

    # Centralized building of cURL command (in Http.Client now):
    curl_example = HttpClient.build_curl_command("GET", url, headers)

    case HttpClient.request("GET", url, headers) do
      {:ok, %{status_code: 200, body: body}} ->
        case Jason.decode(body) do
          {:ok, parsed} when is_list(parsed) ->
            # Take only the requested number of kills
            result = Enum.take(parsed, limit)
            {:ok, result}

          {:ok, _} ->
            Logger.warning("""
            [ZKill] Warning: unexpected response format from zKill for recent kills.
            Sample cURL to reproduce:
            #{curl_example}
            """)
            {:error, :unexpected_response_format}

          {:error, decode_err} ->
            Logger.error("""
            [ZKill] JSON decode error for recent kills: #{inspect(decode_err)}
            Sample cURL to reproduce:
            #{curl_example}
            """)
            {:error, :json_error}
        end

      {:ok, %{status_code: status}} ->
        Logger.error("[ZKill] HTTP error #{status} when fetching recent kills")
        {:error, {:http_error, status}}

      {:error, http_err} ->
        Logger.error("[ZKill] HTTP request error when fetching recent kills: #{inspect(http_err)}")
        {:error, {:request_error, http_err}}
    end
  end

  @doc """
  Retrieves kills for a specific system from zKillboard.

  ## Parameters

  - `system_id`: The ID of the system to get kills for
  - `limit`: The maximum number of kills to retrieve (default: 5)

  ## Returns

  - `{:ok, kills}`: A list of kills for the system
  - `{:error, reason}`: If an error occurred
  """
  def get_system_kills(system_id, limit \\ 5) do
    # According to zKillboard API docs, the correct format is:
    # https://zkillboard.com/api/systemID/ID/
    url = "https://zkillboard.com/api/systemID/#{system_id}/"

    headers = [
      {"User-Agent", @user_agent}
    ]

    # Centralized building of cURL command (in Http.Client now):
    curl_example = HttpClient.build_curl_command("GET", url, headers)
    Logger.info("[ZKill] Requesting system kills from: #{url}")

    case HttpClient.request("GET", url, headers) do
      {:ok, %{status_code: 200, body: body}} ->
        # Log the raw response to understand its structure

        case Jason.decode(body) do
          {:ok, parsed} when is_list(parsed) and length(parsed) > 0 ->

            # Take only the requested number of kills
            result = Enum.take(parsed, limit)
            Logger.info("[ZKill] Successfully parsed #{length(result)} kills for system #{system_id}")
            {:ok, result}

          {:ok, []} ->
            Logger.info("[ZKill] No kills found for system #{system_id}")
            {:ok, []}

          {:ok, other} ->
            Logger.warning("""
            [ZKill] Warning: unexpected response format from zKill for system #{system_id} kills.
            Response type: #{inspect(other |> Map.keys())}
            Sample cURL to reproduce:
            #{curl_example}
            """)
            {:error, :unexpected_response_format}

          {:error, decode_err} ->
            Logger.error("""
            [ZKill] JSON decode error for system #{system_id} kills: #{inspect(decode_err)}
            Raw response preview: #{String.slice(body, 0, 200)}
            Sample cURL to reproduce:
            #{curl_example}
            """)
            {:error, :json_error}
        end

      {:ok, %{status_code: status, body: body}} ->
        Logger.error("""
        [ZKill] HTTP error #{status} when fetching kills for system #{system_id}
        Response body: #{inspect(body)}
        Sample cURL to reproduce:
        #{curl_example}
        """)
        {:error, {:http_error, status}}

      {:error, http_err} ->
        Logger.error("""
        [ZKill] HTTP request error when fetching kills for system #{system_id}: #{inspect(http_err)}
        Sample cURL to reproduce:
        #{curl_example}
        """)
        {:error, {:request_error, http_err}}
    end
  end
end
