defmodule WandererNotifier.Map.SSEConnection do
  require Logger

  @moduledoc """
  Handles SSE connection management and HTTP operations.

  This module is responsible for establishing and managing SSE connections,
  building URLs, handling HTTP requests, and managing connection lifecycle.
  """

  alias WandererNotifier.Shared.Config

  @doc """
  Establishes an SSE connection with the given configuration.

  ## Parameters
  - `map_slug` - The map slug for the connection
  - `api_token` - Authentication token
  - `events_filter` - List of event types to filter (optional)
  - `last_event_id` - Last event ID for backfill (optional)

  ## Returns
  - `{:ok, connection}` - Connection established successfully
  - `{:error, reason}` - Connection failed
  """
  @spec connect(String.t(), String.t(), list(String.t()) | nil, String.t() | nil) ::
          {:ok, reference()} | {:error, term()}
  def connect(map_slug, api_token, events_filter \\ nil, last_event_id \\ nil) do
    url = build_url(map_slug, events_filter, last_event_id)
    headers = build_headers(api_token)

    case start_connection(url, headers) do
      {:ok, connection} ->
        {:ok, connection}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Closes an SSE connection.

  ## Parameters
  - `connection` - The connection reference to close
  """
  @spec close(reference() | term()) :: :ok
  def close(nil), do: :ok

  def close(connection) when is_reference(connection) do
    # Handle HTTPoison async response - stream_next is safe to call
    async_response = %HTTPoison.AsyncResponse{id: connection}

    try do
      HTTPoison.stream_next(async_response)
    rescue
      _error -> :ok
    end

    :ok
  end

  def close(_connection), do: :ok

  # Private functions

  defp build_url(map_slug, events_filter, last_event_id) do
    # Use the map URL from configuration
    raw_base_url = Config.get(:map_url)

    # Ensure we have a map URL
    if is_nil(raw_base_url) do
      raise "MAP_URL is required for SSE connections"
    end

    # Normalize the base URL by removing path and query components
    base_url = normalize_base_url(raw_base_url)

    # Build query params with events filter
    query_params = []

    # Add events filter if available (nil means no filtering)
    Logger.info("Building SSE URL with events filter: #{inspect(events_filter)}",
      map_slug: map_slug
    )

    query_params =
      case events_filter do
        [_ | _] ->
          events_string = Enum.join(events_filter, ",")

          Logger.debug("Building events query parameter",
            events_filter: inspect(events_filter),
            events_string: events_string,
            events_string_length: String.length(events_string)
          )

          [{"events", events_string} | query_params]

        _ ->
          query_params
      end

    # Add last_event_id for backfill if available
    query_params =
      if last_event_id do
        [{"last_event_id", last_event_id} | query_params]
      else
        query_params
      end

    # Build the URL - try using map_slug instead of map_id
    final_url =
      case query_params do
        [] ->
          # No query parameters at all - use map slug
          "#{base_url}/api/maps/#{map_slug}/events/stream"

        _ ->
          query_string = URI.encode_query(query_params)
          "#{base_url}/api/maps/#{map_slug}/events/stream?#{query_string}"
      end

    final_url
  end

  defp build_headers(api_token) do
    [
      {"Authorization", "Bearer #{api_token}"},
      {"Accept", "text/event-stream"},
      {"Cache-Control", "no-cache"},
      {"Connection", "keep-alive"}
    ]
  end

  defp start_connection(url, headers) do
    # Start real SSE connection using HTTPoison streaming
    options = [
      stream_to: self(),
      async: :once,
      recv_timeout: 60_000,
      timeout: 30_000,
      follow_redirect: true
    ]

    Logger.debug("Starting SSE connection", url: url)

    case HTTPoison.get(url, headers, options) do
      {:ok, %HTTPoison.AsyncResponse{id: async_id}} ->
        Logger.debug("SSE connection established", async_id: async_id)
        {:ok, async_id}

      {:error, %HTTPoison.Error{reason: reason}} ->
        Logger.error("SSE connection failed", reason: reason)
        {:error, {:connection_failed, reason}}
    end
  end

  # Normalizes a base URL by removing path and query components.
  #
  # Takes a URL string and returns a normalized URL with only the scheme, host, and port.
  # This ensures that the URL is in a consistent format for building API endpoints.
  #
  # Examples:
  #   normalize_base_url("https://example.com/some/path?param=value")
  #   #=> "https://example.com"
  #
  #   normalize_base_url("http://localhost:3000/maps/test")
  #   #=> "http://localhost:3000"
  @spec normalize_base_url(String.t()) :: String.t()
  defp normalize_base_url(url) do
    url
    |> URI.parse()
    |> Map.put(:path, nil)
    |> Map.put(:query, nil)
    |> URI.to_string()
  end
end
