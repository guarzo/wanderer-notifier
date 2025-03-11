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
end
