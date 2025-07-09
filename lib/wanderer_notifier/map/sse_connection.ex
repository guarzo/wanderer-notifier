defmodule WandererNotifier.Map.SSEConnection do
  @moduledoc """
  Handles SSE connection management and HTTP operations.

  This module is responsible for establishing and managing SSE connections,
  building URLs, handling HTTP requests, and managing connection lifecycle.
  """

  alias WandererNotifier.Config
  alias WandererNotifier.Logger.Logger, as: AppLogger

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

    # Log the full URL without truncation
    AppLogger.api_info("Connecting to SSE",
      map_slug: map_slug,
      # Show more of the URL
      url: String.slice(url, 0..500)
    )

    case start_connection(url, headers) do
      {:ok, connection} ->
        {:ok, connection}

      error ->
        {:error, error}
    end
  end

  @doc """
  Closes an SSE connection.

  ## Parameters
  - `connection` - The connection reference to close
  """
  @spec close(reference() | term()) :: :ok
  def close(connection) when is_reference(connection) do
    # Handle HTTPoison async response
    try do
      async_response = %HTTPoison.AsyncResponse{id: connection}
      HTTPoison.stream_next(async_response)
    rescue
      _ -> :ok
    end
  end

  def close(_), do: :ok

  # Private functions

  defp build_url(map_slug, events_filter, last_event_id) do
    # Use the map URL from configuration, fallback to wanderer_api_base_url
    base_url = Config.get(:map_url) || Config.get(:wanderer_api_base_url, "https://wanderer.ltd")

    # Remove any trailing path from map_url (like /maps/name)
    base_url =
      base_url
      |> URI.parse()
      |> Map.put(:path, nil)
      |> Map.put(:query, nil)
      |> URI.to_string()

    # Build query params with events filter
    query_params = []

    # Add events filter if available (nil means no filtering)
    AppLogger.api_info("Building SSE URL with events filter",
      map_slug: map_slug,
      events_filter: inspect(events_filter)
    )

    query_params =
      if events_filter && length(events_filter) > 0 do
        events_string = Enum.join(events_filter, ",")
        [{"events", events_string} | query_params]
      else
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
      if length(query_params) > 0 do
        query_string = URI.encode_query(query_params)
        "#{base_url}/api/maps/#{map_slug}/events/stream?#{query_string}"
      else
        # No query parameters at all - use map slug
        "#{base_url}/api/maps/#{map_slug}/events/stream"
      end

    AppLogger.api_info("Final SSE URL",
      map_slug: map_slug,
      url: final_url,
      query_params: inspect(query_params)
    )

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

    AppLogger.api_info("Starting SSE connection", url: url)

    case HTTPoison.get(url, headers, options) do
      {:ok, %HTTPoison.AsyncResponse{id: async_id}} ->
        AppLogger.api_info("SSE connection established", async_id: async_id)
        {:ok, async_id}

      {:error, %HTTPoison.Error{reason: reason}} ->
        AppLogger.api_error("SSE connection failed", reason: reason)
        {:error, {:connection_failed, reason}}
    end
  end
end
