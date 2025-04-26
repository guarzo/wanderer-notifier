defmodule WandererNotifier.HttpClient.HTTPoison do
  @behaviour WandererNotifier.HttpClient

  def request(method, url, headers, body, opts) do
    # Convert body to JSON if needed
    payload = if body, do: Jason.encode!(body), else: ""

    HTTPoison.request(method, url, payload, headers, opts)
    |> case do
      {:ok, %HTTPoison.Response{status_code: s, body: b}} ->
        {:ok, %{status: s, body: Jason.decode!(b)}}

      error ->
        error
    end
  end
end
