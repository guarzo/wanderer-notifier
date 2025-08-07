defmodule WandererNotifier.Infrastructure.Http.Utils.HttpUtils do
  @moduledoc """
  Shared HTTP utility functions used across middleware components and HTTP clients.

  Provides common utilities for URL manipulation, query parameter handling,
  and other HTTP-related operations.
  """

  @doc """
  Extracts the host from a URL.

  Returns the hostname from a URL string, or "unknown" if the URL is invalid
  or doesn't contain a host.

  ## Examples

      iex> HttpUtils.extract_host("https://api.example.com/path")
      "api.example.com"

      iex> HttpUtils.extract_host("invalid-url")
      "unknown"
  """
  @spec extract_host(String.t()) :: String.t()
  def extract_host(url) do
    case URI.parse(url) do
      %URI{host: host} when is_binary(host) -> host
      _ -> "unknown"
    end
  end

  @doc """
  Builds a URL with query parameters.

  Takes a base URL and a map of query parameters, returning a complete URL
  with properly encoded query string.

  ## Examples

      iex> HttpUtils.build_url_with_query("https://api.example.com/search", %{"q" => "test", "limit" => 10})
      "https://api.example.com/search?q=test&limit=10"

      iex> HttpUtils.build_url_with_query("https://api.example.com/search", %{})
      "https://api.example.com/search"
  """
  @spec build_url_with_query(String.t(), map()) :: String.t()
  def build_url_with_query(base_url, params) when is_map(params) do
    if map_size(params) == 0 do
      base_url
    else
      query_string = URI.encode_query(params)
      separator = if String.contains?(base_url, "?"), do: "&", else: "?"
      "#{base_url}#{separator}#{query_string}"
    end
  end

  @doc """
  Joins URL path segments properly.

  Handles leading/trailing slashes to create a clean URL path.

  ## Examples

      iex> HttpUtils.join_url_path("https://api.example.com", "/users", "123")
      "https://api.example.com/users/123"

      iex> HttpUtils.join_url_path("https://api.example.com/", "users/", "/123/")
      "https://api.example.com/users/123"
  """
  @spec join_url_path(String.t(), String.t(), String.t()) :: String.t()
  def join_url_path(base, path1, path2) do
    base
    |> normalize_url_segment()
    |> Kernel.<>("/" <> normalize_path_segment(path1))
    |> Kernel.<>("/" <> normalize_path_segment(path2))
  end

  @doc """
  Joins multiple URL path segments properly.

  ## Examples

      iex> HttpUtils.join_url_paths("https://api.example.com", ["users", "123", "posts"])
      "https://api.example.com/users/123/posts"
  """
  @spec join_url_paths(String.t(), [String.t()]) :: String.t()
  def join_url_paths(base, segments) when is_list(segments) do
    normalized_base = normalize_url_segment(base)
    normalized_segments = Enum.map(segments, &normalize_path_segment/1)
    Enum.join([normalized_base | normalized_segments], "/")
  end

  @doc """
  Extracts query parameters from a URL.

  ## Examples

      iex> HttpUtils.extract_query_params("https://api.example.com/search?q=test&limit=10")
      %{"q" => "test", "limit" => "10"}

      iex> HttpUtils.extract_query_params("https://api.example.com/search")
      %{}
  """
  @spec extract_query_params(String.t()) :: map()
  def extract_query_params(url) do
    case URI.parse(url) do
      %URI{query: query} when is_binary(query) ->
        URI.decode_query(query)

      _ ->
        %{}
    end
  end

  @doc """
  Validates if a string is a valid URL.

  ## Examples

      iex> HttpUtils.valid_url?("https://api.example.com")
      true

      iex> HttpUtils.valid_url?("not-a-url")
      false
  """
  @spec valid_url?(String.t()) :: boolean()
  def valid_url?(url) when is_binary(url) do
    case URI.parse(url) do
      %URI{scheme: scheme, host: host} when is_binary(scheme) and is_binary(host) ->
        scheme in ["http", "https"]

      _ ->
        false
    end
  end

  @doc """
  Builds standard HTTP headers with optional authentication.

  ## Examples

      iex> HttpUtils.build_headers(%{"X-API-Key" => "secret"})
      [{"Content-Type", "application/json"}, {"X-API-Key", "secret"}]

      iex> HttpUtils.build_headers(%{"X-API-Key" => "secret"}, "Bearer token123")
      [{"Content-Type", "application/json"}, {"Authorization", "Bearer token123"}, {"X-API-Key", "secret"}]
  """
  @spec build_headers(map(), String.t() | nil) :: [tuple()]
  def build_headers(additional_headers \\ %{}, auth_header \\ nil) do
    # Check if additional_headers already contains a Content-Type header
    has_content_type =
      additional_headers
      |> Enum.any?(fn {key, _value} ->
        key
        |> to_string()
        |> String.downcase() == "content-type"
      end)

    base_headers = if has_content_type, do: [], else: [{"Content-Type", "application/json"}]

    headers_with_auth =
      case auth_header do
        nil -> base_headers
        auth -> [{"Authorization", auth} | base_headers]
      end

    additional_headers
    |> Enum.reduce(headers_with_auth, fn {key, value}, acc ->
      [{key, value} | acc]
    end)
    |> Enum.reverse()
  end

  # Private helper functions

  defp normalize_url_segment(segment) do
    String.trim_trailing(segment, "/")
  end

  defp normalize_path_segment(segment) do
    segment
    |> String.trim_leading("/")
    |> String.trim_trailing("/")
  end
end
