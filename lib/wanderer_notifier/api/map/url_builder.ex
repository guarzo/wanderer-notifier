defmodule WandererNotifier.Api.Map.UrlBuilder do
  @moduledoc """
  Centralized URL construction for Map API requests.
  Handles extracting slugs and building properly formatted URLs for the Map API.
  """
  require Logger
  alias WandererNotifier.Core.Config

  @doc """
  Builds a URL for the Map API.
  
  ## Parameters
    - endpoint: The API endpoint path (e.g., "map/systems")
    - params: Map of query parameters to include in the URL
    - slug: Optional map slug. If not provided, extracts from config
  
  ## Returns
    - {:ok, url} on success
    - {:error, reason} on failure
  """
  def build_url(endpoint, params \\ %{}, slug \\ nil) do
    with {:ok, base_domain} <- get_base_domain(),
         {:ok, map_slug} <- get_slug(slug) do
      # Ensure endpoint doesn't start with a slash
      endpoint = String.trim_leading(endpoint, "/")
      
      # Add the slug to params
      params = Map.put(params, "slug", map_slug)
      
      # Convert params to query string
      query_string = build_query_string(params)
      
      # Return the full URL
      {:ok, "#{base_domain}/api/#{endpoint}#{query_string}"}
    end
  end

  @doc """
  Gets the authentication headers for Map API requests.
  
  ## Returns
    - List of HTTP headers including authorization if available
  """
  def get_auth_headers do
    token = Config.map_token()
    csrf_token = Config.map_csrf_token()

    # Debug logs for token availability
    if token do
      Logger.debug("[UrlBuilder] Map token is available")
    else
      Logger.warning("[UrlBuilder] Map token is NOT available - bearer token authentication will not be used")
    end

    headers = [
      {"accept", "application/json"},
      {"Content-Type", "application/json"}
    ]

    headers = if token, do: [{"Authorization", "Bearer #{token}"} | headers], else: headers
    headers = if csrf_token, do: [{"x-csrf-token", csrf_token} | headers], else: headers

    headers
  end

  # Private helper functions
  
  defp get_base_domain do
    base_url = Config.map_url()

    if is_nil(base_url) or base_url == "" do
      Logger.error("[UrlBuilder] MAP_URL not configured. Cannot construct API URL.")
      {:error, "MAP_URL is required but not configured"}
    else
      # Extract base domain - should be just the domain without the slug path
      base_domain = base_url |> String.split("/") |> Enum.take(3) |> Enum.join("/")
      {:ok, base_domain}
    end
  end
  
  defp get_slug(nil) do
    # Try to get the slug from config or extract from map_url
    slug = 
      Config.map_name() || 
      extract_slug_from_url(Config.map_url())
    
    if is_nil(slug) do
      Logger.error("[UrlBuilder] No map slug provided or configured")
      {:error, "Map slug is required but not available"}
    else
      {:ok, slug}
    end
  end
  
  defp get_slug(slug) when is_binary(slug) do
    {:ok, slug}
  end
  
  defp extract_slug_from_url(url) when is_binary(url) do
    # Example: "https://wanderer.zoolanders.space/flygd" -> "flygd"
    # Split by "/" and take the last part
    parts = String.split(url, "/")
    List.last(parts)
  end
  
  defp extract_slug_from_url(_), do: nil
  
  defp build_query_string(params) when map_size(params) > 0 do
    "?" <>
      Enum.map_join(params, "&", fn {key, value} ->
        "#{key}=#{URI.encode_www_form(to_string(value))}"
      end)
  end
  
  defp build_query_string(_), do: ""
end