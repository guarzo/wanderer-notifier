defmodule WandererNotifier.Map.Clients.BaseMapClient do
  @moduledoc """
  Base client module that provides common functionality for map-related clients.
  These clients handle fetching and caching data from the map API.
  """

  alias WandererNotifier.Config
  alias WandererNotifier.Logger.Logger, as: AppLogger
  require Logger
  alias WandererNotifier.HTTP
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

  # Extract shared functions out of the macro
  def fetch_and_decode(url, headers) do
    with {:ok, response} <- HTTP.get(url, headers),
         {:ok, body} <- extract_body(response),
         {:ok, decoded} <- decode_body(body) do
      {:ok, decoded}
    else
      {:error, _} = error -> error
    end
  end

  defp extract_body(%{status_code: 200, body: body}), do: {:ok, body}
  defp extract_body(%{status_code: status} = _response), do: {:error, {:api_error, status}}

  defp decode_body(body) when is_map(body), do: {:ok, body}

  defp decode_body(body) when is_binary(body) do
    case Jason.decode(body) do
      {:ok, decoded} -> {:ok, decoded}
      {:error, _} -> {:error, :json_decode_error}
    end
  end

  defp decode_body(_), do: {:error, :invalid_body}

  def cache_get(cache_key) do
    cache_name = Application.get_env(:wanderer_notifier, :cache_name, :wanderer_cache)

    case WandererNotifier.Cache.Adapter.get(cache_name, cache_key) do
      {:ok, data} when is_list(data) and length(data) > 0 ->
        AppLogger.api_info("Retrieved data from cache",
          count: length(data),
          key: cache_key
        )

        {:ok, data}

      _ ->
        AppLogger.api_info("Cache miss, fetching from API", key: cache_key)
        {:error, :cache_miss}
    end
  end

  def cache_put(cache_key, data, ttl) do
    cache_name = Application.get_env(:wanderer_notifier, :cache_name, :wanderer_cache)

    AppLogger.api_info("Caching fetched data",
      count: length(data),
      key: cache_key,
      ttl: ttl
    )

    # Convert ttl to milliseconds for the adapter
    ttl_ms =
      case ttl do
        :infinity -> :infinity
        seconds when is_integer(seconds) and seconds > 0 -> :timer.seconds(seconds)
        _ -> 0
      end

    case WandererNotifier.Cache.Adapter.set(cache_name, cache_key, data, ttl_ms) do
      {:ok, _} ->
        {:ok, data}

      error ->
        AppLogger.api_error("Failed to cache data", error: inspect(error))
        {:error, :cache_error}
    end
  end

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

      defoverridable api_url: 0, headers: 0

      def get_all do
        case WandererNotifier.Map.Clients.BaseMapClient.cache_get(cache_key()) do
          {:ok, data} -> {:ok, data}
          {:error, :cache_miss} -> fetch_and_cache()
        end
      end

      def get_by_id(id) do
        with {:ok, items} <- get_all(),
             item when not is_nil(item) <- Enum.find(items, &(&1["id"] == id)) do
          {:ok, item}
        else
          {:error, reason} -> {:error, reason}
          nil -> {:error, :not_found}
        end
      end

      def get_by_name(name) do
        with {:ok, items} <- get_all(),
             item when not is_nil(item) <- Enum.find(items, &(&1["name"] == name)) do
          {:ok, item}
        else
          {:error, reason} -> {:error, reason}
          nil -> {:error, :not_found}
        end
      end

      def update_data(cached \\ [], opts \\ []) do
        url = api_url()
        headers = headers()

        case fetch_and_process(url, headers, cached, opts) do
          {:ok, _} = ok -> ok
          {:error, reason} -> fallback(cached, reason)
        end
      end

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
        # Only user-characters endpoint needs slug as query parameter
        if String.contains?(endpoint(), "user-characters") do
          url <> "?slug=" <> Config.map_slug()
        else
          url
        end
      end

      defp fallback(cached, reason) when is_list(cached) and cached != [] do
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

      defp fallback(nil, reason) do
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
