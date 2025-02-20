defmodule ChainKills.ZKill.Client do
  @moduledoc """
  A minimal example of fetching single killmails from zKillboard.
  If zKill returns a literal JSON "true", we detect that and log
  a 'sample curl' command for debugging.
  """

  require Logger
  alias ChainKills.Http.Client, as: HttpClient

  @user_agent "my-corp-killbot/1.0 (contact me@example.com)"
  # ^ Adjust or move this to config so that zKill sees you as a real user.

  def get_single_killmail(kill_id) do
    url = "https://zkillboard.com/api/killID/#{kill_id}/"

    headers = [
      # Adjust headers as needed
      {"User-Agent", @user_agent}
      # Some people also add a "From" or "Accept" header, e.g.:
      # {"From", "contact@mydomain.tld"},
      # {"Accept", "application/json"}
    ]

    # Optional: build a “sample cURL” command for logs
    curl_example = build_curl_command(url, headers)

    case HttpClient.request("GET", url, headers) do
      {:ok, %{status_code: 200, body: body}} ->
        case Jason.decode(body) do
          # Here’s the scenario that triggers a MatchError if unhandled:
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
            # Normal scenario: parsed is probably a list or map with kill data.
            # For example, zKill often returns JSON like: `[ { killID: 123, ... } ]`
            {:ok, parsed}

          {:error, decode_err} ->
            Logger.error("""
            [ZKill] JSON decode error for killmail #{kill_id}: #{inspect(decode_err)}
            Sample cURL to reproduce:

            #{curl_example}
            """)

            {:error, :json_error}
        end

      {:ok, %{status_code: status, body: body}} ->
        # If you want, you can log the body too. Usually 404 means kill not found,
        # 429 means rate-limiting, etc.
        Logger.error("""
        [ZKill] Unexpected HTTP status=#{status} from zKill for killmail #{kill_id}.
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
    end
  end

  defp build_curl_command(url, headers) when is_list(headers) do
    # Turn each {headerName, headerValue} into -H "headerName: headerValue"
    header_parts =
      Enum.map(headers, fn {k, v} ->
        ~s(-H "#{k}: #{v}")
      end)

    # Create the final string
    "curl -X GET #{Enum.join(header_parts, " ")} \"#{url}\""
  end
end
