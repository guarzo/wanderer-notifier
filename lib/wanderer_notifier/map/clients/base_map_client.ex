defmodule WandererNotifier.Map.Clients.BaseMapClient do
  @moduledoc """
  Base client module that provides common functionality for map-related clients.
  These clients handle fetching and caching data from the map API.
  """

  alias WandererNotifier.HttpClient.Httpoison, as: HttpClient
  alias WandererNotifier.Config
  alias WandererNotifier.Logger.Logger, as: AppLogger

  @callback endpoint() :: String.t()
  @callback extract_data(map()) :: {:ok, list()} | {:error, term()}
  @callback validate_data(list()) :: :ok | {:error, term()}
  @callback process_data(list(), list(), Keyword.t()) :: {:ok, list()} | {:error, term()}
  @callback cache_key() :: String.t()
  @callback cache_ttl() :: integer()

  defmacro __using__(_opts) do
    quote do
      @behaviour WandererNotifier.Map.Clients.BaseMapClient

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
        base_url = Config.map_url_with_name()
        map_name = Config.map_slug()
        endpoint = endpoint()
        url = build_url(base_url, map_name, endpoint)
        headers = auth_header()

        AppLogger.api_info("Starting data update",
          url: url,
          cached_count: length(cached),
          opts: inspect(opts)
        )

        case fetch_and_process(url, headers, cached, opts) do
          {:ok, _} = ok -> ok
          {:error, reason} -> fallback(cached, reason)
        end
      end

      defp fetch_and_process(url, headers, cached, opts) do
        AppLogger.api_info("Fetching data from API", url: url)

        with {:ok, %{status_code: 200, body: body}} <- HttpClient.get(url, headers),
             {:ok, decoded} <- decode_body(body),
             {:ok, items} <- extract_data(decoded) do
          AppLogger.api_info("API responded with #{length(items)} items")

          case validate_data(items) do
            :ok ->
              AppLogger.api_info("Data validation successful", count: length(items))
              process_data(items, cached, opts)

            {:error, :invalid_data} ->
              # Validation already logged the details
              {:error, :invalid_data}
          end
        else
          {:ok, %{status_code: status, body: body}} ->
            AppLogger.api_error("HTTP error",
              status: status,
              body_preview: slice(body)
            )

            handle_http_error(status, body)

          {:error, reason} ->
            AppLogger.api_error("Request failed", error: inspect(reason))
            handle_request_error(reason)

          other ->
            AppLogger.api_error("Unexpected result", result: inspect(other))
            handle_unexpected_result(other)
        end
      end

      defp fetch_and_cache do
        case fetch_from_api() do
          {:ok, items} ->
            cache_name = Application.get_env(:wanderer_notifier, :cache_name, :wanderer_cache)

            AppLogger.api_info("Caching fetched data",
              count: length(items),
              key: cache_key(),
              ttl: cache_ttl()
            )

            :ok = Cachex.put(cache_name, cache_key(), items, ttl: :timer.seconds(cache_ttl()))
            {:ok, items}

          error ->
            AppLogger.api_error("Failed to fetch and cache data", error: inspect(error))
            error
        end
      end

      defp fetch_from_api do
        base_url = Config.map_url_with_name()
        map_name = Config.map_slug()
        endpoint = endpoint()
        url = build_url(base_url, map_name, endpoint)
        headers = auth_header()

        AppLogger.api_info("Fetching from API", url: url)

        with {:ok, %{status_code: 200, body: body}} <- HttpClient.get(url, headers),
             {:ok, decoded} <- decode_body(body),
             {:ok, items} <- extract_data(decoded) do
          {:ok, items}
        else
          {:ok, %{status_code: status, body: body}} ->
            AppLogger.api_error("HTTP error",
              status: status,
              body_preview: slice(body)
            )

            {:error, {:http_error, status}}

          {:error, reason} ->
            AppLogger.api_error("Request failed", error: inspect(reason))
            {:error, reason}

          other ->
            AppLogger.api_error("Unexpected result", result: inspect(other))
            {:error, :unexpected_result}
        end
      end

      # Helper functions
      defp build_url(base_url, map_name, endpoint) do
        base_url
        |> String.trim_trailing("/")
        |> Kernel.<>("/api/maps/")
        |> Kernel.<>(map_name)
        |> Kernel.<>("/")
        |> Kernel.<>(endpoint)
      end

      defp auth_header do
        token = Config.map_token()
        AppLogger.api_info("Using auth token", token_length: String.length(token))
        [{"Authorization", "Bearer #{token}"}]
      end

      defp decode_body(body) when is_binary(body) do
        case Jason.decode(body) do
          {:ok, data} ->
            {:ok, data}

          error ->
            AppLogger.api_error("Failed to decode JSON", error: inspect(error))
            {:error, :json_decode_failed}
        end
      end

      defp decode_body(map) when is_map(map), do: {:ok, map}
      defp decode_body(other), do: {:error, :invalid_body}

      defp handle_http_error(status, body) do
        error_preview = if is_binary(body), do: String.slice(body, 0, 100), else: inspect(body)

        AppLogger.api_error("API HTTP error",
          status: status,
          body_preview: error_preview
        )

        {:error, {:http_error, status}}
      end

      defp handle_request_error(reason) do
        AppLogger.api_error("Request failed", error: inspect(reason))
        {:error, reason}
      end

      defp handle_unexpected_result(result) do
        AppLogger.api_error("Unexpected result", result: inspect(result))
        {:error, :unexpected_result}
      end

      defp slice(body) when is_binary(body) do
        if String.length(body) > 100 do
          String.slice(body, 0, 100) <> "..."
        else
          body
        end
      end

      defp slice(body), do: inspect(body)

      defp fallback(cached, reason) when is_list(cached) and cached != [] do
        AppLogger.api_info(
          "Using #{length(cached)} cached items as fallback",
          reason: inspect(reason)
        )

        {:ok, cached}
      end

      defp fallback([], reason) do
        AppLogger.api_error("Fallback with empty cache", reason: inspect(reason))
        {:error, reason}
      end

      defp fallback(nil, reason) do
        AppLogger.api_error("Fallback with nil cache", reason: inspect(reason))
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
