defmodule WandererNotifier.HttpClient.ErrorHandler do
  @moduledoc """
  Handles HTTP response errors and provides consistent error handling across the application.
  """

  alias WandererNotifier.Logger.Logger, as: AppLogger

  @doc """
  Handles HTTP responses and provides consistent error handling.

  ## Parameters
    - response: The HTTP response to handle
    - opts: Options for error handling
      - :domain - The domain of the request (e.g., :map, :esi)
      - :tag - A tag for logging purposes

  ## Returns
    - {:ok, parsed_response} on success
    - {:error, reason} on failure
  """
  def handle_http_response(response, opts \\ []) do
    domain = Keyword.get(opts, :domain, :unknown)
    tag = Keyword.get(opts, :tag, "Unknown")

    case response do
      {:ok, %{status_code: status, body: body}} when status in 200..299 ->
        case parse_response_body(body) do
          {:ok, parsed} ->
            {:ok, parsed}

          {:error, reason} ->
            log_parse_error(domain, tag, reason, body)
            {:error, :parse_error}
        end

      {:ok, %{status_code: status, body: body}} ->
        log_http_error(domain, tag, status, body)
        {:error, {:http_error, status}}

      {:error, reason} ->
        log_request_error(domain, tag, reason)
        {:error, reason}
    end
  end

  # Private helper functions

  defp parse_response_body(body) when is_map(body), do: {:ok, body}

  defp parse_response_body(body) when is_binary(body) do
    case Jason.decode(body) do
      {:ok, parsed} -> {:ok, parsed}
      error -> error
    end
  end

  defp parse_response_body(body), do: {:error, {:invalid_body, body}}

  defp log_parse_error(domain, tag, reason, body) do
    AppLogger.api_error("Failed to parse response", %{
      domain: domain,
      tag: tag,
      error: inspect(reason),
      body_sample: String.slice(to_string(body), 0, 200)
    })
  end

  defp log_http_error(domain, tag, status, body) do
    AppLogger.api_error("HTTP error response", %{
      domain: domain,
      tag: tag,
      status: status,
      body_sample: String.slice(to_string(body), 0, 200)
    })
  end

  defp log_request_error(domain, tag, reason) do
    AppLogger.api_error("Request failed", %{
      domain: domain,
      tag: tag,
      error: inspect(reason)
    })
  end
end
