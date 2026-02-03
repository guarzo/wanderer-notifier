defmodule WandererNotifier.Infrastructure.Adapters.ESI.Service do
  @moduledoc """
  Service for interacting with EVE Online's ESI (Swagger Interface) API.
  Provides high-level functions for common ESI operations.

  This service uses the cache facade for all cache operations.
  """

  # 30 seconds default timeout
  @default_timeout 30_000

  require Logger

  alias WandererNotifier.Infrastructure.Cache

  @behaviour WandererNotifier.Infrastructure.Adapters.ESI.ServiceBehaviour

  # Define error structs
  defmodule TimeoutError do
    @moduledoc """
    Error raised when an ESI API call times out.
    """
    defexception [:message]
  end

  defmodule ApiError do
    @moduledoc """
    Error raised when an ESI API call returns an error.
    """
    defexception [:reason, :message]
  end

  @impl WandererNotifier.Infrastructure.Adapters.ESI.ServiceBehaviour
  @spec get_killmail(integer(), String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def get_killmail(kill_id, killmail_hash, opts \\ []) do
    cache_key = Cache.Keys.killmail(kill_id)

    case Cache.get(cache_key) do
      {:ok, data} ->
        {:ok, data}

      {:error, :not_found} ->
        case esi_client().get_killmail(kill_id, killmail_hash, Keyword.merge(retry_opts(), opts)) do
          {:ok, data} when is_map(data) ->
            Cache.put(cache_key, data, Cache.ttl(:killmail))
            {:ok, data}

          {:error, reason} ->
            handle_killmail_error(reason, kill_id)
        end
    end
  end

  @impl WandererNotifier.Infrastructure.Adapters.ESI.ServiceBehaviour
  @spec get_character_info(integer(), keyword()) :: {:ok, map()} | {:error, term()}
  def get_character_info(character_id, opts \\ []) do
    case Cache.get_character(character_id) do
      {:ok, data} ->
        {:ok, data}

      {:error, :not_found} ->
        case esi_client().get_character_info(character_id, Keyword.merge(retry_opts(), opts)) do
          {:ok, data} when is_map(data) ->
            Cache.put_character(character_id, data)
            {:ok, data}

          {:error, reason} ->
            {:error, reason}
        end
    end
  end

  @impl WandererNotifier.Infrastructure.Adapters.ESI.ServiceBehaviour
  @spec get_corporation_info(integer(), keyword()) :: {:ok, map()} | {:error, term()}
  def get_corporation_info(corporation_id, opts \\ []) do
    case Cache.get_corporation(corporation_id) do
      {:ok, data} ->
        {:ok, data}

      {:error, :not_found} ->
        case esi_client().get_corporation_info(corporation_id, Keyword.merge(retry_opts(), opts)) do
          {:ok, data} when is_map(data) ->
            Cache.put_corporation(corporation_id, data)
            {:ok, data}

          {:error, reason} ->
            {:error, reason}
        end
    end
  end

  @impl WandererNotifier.Infrastructure.Adapters.ESI.ServiceBehaviour
  @spec get_alliance_info(integer(), keyword()) :: {:ok, map()} | {:error, term()}
  def get_alliance_info(alliance_id, opts \\ []) do
    case Cache.get_alliance(alliance_id) do
      {:ok, data} ->
        {:ok, data}

      {:error, :not_found} ->
        case esi_client().get_alliance_info(alliance_id, Keyword.merge(retry_opts(), opts)) do
          {:ok, data} when is_map(data) ->
            Cache.put_alliance(alliance_id, data)
            {:ok, data}

          {:error, reason} ->
            {:error, reason}
        end
    end
  end

  @impl true
  @spec get_ship_type_name(integer(), keyword()) :: {:ok, map()} | {:error, term()}
  def get_ship_type_name(ship_type_id, opts \\ []) do
    case get_type_info(ship_type_id, opts) do
      {:ok, %{"name" => name}} ->
        {:ok, %{"name" => name}}

      {:ok, _} ->
        Logger.error("ESI Service: Missing name in type info")
        {:error, :esi_data_missing}

      error ->
        error
    end
  end

  @impl WandererNotifier.Infrastructure.Adapters.ESI.ServiceBehaviour
  @spec get_type_info(integer(), keyword()) :: {:ok, map()} | {:error, term()}
  def get_type_info(type_id, opts \\ []) do
    case Cache.get_universe_type(type_id) do
      {:ok, data} ->
        {:ok, data}

      {:error, :not_found} ->
        case esi_client().get_universe_type(type_id, Keyword.merge(retry_opts(), opts)) do
          {:ok, data} when is_map(data) ->
            Cache.put_universe_type(type_id, data)
            {:ok, data}

          {:error, reason} ->
            {:error, reason}
        end
    end
  end

  @doc """
  Get type names for multiple type IDs efficiently.
  Returns a map of type_id => name
  """
  @spec get_type_names(list(integer())) :: {:ok, map()} | {:error, term()}
  def get_type_names(type_ids) when is_list(type_ids) do
    results =
      type_ids
      |> Enum.uniq()
      |> Enum.map(fn type_id ->
        case get_type_info(type_id) do
          {:ok, %{"name" => name}} -> {to_string(type_id), name}
          _ -> nil
        end
      end)
      |> Enum.reject(&is_nil/1)
      |> Map.new()

    {:ok, results}
  end

  @doc """
  Searches for inventory types using the ESI /search/ endpoint.
  """
  def search_inventory_type(query, strict \\ true, opts \\ []) do
    cache_key = Cache.Keys.custom("search", "inventory_type_#{query}_#{strict}")

    case Cache.get(cache_key) do
      {:ok, data} ->
        {:ok, data}

      {:error, :not_found} ->
        case esi_client().search_inventory_type(query, strict, Keyword.merge(retry_opts(), opts)) do
          {:ok, data} ->
            Cache.put_with_ttl(cache_key, data, Cache.ttl(:system))
            {:ok, data}

          {:error, reason} ->
            {:error, reason}
        end
    end
  end

  @impl true
  def get_universe_type(type_id, opts \\ []), do: get_type_info(type_id, opts)

  @doc """
  Fetches solar system info from ESI given a solar_system_id.
  Expects the response to include a "name" field.
  """
  @impl WandererNotifier.Infrastructure.Adapters.ESI.ServiceBehaviour
  @spec get_system(integer() | String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def get_system(system_id, opts \\ []) do
    case Cache.get_system(system_id) do
      {:ok, data} ->
        {:ok, data}

      {:error, :not_found} ->
        case esi_client().get_system(system_id, Keyword.merge(retry_opts(), opts)) do
          {:ok, data} when is_map(data) ->
            Cache.put_system(system_id, data)
            {:ok, data}

          {:error, reason} ->
            {:error, reason}
        end
    end
  end

  # Compatibility aliases - simplified to direct function calls
  @impl WandererNotifier.Infrastructure.Adapters.ESI.ServiceBehaviour
  def get_system_info(system_id, opts \\ []), do: get_system(system_id, opts)

  @impl WandererNotifier.Infrastructure.Adapters.ESI.ServiceBehaviour
  def get_character(character_id, opts \\ []), do: get_character_info(character_id, opts)

  @impl WandererNotifier.Infrastructure.Adapters.ESI.ServiceBehaviour
  def get_type(type_id, opts \\ []), do: get_type_info(type_id, opts)

  @impl WandererNotifier.Infrastructure.Adapters.ESI.ServiceBehaviour
  def get_system_kills(system_id, limit, opts \\ []) do
    _ = {system_id, limit, opts}
    {:ok, []}
  end

  @impl WandererNotifier.Infrastructure.Adapters.ESI.ServiceBehaviour
  def search(query, categories, opts \\ []) do
    case categories do
      ["inventory_type" | _] -> search_inventory_type(query, true, opts)
      _ -> {:ok, %{}}
    end
  end

  # Private helper functions

  defp esi_client do
    Application.get_env(
      :wanderer_notifier,
      :esi_client,
      WandererNotifier.Infrastructure.Adapters.ESI.Client
    )
  end

  defp retry_opts do
    [
      timeout: @default_timeout,
      recv_timeout: @default_timeout
    ]
  end

  defp handle_killmail_error(reason, kill_id) do
    case reason do
      :timeout ->
        Logger.error(
          "ESI Service: Request timed out for kill_id=#{kill_id} after #{@default_timeout}ms"
        )

      _ ->
        Logger.error(
          "ESI Service: Failed to fetch killmail data for kill_id=#{kill_id}: #{inspect(reason)}"
        )
    end

    {:error, reason}
  end
end
