defmodule WandererNotifier.Infrastructure.Http.Headers do
  @moduledoc """
  Centralized HTTP header management for consistent header generation across all HTTP clients.

  This module provides common header patterns and builder functions to eliminate
  duplication and ensure consistency in HTTP requests throughout the application.
  """

  alias WandererNotifier.Shared.Types.Constants

  @type headers :: [{String.t(), String.t()}]

  @doc """
  Returns the standard JSON headers for API requests.

  Includes both Content-Type and Accept headers for JSON.

  ## Examples

      iex> WandererNotifier.Infrastructure.Http.Headers.json_headers()
      [
        {"Content-Type", "application/json"},
        {"Accept", "application/json"}
      ]
  """
  @spec json_headers() :: headers()
  def json_headers do
    [
      {"Content-Type", "application/json"},
      {"Accept", "application/json"}
    ]
  end

  @doc """
  Returns headers for JSON API requests that only expect JSON responses.

  Only includes Accept header, not Content-Type (for GET requests).

  ## Examples

      iex> WandererNotifier.Infrastructure.Http.Headers.json_accept_headers()
      [{"Accept", "application/json"}]
  """
  @spec json_accept_headers() :: headers()
  def json_accept_headers do
    [{"Accept", "application/json"}]
  end

  @doc """
  Returns the default User-Agent header.

  Uses the application's configured user agent string.

  ## Examples

      iex> WandererNotifier.Infrastructure.Http.Headers.user_agent_header()
      [{"User-Agent", "WandererNotifier/1.0"}]
  """
  @spec user_agent_header() :: headers()
  def user_agent_header do
    [{"User-Agent", Constants.user_agent()}]
  end

  @doc """
  Returns a Bearer authorization header with the given token.

  ## Parameters

    - token: The bearer token to include

  ## Examples

      iex> WandererNotifier.Infrastructure.Http.Headers.bearer_auth_header("my-token")
      [{"Authorization", "Bearer my-token"}]
  """
  @spec bearer_auth_header(String.t()) :: headers()
  def bearer_auth_header(token) when is_binary(token) do
    [{"Authorization", "Bearer #{token}"}]
  end

  @doc """
  Returns cache control headers to prevent caching.

  ## Examples

      iex> WandererNotifier.Infrastructure.Http.Headers.no_cache_headers()
      [{"Cache-Control", "no-cache"}]
  """
  @spec no_cache_headers() :: headers()
  def no_cache_headers do
    [{"Cache-Control", "no-cache"}]
  end

  @doc """
  Builds headers for external API requests.

  Combines JSON accept headers with user agent identification.

  ## Options

    - `:include_content_type` - Include Content-Type header (default: false)
    - `:no_cache` - Include Cache-Control: no-cache header (default: false)
    - `:user_agent` - Include User-Agent header (default: true)

  ## Examples

      iex> WandererNotifier.Infrastructure.Http.Headers.external_api_headers()
      [
        {"Accept", "application/json"},
        {"User-Agent", "WandererNotifier/1.0"}
      ]
      
      iex> WandererNotifier.Infrastructure.Http.Headers.external_api_headers(include_content_type: true)
      [
        {"Content-Type", "application/json"},
        {"Accept", "application/json"},
        {"User-Agent", "WandererNotifier/1.0"}
      ]
  """
  @spec external_api_headers(keyword()) :: headers()
  def external_api_headers(opts \\ []) do
    headers =
      if Keyword.get(opts, :include_content_type, false) do
        json_headers()
      else
        json_accept_headers()
      end

    headers =
      if Keyword.get(opts, :user_agent, true) do
        headers ++ user_agent_header()
      else
        headers
      end

    if Keyword.get(opts, :no_cache, false) do
      headers ++ no_cache_headers()
    else
      headers
    end
  end

  @doc """
  Builds headers for authenticated API requests.

  Combines standard headers with bearer token authorization.

  ## Parameters

    - token: The bearer token for authorization
    - opts: Additional options (same as external_api_headers/1)

  ## Examples

      iex> WandererNotifier.Infrastructure.Http.Headers.authenticated_api_headers("my-token")
      [
        {"Accept", "application/json"},
        {"User-Agent", "WandererNotifier/1.0"},
        {"Authorization", "Bearer my-token"}
      ]
  """
  @spec authenticated_api_headers(String.t(), keyword()) :: headers()
  def authenticated_api_headers(token, opts \\ []) do
    external_api_headers(opts) ++ bearer_auth_header(token)
  end

  @doc """
  Builds headers for internal API requests (e.g., map API).

  These typically don't need user agent but do need authentication.

  ## Parameters

    - token: The bearer token for authorization
    - opts: Additional options

  ## Examples

      iex> WandererNotifier.Infrastructure.Http.Headers.internal_api_headers("my-token")
      [
        {"Accept", "application/json"},
        {"Authorization", "Bearer my-token"}
      ]
  """
  @spec internal_api_headers(String.t(), keyword()) :: headers()
  def internal_api_headers(token, opts \\ []) do
    opts = Keyword.put(opts, :user_agent, false)
    authenticated_api_headers(token, opts)
  end

  @doc """
  Merges custom headers with base headers.

  Custom headers take precedence over base headers.

  ## Parameters

    - base_headers: The base header list
    - custom_headers: Additional headers to merge

  ## Examples

      iex> base = [{"Accept", "application/json"}]
      iex> custom = [{"X-Custom", "value"}, {"Accept", "text/html"}]
      iex> WandererNotifier.Infrastructure.Http.Headers.merge_headers(base, custom)
      [{"Accept", "text/html"}, {"X-Custom", "value"}]
  """
  @spec merge_headers(headers(), headers()) :: headers()
  def merge_headers(base_headers, custom_headers) do
    # Convert to map for deduplication, custom headers override base
    base_map = Enum.into(base_headers, %{})
    custom_map = Enum.into(custom_headers, %{})

    Map.merge(base_map, custom_map)
    |> Enum.map(fn {k, v} -> {k, v} end)
    |> Enum.sort()
  end

  @doc """
  Returns ESI-specific headers.

  ESI API requires specific headers for proper operation.
  """
  @spec esi_headers() :: headers()
  def esi_headers do
    external_api_headers()
  end

  @doc """
  Returns ZKillboard-specific headers.

  ZKillboard requires no-cache to ensure fresh data.
  """
  @spec zkill_headers() :: headers()
  def zkill_headers do
    external_api_headers(no_cache: true)
  end

  @doc """
  Returns map API headers with authentication.

  ## Parameters

    - token: The map API token (optional, will fetch from config if not provided)
  """
  @spec map_api_headers(String.t() | nil) :: headers()
  def map_api_headers(token \\ nil) do
    token = token || WandererNotifier.Shared.Config.map_token()
    internal_api_headers(token)
  end

  @doc """
  Returns license API headers with authentication.

  ## Parameters

    - api_key: The license API key
  """
  @spec license_api_headers(String.t()) :: headers()
  def license_api_headers(api_key) do
    authenticated_api_headers(api_key, include_content_type: true)
  end
end
