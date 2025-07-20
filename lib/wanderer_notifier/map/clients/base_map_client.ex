defmodule WandererNotifier.Map.Clients.BaseMapClient do
  @moduledoc """
  Base client module that provides common functionality for map-related clients.
  These clients handle fetching and caching data from the map API.
  """

  alias WandererNotifier.Shared.Config
  alias WandererNotifier.Shared.Logger.Logger, as: AppLogger
  alias WandererNotifier.Infrastructure.Cache
  require Logger
  alias MapSet

  @callback endpoint() :: String.t()
  @callback extract_data(map()) :: {:ok, list()} | {:error, term()}
  @callback validate_data(list()) :: :ok | {:error, term()}
  @callback process_data(list(), list(), Keyword.t()) :: {:ok, list()} | {:error, term()}
  @callback cache_key() :: String.t()
  @callback cache_ttl() :: integer()
  @callback should_notify?(term(), term()) :: boolean()
  @callback send_notification(term()) :: :ok | {:error, term()}
  @callback enrich_item(term()) :: term()
  @callback requires_slug?() :: boolean()

  # Extract shared functions out of the macro
  def fetch_and_decode(url, headers) do
    log_request_start(url, headers)

    # Use unified HTTP client with :map service configuration
    # Internal service - extended timeout, no rate limiting
    url
    |> WandererNotifier.Infrastructure.Http.get(headers, service: :map)
    |> handle_http_response(url)
  end

  defp log_request_start(url, headers) do
    AppLogger.api_info("Making HTTP request",
      url: url,
      headers: Enum.map(headers, fn {k, _v} -> {k, "[REDACTED]"} end)
    )
  end

  defp handle_http_response(response, url) do
    case response do
      {:ok, %{status_code: 200, body: body}} ->
        handle_success_response(body, url)

      {:ok, %{status_code: status, body: body}} ->
        handle_error_status(status, body, url)

      {:error, reason} ->
        handle_http_error(reason, url)
    end
  end

  defp handle_success_response(body, url) do
    body_size =
      case body do
        body when is_binary(body) -> byte_size(body)
        body when is_map(body) -> "parsed_json"
        _ -> "unknown"
      end

    AppLogger.api_info("HTTP request successful",
      url: url,
      status: 200,
      body_size: body_size
    )

    decode_body(body)
  end

  defp handle_error_status(status, body, url) do
    AppLogger.api_error("HTTP request failed with non-200 status",
      url: url,
      status: status,
      body: String.slice(body, 0, 500)
    )

    {:error, {:api_error, status}}
  end

  defp handle_http_error(reason, url) do
    AppLogger.api_error("HTTP request failed with error",
      url: url,
      error: inspect(reason)
    )

    {:error, reason}
  end

  defp decode_body(body) when is_binary(body) do
    case Jason.decode(body) do
      {:ok, decoded} -> {:ok, decoded}
      {:error, _} -> {:error, :json_decode_error}
    end
  end

  defp decode_body(body) when is_map(body) do
    # Body is already parsed JSON (e.g., by Req)
    {:ok, body}
  end

  defp decode_body(_), do: {:error, :invalid_body}

  def cache_get(cache_key) do
    case Cache.get(cache_key) do
      {:ok, data} ->
        handle_cache_data(data, cache_key)

      {:error, :not_found} ->
        AppLogger.api_info("Cache miss, fetching from API", key: cache_key)
        {:error, :cache_miss}
    end
  end

  defp handle_cache_data({:ok, data}, cache_key) when is_list(data) and length(data) > 0 do
    log_cache_hit(data, cache_key)
    {:ok, data}
  end

  defp handle_cache_data(data, cache_key) when is_list(data) and length(data) > 0 do
    log_cache_hit(data, cache_key)
    {:ok, data}
  end

  defp handle_cache_data(_, cache_key) do
    AppLogger.api_info("Cache miss, fetching from API", key: cache_key)
    {:error, :cache_miss}
  end

  defp log_cache_hit(data, cache_key) do
    AppLogger.api_debug("Retrieved data from cache",
      count: length(data),
      key: cache_key
    )
  end

  def cache_put(cache_key, data, ttl) do
    AppLogger.api_debug("Caching fetched data",
      count: length(data),
      key: cache_key,
      ttl: ttl
    )

    Cache.put_with_ttl(cache_key, data, ttl)
    {:ok, data}
  end

  # TTL conversion and cache operations are now handled by the Cache facade

  def build_url(endpoint) do
    base_url = Config.base_map_url()
    base_url = String.trim_trailing(base_url, "/")
    map_slug = Config.map_slug()
    "#{base_url}/api/maps/#{map_slug}/#{endpoint}"
  end

  def auth_headers do
    token = Config.map_token()
    [{"Authorization", "Bearer #{token}"}]
  end

  def fetch_and_decode_with_auth(url) do
    log_request_start(url, [])

    # Use unified HTTP client with :map service configuration and authentication
    token = Config.map_token()

    url
    |> WandererNotifier.Infrastructure.Http.get([],
      service: :map,
      auth: [type: :bearer, token: token]
    )
    |> handle_http_response(url)
  end

  def find_new_items(cached_items, new_items) do
    cached_ids =
      cached_items
      |> Enum.map(&get_item_id/1)
      |> MapSet.new()

    Enum.reject(new_items, fn item ->
      get_item_id(item) in cached_ids
    end)
  end

  def get_item_id(%{"id" => id}), do: id
  def get_item_id(%{"eve_id" => id}), do: id
  def get_item_id(%{id: id}), do: id
  def get_item_id(%{eve_id: id}), do: id
  def get_item_id(_), do: nil

  defmacro __using__(_opts) do
    quote do
      @behaviour WandererNotifier.Map.Clients.BaseMapClient

      # Default implementations of required functions
      def api_url do
        WandererNotifier.Map.Clients.BaseMapClient.build_url(endpoint())
        |> add_query_params()
      end

      def headers do
        WandererNotifier.Map.Clients.BaseMapClient.auth_headers()
      end

      def fetch_with_auth(url) do
        WandererNotifier.Map.Clients.BaseMapClient.fetch_and_decode_with_auth(url)
      end

      def requires_slug?, do: false

      defoverridable api_url: 0, headers: 0, requires_slug?: 0

      def get_all do
        case WandererNotifier.Map.Clients.BaseMapClient.cache_get(cache_key()) do
          {:ok, data} -> {:ok, data}
          # Return empty list if cache is empty
          {:error, :cache_miss} -> {:ok, []}
        end
      end

      def get_by_id(id) do
        {:ok, items} = get_all()

        case Enum.find(items, &(&1["id"] == id)) do
          nil -> {:error, :not_found}
          item -> {:ok, item}
        end
      end

      def get_by_name(name) do
        {:ok, items} = get_all()

        case Enum.find(items, &(&1["name"] == name)) do
          nil -> {:error, :not_found}
          item -> {:ok, item}
        end
      end

      # Polling has been removed in favor of SSE
      # update_data is no longer needed

      defp fetch_and_process(url, headers, cached, opts) do
        with {:ok, decoded} <-
               WandererNotifier.Map.Clients.BaseMapClient.fetch_and_decode(url, headers),
             {:ok, items} <- extract_data(decoded) do
          validate_and_process(items, cached, opts, url)
        else
          {:error, :json_decode_error} = error ->
            AppLogger.api_error("Failed to decode response", url: url)
            error

          {:error, :invalid_data} = error ->
            AppLogger.api_error("Invalid data format", url: url)
            error

          {:error, reason} = error ->
            AppLogger.api_error("Request failed", url: url, error: inspect(reason))
            error
        end
      end

      defp validate_and_process(items, cached, opts, url) do
        case validate_data(items) do
          :ok ->
            process_with_notifications(items, cached, opts)

          {:error, :invalid_data} ->
            AppLogger.api_error("Data validation failed",
              url: url,
              item_count: length(items)
            )

            {:error, :invalid_data}
        end
      end

      defp module_name do
        __MODULE__ |> Module.split() |> List.last()
      end

      defp process_with_notifications(new_items, [], _opts) do
        WandererNotifier.Map.Clients.BaseMapClient.cache_put(cache_key(), new_items, cache_ttl())
      end

      defp process_with_notifications(new_items, cached_items, opts) do
        # Find new items that aren't in the cache
        truly_new_items =
          WandererNotifier.Map.Clients.BaseMapClient.find_new_items(cached_items, new_items)

        # Process notifications if not suppressed
        if !Keyword.get(opts, :suppress_notifications, false) do
          process_notifications(truly_new_items)
        end

        # Cache the new data (all items, not just the new ones)
        WandererNotifier.Map.Clients.BaseMapClient.cache_put(cache_key(), new_items, cache_ttl())
      end

      defp process_notifications(items) do
        Enum.each(items, fn item ->
          item
          |> enrich_item()
          |> maybe_send_notification()
        end)
      end

      defp maybe_send_notification(item) do
        if should_notify?(WandererNotifier.Map.Clients.BaseMapClient.get_item_id(item), item) do
          send_notification(item)
        end
      rescue
        e ->
          AppLogger.api_error("Notification failed",
            error: Exception.message(e),
            item: inspect(item)
          )

          :error
      end

      defp fetch_and_cache do
        case fetch_from_api() do
          {:ok, items} ->
            WandererNotifier.Map.Clients.BaseMapClient.cache_put(cache_key(), items, cache_ttl())

          error ->
            AppLogger.api_error("Failed to fetch and cache data",
              error: inspect(error)
            )

            error
        end
      end

      defp fetch_from_api do
        url = api_url()
        headers = headers()

        with {:ok, decoded} <-
               WandererNotifier.Map.Clients.BaseMapClient.fetch_and_decode(url, headers),
             {:ok, items} <- extract_data(decoded) do
          {:ok, items}
        else
          {:error, {:api_error, status}} ->
            AppLogger.error("API request failed", %{
              status: status,
              url: url
            })

            {:error, :api_request_failed}

          {:error, reason} ->
            AppLogger.error("API request error", %{
              reason: reason,
              url: url
            })

            {:error, reason}
        end
      end

      defp add_query_params(url) do
        if requires_slug?() do
          case Config.map_slug() do
            nil -> url
            slug when is_binary(slug) -> url <> "?slug=" <> slug
            _ -> url
          end
        else
          url
        end
      end

      defp fallback([_ | _] = cached, reason) do
        AppLogger.api_info("Using cached data as fallback",
          count: length(cached),
          reason: inspect(reason)
        )

        {:ok, cached}
      end

      defp fallback([], reason) do
        AppLogger.api_error("Fallback with empty cache",
          reason: inspect(reason)
        )

        {:error, reason}
      end

      defp fallback(nil, reason) when reason != nil do
        AppLogger.api_error("Fallback with nil cache",
          reason: inspect(reason)
        )

        {:error, reason}
      end

      defp fallback(other, reason) do
        AppLogger.api_error("Fallback with invalid cache type",
          cache_type: inspect(other),
          reason: inspect(reason)
        )

        {:error, reason}
      end
    end
  end
end
