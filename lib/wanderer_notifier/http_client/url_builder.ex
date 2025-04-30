defmodule WandererNotifier.HttpClient.UrlBuilder do
  @moduledoc """
  Handles URL construction and authentication headers for API requests.
  """

  alias WandererNotifier.Config.Config
  alias WandererNotifier.Logger.Logger, as: AppLogger

  @doc """
  Builds a URL for the map API.
  """
  def build_url(path, params \\ %{}) do
    base_url = Config.map_url()
    token = Config.map_token()

    case {base_url, token} do
      {url, _} when not is_binary(url) or url == "" ->
        AppLogger.api_error("Invalid map URL configuration", error: inspect(base_url))
        {:error, :invalid_url}

      {_, token} when not is_binary(token) or token == "" ->
        AppLogger.api_error("Invalid map token configuration", error: inspect(token))
        {:error, :invalid_token}

      {url, _} ->
        full_url = build_full_url(url, path, params)
        {:ok, full_url}
    end
  end

  @doc """
  Gets the authentication headers for API requests.
  """
  def get_auth_headers do
    token = Config.map_token()

    [
      {"Authorization", "Bearer #{token}"},
      {"Content-Type", "application/json"},
      {"Accept", "application/json"}
    ]
  end

  # Private helper to build the full URL with query parameters
  defp build_full_url(base_url, path, params) when map_size(params) == 0 do
    Path.join([base_url, "api", path])
  end

  defp build_full_url(base_url, path, params) do
    base = Path.join([base_url, "api", path])
    query = URI.encode_query(params)
    "#{base}?#{query}"
  end
end
