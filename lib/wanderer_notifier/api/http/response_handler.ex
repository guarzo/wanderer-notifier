defmodule WandererNotifier.Api.Http.ResponseHandler do
  @moduledoc """
  Handles HTTP responses, providing consistent error handling and response processing.
  """
  require Logger

  @spec handle_response({:ok, any()} | {:error, any()}, String.t()) ::
          {:ok, map()} | {:error, any()}
  def handle_response({:ok, %{status_code: 200, body: body}}, curl_example) do
    case Jason.decode(body) do
      {:ok, data} ->
        {:ok, data}

      {:error, err} ->
        Logger.error("JSON decode error: #{inspect(err)}. cURL: #{curl_example}")
        {:error, err}
    end
  end

  def handle_response({:ok, %{status_code: status, body: body}}, curl_example) do
    Logger.error("Unexpected status #{status}: #{body}. cURL: #{curl_example}")
    {:error, {:unexpected_status, status}}
  end

  def handle_response({:error, reason}, curl_example) do
    Logger.error("HTTP error: #{inspect(reason)}. cURL: #{curl_example}")
    {:error, reason}
  end
end
