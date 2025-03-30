defmodule WandererNotifier.Api.Map.UrlBuilder do
  @moduledoc """
  Builds URLs for the map API endpoints.
  """
  alias WandererNotifier.Config
  alias WandererNotifier.Logger, as: AppLogger

  @doc """
  Builds a URL for a map API endpoint with query parameters and a custom slug.

  ## Parameters
    - endpoint: The API endpoint to call
    - params: A map of query parameters to include in the URL
    - slug: An optional slug override

  ## Returns
    - {:ok, url} on success
    - {:error, reason} on failure
  """
  def build_url(endpoint, params, slug) when is_map(params) do
    with {:ok, base_url} <- get_base_url(),
         {:ok, final_slug} <- get_final_slug(slug) do
      # Start with the base URL and endpoint
      base = "#{base_url}/api/#{endpoint}"

      # Convert params to query string
      query_params =
        params
        |> Map.to_list()
        |> Enum.map_join("&", fn {k, v} -> "#{k}=#{URI.encode_www_form(to_string(v))}" end)

      # Add slug parameter to query
      slug_param = "slug=#{URI.encode_www_form(final_slug)}"
      query = if query_params == "", do: slug_param, else: "#{query_params}&#{slug_param}"

      # Build the final URL
      url = "#{base}?#{query}"

      AppLogger.api_info("Building URL with params: #{url}",
        base_url: base_url,
        endpoint: endpoint,
        params: inspect(params),
        slug: final_slug
      )

      {:ok, url}
    end
  end

  @doc """
  Builds a URL for a map API endpoint with query parameters.
  Can build URLs with no slug for system-static-info endpoint.

  ## Parameters
    - endpoint: The API endpoint to call
    - params: A map of query parameters to include in the URL

  ## Returns
    - {:ok, url} on success
    - {:error, reason} on failure
  """
  def build_url(endpoint, params) when is_map(params) do
    # For system-static-info endpoint, we don't need a slug
    if endpoint == "common/system-static-info" do
      with {:ok, base_url} <- get_base_url() do
        # Start with the base URL and endpoint
        base = "#{base_url}/api/#{endpoint}"

        # Convert params to query string
        query_params =
          params
          |> Map.to_list()
          |> Enum.map_join("&", fn {k, v} -> "#{k}=#{URI.encode_www_form(to_string(v))}" end)

        # Build the final URL
        url = "#{base}?#{query_params}"

        AppLogger.api_info("Building URL with params (no slug): #{url}",
          base_url: base_url,
          endpoint: endpoint,
          params: inspect(params)
        )

        {:ok, url}
      end
    else
      # For regular endpoints, include the slug
      build_url(endpoint, params, nil)
    end
  end

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

  # Helper to get final slug, using custom slug or falling back to config
  defp get_final_slug(nil), do: get_slug()
  defp get_final_slug(""), do: get_slug()
  defp get_final_slug(slug), do: {:ok, slug}
end
