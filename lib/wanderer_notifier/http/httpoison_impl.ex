defmodule WandererNotifier.HTTP.HttpoisonImpl do
  @moduledoc """
  Default implementation of the HTTP behaviour using HTTPoison.
  """

  @behaviour WandererNotifier.HTTP

  @impl true
  def get(url, headers \\ []) do
    HTTPoison.get(url, headers)
  end

  @doc """
  Get request with options for timeout and other settings.
  This is needed by the ZKill client that calls get/3.
  """
  @impl true
  def get(url, headers, options) do
    HTTPoison.get(url, headers, options)
  end

  @impl true
  def post(url, body, headers \\ []) do
    HTTPoison.post(url, body, headers)
  end

  @impl true
  def post_json(url, body, headers \\ [], options \\ []) do
    headers = [{"Content-Type", "application/json"} | headers]
    body = Jason.encode!(body)
    HTTPoison.post(url, body, headers, options)
  end

  @impl true
  def request(method, url, headers \\ [], body \\ "", options \\ []) do
    HTTPoison.request(method, url, body, headers, options)
  end
end
