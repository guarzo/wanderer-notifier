defmodule WandererNotifier.Api.Map.UrlBuilder do
  @moduledoc """
  Builds URLs for the map API endpoints.
  """
  alias WandererNotifier.Core.Config
  alias WandererNotifier.Logger, as: AppLogger

  @doc """
  Builds a URL for a map API endpoint.
  """
  def build_url(endpoint) do
    with {:ok, base_url} <- get_base_url(),
         {:ok, slug} <- get_slug() do
      url = "#{base_url}/api/#{endpoint}?slug=#{URI.encode_www_form(slug)}"

      AppLogger.api_info("Building URL: #{url}",
        base_url: base_url,
        endpoint: endpoint,
        slug: slug
      )

      # Log URL components for debugging
      AppLogger.api_debug("URL Components breakdown",
        scheme: URI.parse(url).scheme,
        host: URI.parse(url).host,
        port: URI.parse(url).port,
        path: URI.parse(url).path,
        query: URI.parse(url).query
      )

      {:ok, url}
    end
  end

  @doc """
  Gets the authorization headers for map API requests.
  """
  def get_auth_headers do
    headers =
      case Config.map_token() do
        nil -> []
        token -> [{"Authorization", "Bearer " <> token}]
      end

    AppLogger.api_info("Auth headers configured",
      has_token: Config.map_token() != nil
    )

    headers
  end

  # Get the base URL from the map URL
  defp get_base_url do
    case Config.map_url() do
      nil ->
        {:error, "Map URL not configured"}

      "" ->
        {:error, "Map URL not configured"}

      url ->
        uri = URI.parse(url)
        base = "#{uri.scheme}://#{uri.host}#{if uri.port, do: ":#{uri.port}", else: ""}"
        {:ok, base}
    end
  end

  # Get the slug from the map configuration
  defp get_slug do
    case Config.map_name() do
      nil ->
        {:error, "Map name not configured"}

      "" ->
        {:error, "Map name not configured"}

      slug ->
        {:ok, slug}
    end
  end
end
