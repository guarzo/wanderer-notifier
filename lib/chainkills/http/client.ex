defmodule ChainKills.Http.Client do
  @moduledoc """
  HTTP client using HTTPoison.
  """
  require Logger

  def get(url) do
    # Pass an empty string instead of nil for GET requests.
    request("GET", url, [], "")
  end

  def request(method, url, headers \\ [], body \\ nil) do
    # Ensure the body is a binary; default to an empty string if nil.
    body = body || ""

    # Logger.debug("""
    # HTTP Request:
    #   method = #{inspect(method)}
    #   url    = #{inspect(url)}
    #   headers= #{inspect(headers)}
    #   body   = #{inspect(body)}
    # """)

    options = [
      hackney: [
        follow_redirect: true
        # trace: :max   # uncomment for detailed chunk-level logs
      ]
    ]

    case HTTPoison.request(method, url, body, headers, options) do
      {:ok, response} ->
        Logger.debug("HTTP Response OK: status=#{response.status_code}, body-size=#{byte_size(response.body)}")
        {:ok, response}

      {:error, reason} ->
        Logger.error("HTTP Request FAILED: #{inspect(reason)}")
        {:error, reason}
    end
  end
end
