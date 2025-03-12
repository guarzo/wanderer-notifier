defmodule WandererNotifier.Http.Client do
  @moduledoc """
  Generic HTTP client wrapper.
  """
  require Logger

  # Default retry configuration
  @default_max_retries 3
  @default_initial_backoff 500  # milliseconds
  @default_max_backoff 5000     # milliseconds
  @default_timeout 10000        # milliseconds (10 seconds)

  # Errors that are considered transient and can be retried
  @transient_errors [:timeout, :connect_timeout, :econnrefused, :closed, :enetunreach, :system_limit]

  def get(url) do
    # For GET requests, pass an empty string as body
    request("GET", url, [], "")
  end

  def request(method, url, headers \\ [], body \\ nil, opts \\ []) do
    body = body || ""
    max_retries = Keyword.get(opts, :max_retries, @default_max_retries)
    initial_backoff = Keyword.get(opts, :initial_backoff, @default_initial_backoff)
    
    do_request_with_retry(method, url, headers, body, max_retries, initial_backoff, 0)
  end

  defp do_request_with_retry(method, url, headers, body, max_retries, backoff, retry_count) do
    options = [
      hackney: [
        follow_redirect: true,
        recv_timeout: @default_timeout,
        connect_timeout: @default_timeout
      ]
    ]

    result = HTTPoison.request(method, url, body, headers, options)

    case result do
      {:ok, response} ->
        Logger.debug("HTTP #{method} => #{url} (status=#{response.status_code})")
        {:ok, response}

      {:error, %HTTPoison.Error{reason: reason}} = error ->
        if retry_count < max_retries && transient_error?(reason) do
          # Calculate exponential backoff with jitter
          current_backoff = min(backoff * :math.pow(2, retry_count), @default_max_backoff)
          jitter = :rand.uniform(trunc(current_backoff * 0.2))
          actual_backoff = trunc(current_backoff + jitter)
          
          Logger.warning("HTTP #{method} => #{url} FAILED: #{inspect(reason)}. Retrying in #{actual_backoff}ms (attempt #{retry_count + 1}/#{max_retries})")
          
          :timer.sleep(actual_backoff)
          do_request_with_retry(method, url, headers, body, max_retries, backoff, retry_count + 1)
        else
          if retry_count > 0 do
            Logger.error("HTTP #{method} => #{url} FAILED after #{retry_count + 1} attempts: #{inspect(reason)}")
          else
            Logger.error("HTTP #{method} => #{url} FAILED: #{inspect(reason)}")
          end
          error
        end
    end
  end

  # Check if an error is transient and can be retried
  defp transient_error?(reason) when reason in @transient_errors, do: true
  defp transient_error?({:closed, _}), do: true
  defp transient_error?({:timeout, _}), do: true
  defp transient_error?(_), do: false

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
