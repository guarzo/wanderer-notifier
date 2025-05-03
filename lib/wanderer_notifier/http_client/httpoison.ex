defmodule WandererNotifier.HttpClient.Httpoison do
  @moduledoc """
  HTTPoison implementation of the HTTP client behavior
  """
  @behaviour WandererNotifier.HttpClient.Behaviour

  require Logger

  @default_headers [{"Content-Type", "application/json"}]

  @impl true
  def get(url, headers \\ @default_headers) do
    HTTPoison.get(url, headers)
    |> handle_response()
  end

  @impl true
  def post(url, body, headers \\ @default_headers) do
    HTTPoison.post(url, body, headers)
    |> handle_response()
  end

  @impl true
  def post_json(url, body, headers \\ @default_headers, options \\ []) do
    encoded_body = Jason.encode!(body)

    HTTPoison.post(url, encoded_body, headers, options)
    |> handle_response()
  end

  @doc """
  Makes a generic HTTP request
  """
  @impl true
  def request(method, url, headers \\ [], body \\ nil, opts \\ []) do
    # Convert body to JSON if it's a map and not nil
    payload =
      cond do
        is_nil(body) -> ""
        is_map(body) -> Jason.encode!(body)
        true -> body
      end

    HTTPoison.request(method, url, payload, headers, opts)
    |> handle_response()
  end

  @impl true
  def handle_response(
        {:ok, %HTTPoison.Response{status_code: status, body: body, headers: _headers}}
      )
      when status in 200..299 do
    case Jason.decode(body) do
      {:ok, decoded} ->
        {:ok, %{status_code: status, body: decoded}}

      {:error, _reason} ->
        {:ok, %{status_code: status, body: body}}
    end
  end

  def handle_response(
        {:ok, %HTTPoison.Response{status_code: status, body: body, headers: headers}}
      ) do
    Logger.warning("Non-2xx response",
      status: status,
      headers: inspect(headers),
      body: inspect(body)
    )

    {:error, %{status_code: status, body: body}}
  end

  def handle_response({:error, %HTTPoison.Error{reason: reason}}) do
    Logger.error("HTTP request failed: #{inspect(reason)}")
    {:error, reason}
  end

  def handle_response(other) do
    {:error, {:unexpected_response, other}}
  end
end
