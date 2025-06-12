defmodule WandererNotifier.ESI.Service do
  @moduledoc """
  Service for interacting with EVE Online's ESI (Swagger Interface) API.
  Provides high-level functions for common ESI operations.
  """

  # 30 seconds default timeout
  @default_timeout 30_000

  require Logger
  alias WandererNotifier.ESI.Entities.{Character, Corporation, Alliance, SolarSystem}
  alias WandererNotifier.Cache.Keys, as: CacheKeys
  alias WandererNotifier.Cache.CacheHelper
  alias WandererNotifier.Logger.Logger, as: AppLogger
  alias WandererNotifier.Config

  @behaviour WandererNotifier.ESI.ServiceBehaviour

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

  @impl WandererNotifier.ESI.ServiceBehaviour
  def get_killmail(kill_id, killmail_hash, opts \\ []) do
    cache_name = Keyword.get(opts, :cache_name, Config.cache_name())
    cache_key = CacheKeys.killmail(kill_id, killmail_hash)

    case Cachex.get(cache_name, cache_key) do
      {:ok, data} when is_map(data) and map_size(data) > 0 ->
        {:ok, data}

      _ ->
        fetch_from_esi(kill_id, killmail_hash, cache_name, cache_key, opts)
    end
  end

  defp fetch_from_esi(kill_id, killmail_hash, cache_name, cache_key, opts) do
    # Get the raw response from the client
    response =
      esi_client().get_killmail(kill_id, killmail_hash, Keyword.merge(retry_opts(), opts))

    case response do
      {:ok, data} when is_map(data) and map_size(data) > 0 ->
        # Only cache if we have a cache name and key
        if cache_name && cache_key do
          cache_put(cache_name, cache_key, data)
        end

        {:ok, data}

      {:ok, nil} ->
        AppLogger.api_error("ESI Service: Received nil data for kill_id=#{kill_id}")
        {:error, :esi_data_missing}

      {:ok, data} ->
        AppLogger.api_error(
          "ESI Service: Invalid data format for kill_id=#{kill_id}: #{inspect(data)}"
        )

        {:error, :esi_data_missing}

      {:error, :timeout} ->
        AppLogger.api_error(
          "ESI Service: Request timed out for kill_id=#{kill_id} after #{Keyword.get(opts, :timeout, @default_timeout)}ms"
        )

        {:error, :timeout}

      error ->
        AppLogger.api_error(
          "ESI Service: Failed to fetch killmail data for kill_id=#{kill_id}: #{inspect(error)}"
        )

        error
    end
  end

  @impl WandererNotifier.ESI.ServiceBehaviour
  def get_character_info(character_id, opts \\ []) do
    CacheHelper.fetch_with_cache(
      :character,
      character_id,
      opts,
      fn id, fetch_opts -> esi_client().get_character_info(id, fetch_opts) end,
      "character"
    )
  end

  @doc """
  Get character info and return it as a Character struct.

  ## Parameters
    - character_id: The character ID to look up
    - opts: Optional parameters

  ## Returns
    - {:ok, %Character{}} on success
    - {:error, reason} on failure
  """
  def get_character_struct(character_id, opts \\ []) do
    with {:ok, data} <- get_character_info(character_id, opts) do
      {:ok, Character.from_esi_data(data)}
    end
  end

  @impl WandererNotifier.ESI.ServiceBehaviour
  def get_corporation_info(corporation_id, opts \\ []) do
    CacheHelper.fetch_with_cache(
      :corporation,
      corporation_id,
      opts,
      fn id, fetch_opts -> esi_client().get_corporation_info(id, fetch_opts) end,
      "corporation"
    )
  end

  @doc """
  Get corporation info and return it as a Corporation struct.

  ## Parameters
    - corporation_id: The corporation ID to look up
    - opts: Optional parameters

  ## Returns
    - {:ok, %Corporation{}} on success
    - {:error, reason} on failure
  """
  def get_corporation_struct(corporation_id, opts \\ []) do
    with {:ok, data} <- get_corporation_info(corporation_id, opts) do
      {:ok, Corporation.from_esi_data(data)}
    end
  end

  @impl WandererNotifier.ESI.ServiceBehaviour
  def get_alliance_info(alliance_id, opts \\ []) do
    CacheHelper.fetch_with_cache(
      :alliance,
      alliance_id,
      opts,
      fn id, fetch_opts -> esi_client().get_alliance_info(id, fetch_opts) end,
      "alliance"
    )
  end

  @doc """
  Get alliance info and return it as an Alliance struct.

  ## Parameters
    - alliance_id: The alliance ID to look up
    - opts: Optional parameters

  ## Returns
    - {:ok, %Alliance{}} on success
    - {:error, reason} on failure
  """
  def get_alliance_struct(alliance_id, opts \\ []) do
    with {:ok, data} <- get_alliance_info(alliance_id, opts) do
      {:ok, Alliance.from_esi_data(data)}
    end
  end

  @impl true
  def get_ship_type_name(ship_type_id, opts \\ []) do
    cache_name = Keyword.get(opts, :cache_name, Config.cache_name())
    cache_key = CacheKeys.type(ship_type_id)

    case Cachex.get(cache_name, cache_key) do
      {:ok, data} when is_map(data) and map_size(data) > 0 ->
        handle_cache_hit(ship_type_id, data)

      _ ->
        handle_cache_miss(ship_type_id, cache_key, opts)
    end
  end

  defp handle_cache_miss(ship_type_id, cache_key, opts) do
    AppLogger.api_debug("🔍 ESI cache miss for ship type", ship_type_id: ship_type_id)

    cache_name = Keyword.get(opts, :cache_name, Config.cache_name())

    case esi_client().get_universe_type(ship_type_id, Keyword.merge(retry_opts(), opts)) do
      {:ok, type_info} when is_map(type_info) and map_size(type_info) > 0 ->
        case type_info do
          %{"name" => name} ->
            cache_put(cache_name, cache_key, type_info)
            {:ok, %{"name" => name}}

          _ ->
            AppLogger.api_error("ESI Service: Missing name in type info",
              type_info: inspect(type_info)
            )

            {:error, :esi_data_missing}
        end

      error ->
        error
    end
  end

  defp handle_cache_hit(ship_type_id, data) do
    AppLogger.api_debug("✨ ESI cache hit for ship type", ship_type_id: ship_type_id)

    case data do
      %{"name" => name} ->
        {:ok, %{"name" => name}}

      _ ->
        AppLogger.api_error("ESI Service: Missing name in cached type info", data: inspect(data))
        {:error, :esi_data_missing}
    end
  end

  @impl WandererNotifier.ESI.ServiceBehaviour
  def get_type_info(type_id, opts \\ []) do
    cache_name = Keyword.get(opts, :cache_name, Config.cache_name())
    cache_key = CacheKeys.type(type_id)

    case Cachex.get(cache_name, cache_key) do
      {:ok, data} when is_map(data) and map_size(data) > 0 ->
        handle_cache_hit(type_id, data)

      _ ->
        handle_cache_miss(type_id, cache_key, opts)
    end
  end

  @doc """
  Searches for inventory types using the ESI /search/ endpoint.
  """
  def search_inventory_type(query, strict \\ true, opts \\ []) do
    custom_key = CacheKeys.search_inventory_type(query, strict)

    CacheHelper.fetch_with_custom_key(
      custom_key,
      opts,
      fn -> esi_client().search_inventory_type(query, opts) end,
      %{query: query, type: "inventory type search"}
    )
  end

  @impl true
  def get_universe_type(type_id, opts \\ []) do
    cache_name = Keyword.get(opts, :cache_name, Config.cache_name())
    cache_key = CacheKeys.type(type_id)

    case Cachex.get(cache_name, cache_key) do
      {:ok, data} when is_map(data) and map_size(data) > 0 ->
        AppLogger.api_debug("✨ ESI cache hit for universe type", type_id: type_id)
        {:ok, data}

      _ ->
        AppLogger.api_debug("🔍 ESI cache miss for universe type", type_id: type_id)
        fetch_and_cache_type(type_id, cache_name, cache_key, opts)
    end
  end

  defp fetch_and_cache_type(type_id, cache_name, cache_key, opts) do
    case esi_client().get_universe_type(type_id, Keyword.merge(retry_opts(), opts)) do
      {:ok, data} when is_map(data) and map_size(data) > 0 ->
        cache_put(cache_name, cache_key, data)
        {:ok, data}

      {:ok, nil} ->
        AppLogger.api_error("ESI service got nil type data", %{
          type_id: type_id
        })

        {:error, :type_not_found}

      {:ok, invalid_data} ->
        AppLogger.api_error("ESI service got invalid type data", %{
          type_id: type_id,
          data: inspect(invalid_data)
        })

        {:error, :invalid_type_data}

      error ->
        AppLogger.api_error("ESI service type error", %{
          type_id: type_id,
          error: inspect(error)
        })

        error
    end
  end

  @doc """
  Fetches solar system info from ESI given a solar_system_id.
  Expects the response to include a "name" field.
  """
  @impl WandererNotifier.ESI.ServiceBehaviour
  def get_system(system_id, opts \\ []) do
    CacheHelper.fetch_with_cache(
      :system,
      system_id,
      opts,
      fn id, fetch_opts -> esi_client().get_system(id, fetch_opts) end,
      "solar system"
    )
  end

  @doc """
  Get solar system info and return it as a SolarSystem struct.

  ## Parameters
    - system_id: The solar system ID to look up
    - opts: Optional parameters

  ## Returns
    - {:ok, %SolarSystem{}} on success
    - {:error, reason} on failure
  """
  def get_system_struct(system_id, opts \\ []) do
    case get_system(system_id, opts) do
      {:ok, data} when is_map(data) and map_size(data) > 0 ->
        {:ok, SolarSystem.from_esi_data(data)}

      _ ->
        {:error, :system_not_found}
    end
  end

  @doc """
  Alias for get_system to maintain backward compatibility.
  Fetches solar system info from ESI given a system_id.
  """
  @impl WandererNotifier.ESI.ServiceBehaviour
  def get_system_info(system_id, opts \\ []) do
    cache_name = Keyword.get(opts, :cache_name, Config.cache_name())
    cache_key = CacheKeys.system(system_id)

    case Cachex.get(cache_name, cache_key) do
      {:ok, data} when is_map(data) and map_size(data) > 0 ->
        {:ok, data}

      _ ->
        fetch_and_cache_system(system_id, cache_name, cache_key, opts)
    end
  end

  defp fetch_and_cache_system(system_id, cache_name, cache_key, opts) do
    case esi_client().get_system(system_id, Keyword.merge(retry_opts(), opts)) do
      {:ok, data} when is_map(data) and map_size(data) > 0 ->
        cache_put(cache_name, cache_key, data)
        {:ok, data}

      {:ok, nil} ->
        AppLogger.api_error("ESI service got nil system data", %{
          system_id: system_id
        })

        {:error, :system_not_found}

      error ->
        AppLogger.api_error("ESI service system error", %{
          system_id: system_id,
          error: inspect(error)
        })

        error
    end
  end

  @impl WandererNotifier.ESI.ServiceBehaviour
  def get_character(character_id, opts \\ []) do
    CacheHelper.fetch_with_cache(
      :character,
      character_id,
      opts,
      fn id, fetch_opts -> esi_client().get_character_info(id, fetch_opts) end,
      "character"
    )
  end

  @impl WandererNotifier.ESI.ServiceBehaviour
  def get_type(type_id, opts \\ []) do
    CacheHelper.fetch_with_cache(
      :type,
      type_id,
      opts,
      fn id, fetch_opts -> esi_client().get_universe_type(id, fetch_opts) end,
      "type"
    )
  end

  @impl WandererNotifier.ESI.ServiceBehaviour
  def get_system_kills(system_id, limit, opts \\ []) do
    custom_key = CacheKeys.system_kills(system_id, limit)

    CacheHelper.fetch_with_custom_key(
      custom_key,
      opts,
      fn -> esi_client().get_system_kills(system_id, limit, opts) end,
      %{system_id: system_id, limit: limit, type: "system kills"}
    )
  end

  # Get retry options with default values
  defp retry_opts do
    [
      max_attempts: 3,
      base_timeout: 5_000,
      max_timeout: 15_000,
      backoff: :exponential
    ]
  end

  defp esi_client, do: WandererNotifier.Core.Dependencies.esi_client()

  # Fallback module that returns safe defaults to prevent crashes
  defmodule SafeCache do
    @moduledoc """
    A fallback module that provides safe access to cache functions when the real cache is unavailable.
    Returns default values to prevent application crashes when cache access fails.
    """
    def get(_cache_name, _key), do: {:error, :cache_not_available}
    def put(_cache_name, _key, _value), do: {:error, :cache_not_available}
    def delete(_cache_name, _key), do: {:error, :cache_not_available}
    def exists?(_cache_name, _key), do: false
  end

  @impl true
  def search(_category, _search, _opts \\ []), do: {:error, :not_implemented}

  defp cache_put(cache_name, key, value) do
    Cachex.put(cache_name, key, value)
  end
end
