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

    # Log the URL with intelligent truncation
    AppLogger.api_info("Connecting to SSE",
      map_slug: map_slug,
      url: truncate_url_intelligently(url, 500),
      full_url_length: String.length(url),
      events_count: if(is_list(events_filter), do: length(events_filter), else: 0)
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
  def close(connection) do
    # Handle HTTPoison async response - stream_next is safe to call
    async_response = %HTTPoison.AsyncResponse{id: connection}
    HTTPoison.stream_next(async_response)
    :ok
  end

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
    AppLogger.api_info("Building SSE URL with events filter",
      map_slug: map_slug,
      events_filter: inspect(events_filter)
    )

    query_params =
      case events_filter do
        [_ | _] ->
          events_string = Enum.join(events_filter, ",")

          AppLogger.api_debug("Building events query parameter",
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

    AppLogger.api_info("Final SSE URL",
      map_slug: map_slug,
      url: final_url,
      url_length: String.length(final_url),
      query_params: inspect(query_params),
      events_filter_input: inspect(events_filter),
      events_count: if(is_list(events_filter), do: length(events_filter), else: 0)
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

  # Helper function to intelligently truncate URLs at query parameter boundaries
  defp truncate_url_intelligently(url, max_length) do
    if String.length(url) <= max_length do
      url
    else
      truncate_long_url(url, max_length)
    end
  end

  defp truncate_long_url(url, max_length) do
    case String.split(url, "?", parts: 2) do
      [_base_url] ->
        # No query parameters, just truncate normally
        String.slice(url, 0, max_length) <> "..."

      [base_url, query_string] ->
        truncate_url_with_query(base_url, query_string, max_length)
    end
  end

  defp truncate_url_with_query(base_url, query_string, max_length) do
    if String.length(base_url) >= max_length do
      String.slice(base_url, 0, max_length) <> "..."
    else
      truncate_query_params(base_url, query_string, max_length)
    end
  end

  defp truncate_query_params(base_url, query_string, max_length) do
    # -1 for the "?"
    remaining_length = max_length - String.length(base_url) - 1
    query_params = String.split(query_string, "&")

    truncated_params = collect_params_within_limit(query_params, remaining_length)

    build_truncated_url(base_url, truncated_params, query_params)
  end

  defp collect_params_within_limit(query_params, remaining_length) do
    {params, _} =
      Enum.reduce_while(query_params, {[], 0}, fn param, {acc, current_length} ->
        param_length = calculate_param_length(param, acc)
        new_length = current_length + param_length

        if new_length <= remaining_length do
          {:cont, {[param | acc], new_length}}
        else
          {:halt, {acc, current_length}}
        end
      end)

    # Reverse since we built the list in reverse order
    Enum.reverse(params)
  end

  defp calculate_param_length(param, acc) do
    # "&" separator
    separator_length = if acc == [], do: 0, else: 1
    String.length(param) + separator_length
  end

  defp build_truncated_url(base_url, [], _all_params) do
    base_url <> "?..."
  end

  defp build_truncated_url(base_url, truncated_params, all_params) do
    truncated_query = Enum.join(truncated_params, "&")
    ellipsis = if length(truncated_params) < length(all_params), do: "&...", else: ""

    base_url <> "?" <> truncated_query <> ellipsis
  end
end
