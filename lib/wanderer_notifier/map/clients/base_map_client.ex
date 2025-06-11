defmodule WandererNotifier.Map.Clients.BaseMapClient do
  @moduledoc """
  Base client module that provides common functionality for map-related clients.
  These clients handle fetching and caching data from the map API.
  """

  alias WandererNotifier.Config
  alias WandererNotifier.Logger.Logger, as: AppLogger
  require Logger
  alias WandererNotifier.HTTP

  @callback endpoint() :: String.t()
  @callback extract_data(map()) :: {:ok, list()} | {:error, term()}
  @callback validate_data(list()) :: :ok | {:error, term()}
  @callback process_data(list(), list(), Keyword.t()) :: {:ok, list()} | {:error, term()}
  @callback cache_key() :: String.t()
  @callback cache_ttl() :: integer()
  @callback should_notify?(term(), term()) :: boolean()
  @callback send_notification(term()) :: :ok | {:error, term()}
  @callback enrich_item(term()) :: term()

  defmacro __using__(_opts) do
    quote do
      @behaviour WandererNotifier.Map.Clients.BaseMapClient

      # Default implementations of required functions
      def api_url do
        base_url = Config.base_map_url()
        endpoint = endpoint()
        build_url(base_url, endpoint)
      end

      def headers do
        auth_header()
      end

      defoverridable api_url: 0, headers: 0

      def get_all do
        cache_name = Application.get_env(:wanderer_notifier, :cache_name, :wanderer_cache)

        case Cachex.get(cache_name, cache_key()) do
          {:ok, data} when is_list(data) and length(data) > 0 ->
            AppLogger.api_info("Retrieved data from cache",
              count: length(data),
              key: cache_key()
            )

            {:ok, data}

          _ ->
            AppLogger.api_info("Cache miss, fetching from API", key: cache_key())
            fetch_and_cache()
        end
      end

      def get_by_id(id) do
        with {:ok, items} <- get_all(),
             item when not is_nil(item) <- Enum.find(items, &(&1["id"] == id)) do
          {:ok, item}
        else
          _ -> {:error, :not_found}
        end
      end

      def get_by_name(name) do
        with {:ok, items} <- get_all(),
             item when not is_nil(item) <- Enum.find(items, &(&1["name"] == name)) do
          {:ok, item}
        else
          _ -> {:error, :not_found}
        end
      end

      def update_data(cached \\ [], opts \\ []) do
        base_url = Config.base_map_url()
        endpoint = endpoint()
        url = build_url(base_url, endpoint)
        headers = auth_header()

        case fetch_and_process(url, headers, cached, opts) do
          {:ok, _} = ok -> ok
          {:error, reason} -> fallback(cached, reason)
        end
      end

      defp fetch_and_process(url, headers, cached, opts) do
        with {:ok, %{status_code: 200, body: body}} <- HTTP.get(url, headers),
             {:ok, decoded} <- decode_body(body),
             {:ok, items} <- extract_data(decoded) do
          validate_and_process(items, cached, opts, url)
        else
          error -> handle_fetch_error(error, url)
        end
      end

      # Validate data and process if valid
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

      # Handle different types of fetch errors
      defp handle_fetch_error({:ok, %{status_code: status, body: body}}, url) do
        AppLogger.api_error("HTTP error",
          status: status,
          url: url,
          response: String.slice(body, 0, 100)
        )

        {:error, {:http_error, status, body}}
      end

      defp handle_fetch_error({:error, reason}, url) do
        AppLogger.api_error("Request failed",
          url: url,
          error: inspect(reason)
        )

        {:error, {:request_error, reason}}
      end

      defp handle_fetch_error(other, url) do
        AppLogger.api_error("Unexpected result",
          url: url,
          result: inspect(other)
        )

        {:error, {:unexpected_result, other}}
      end

      defp process_with_notifications(new_items, [], _opts) do
        cache_name = Application.get_env(:wanderer_notifier, :cache_name, :wanderer_cache)

        case Cachex.put(cache_name, cache_key(), new_items, ttl: :timer.seconds(cache_ttl())) do
          {:ok, true} ->
            {:ok, new_items}

          error ->
            AppLogger.api_error("Failed to cache data", error: inspect(error))
            {:error, :cache_error}
        end
      end

      defp process_with_notifications(new_items, cached_items, opts) do
        cache_name = Application.get_env(:wanderer_notifier, :cache_name, :wanderer_cache)

        # Find new items that aren't in the cache
        truly_new_items = find_new_items(cached_items, new_items)

        # Process notifications if not suppressed
        if !Keyword.get(opts, :suppress_notifications, false) do
          process_notifications(truly_new_items)
        end

        # Cache the new data (all items, not just the new ones)
        case Cachex.put(cache_name, cache_key(), new_items, ttl: :timer.seconds(cache_ttl())) do
          {:ok, true} ->
            {:ok, new_items}

          error ->
            AppLogger.api_error("Failed to cache data", error: inspect(error))
            {:error, :cache_error}
        end
      end

      defp find_new_items(cached_items, new_items) do
        cached_ids = Enum.map(cached_items, &get_item_id/1) |> MapSet.new()

        Enum.reject(new_items, fn item ->
          get_item_id(item) in cached_ids
        end)
      end

      defp process_notifications(items) do
        Enum.each(items, fn item ->
          item
          |> enrich_item()
          |> maybe_send_notification()
        end)
      end

      defp maybe_send_notification(item) do
        if should_notify?(get_item_id(item), item) do
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

      defp get_item_id(%{"id" => id}), do: id
      defp get_item_id(%{"eve_id" => id}), do: id
      defp get_item_id(%{id: id}), do: id
      defp get_item_id(%{eve_id: id}), do: id
      defp get_item_id(_), do: nil

      defp fetch_and_cache do
        case fetch_from_api() do
          {:ok, items} ->
            cache_name = Application.get_env(:wanderer_notifier, :cache_name, :wanderer_cache)

            AppLogger.api_info("Caching fetched data",
              count: length(items),
              key: cache_key(),
              ttl: cache_ttl()
            )

            case Cachex.put(cache_name, cache_key(), items, ttl: :timer.seconds(cache_ttl())) do
              {:ok, true} ->
                {:ok, items}

              error ->
                AppLogger.api_error("Failed to cache data",
                  error: inspect(error)
                )

                {:error, :cache_error}
            end

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

        case HTTP.get(url, headers) do
          {:ok, %{status_code: 200, body: body}} ->
            {:ok, body}

          {:ok, %{status_code: status}} ->
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

      # Helper functions
      defp build_url(base_url, endpoint) do
        base_url
        |> String.trim_trailing("/")
        |> Kernel.<>("/api/maps/")
        |> Kernel.<>(Config.map_slug())
        |> Kernel.<>("/")
        |> Kernel.<>(endpoint)
      end

      defp add_query_params(url) do
        case endpoint() do
          "map/user_characters" ->
            url <> "?slug=" <> Config.map_slug()

          _ ->
            url
        end
      end

      defp auth_header do
        token = Config.map_token()
        [{"Authorization", "Bearer #{token}"}]
      end

      defp decode_body(body) when is_binary(body) do
        case Jason.decode(body) do
          {:ok, data} ->
            {:ok, data}

          error ->
            AppLogger.api_error("Failed to decode JSON",
              error: inspect(error)
            )

            {:error, :json_decode_failed}
        end
      end

      defp decode_body(map) when is_map(map), do: {:ok, map}
      defp decode_body(other), do: {:error, :invalid_body}

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
