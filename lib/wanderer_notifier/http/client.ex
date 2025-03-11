defmodule WandererNotifier.Http.Client do
  @moduledoc """
  Generic HTTP client wrapper.
  """
  require Logger

  def get(url) do
    # For GET requests, pass an empty string as body
    request("GET", url, [], "")
  end

  def request(method, url, headers \\ [], body \\ nil) do
    body = body || ""

    options = [
      hackney: [
        follow_redirect: true
        # trace: :max   # uncomment for detailed chunk-level logs
      ]
    ]

    case HTTPoison.request(method, url, body, headers, options) do
      {:ok, response} ->
        Logger.debug("HTTP #{method} => #{url} (status=#{response.status_code})")
        {:ok, response}

      {:error, reason} ->
        Logger.error("HTTP #{method} => #{url} FAILED: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Builds a sample curl command for debugging or logging.
  """
  def build_curl_command(method, url, headers \\ []) do
    header_str =
      Enum.map(headers, fn {k, v} ->
        ~s(-H "#{k}: #{v}")
      end)
      |> Enum.join(" ")

    "curl -X #{method} #{header_str} \"#{url}\""
  end
end
