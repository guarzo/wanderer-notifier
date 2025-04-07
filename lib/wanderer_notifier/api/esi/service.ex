defmodule WandererNotifier.Api.ESI.Service do
  @moduledoc """
  Service for interacting with EVE Online's ESI (Swagger Interface) API.
  Provides high-level functions for common ESI operations.
  """

  require Logger
  alias WandererNotifier.Api.ESI.Client
  alias WandererNotifier.Data.Cache.Keys, as: CacheKeys
  alias WandererNotifier.Data.Cache.Repository, as: CacheRepo
  alias WandererNotifier.Logger.Logger, as: AppLogger

  @behaviour WandererNotifier.Api.ESI.ServiceBehaviour

  @impl WandererNotifier.Api.ESI.ServiceBehaviour
  def get_killmail(kill_id, killmail_hash) do
    cache_key = CacheKeys.killmail(kill_id, killmail_hash)

    case CacheRepo.get(cache_key) do
      nil ->
        AppLogger.api_debug("🔍 ESI cache miss for killmail", kill_id: kill_id)

        case Client.get_killmail(kill_id, killmail_hash, retry_opts()) do
          {:ok, data} = result ->
            CacheRepo.put(cache_key, data)
            result

          error ->
            error
        end

      data ->
        AppLogger.api_debug("✨ ESI cache hit for killmail", kill_id: kill_id)
        {:ok, data}
    end
  end

  @impl WandererNotifier.Api.ESI.ServiceBehaviour
  def get_character_info(character_id, _opts \\ []) do
    cache_key = CacheKeys.character(character_id)

    case CacheRepo.get(cache_key) do
      nil ->
        AppLogger.api_debug("🔍 ESI cache miss for character", character_id: character_id)

        case Client.get_character_info(character_id, retry_opts()) do
          {:ok, data} = result ->
            CacheRepo.put(cache_key, data)
            result

          error ->
            error
        end

      data when is_map(data) ->
        AppLogger.api_debug("✨ ESI cache hit for character (map data)",
          character_id: character_id
        )

        {:ok, data}

      name when is_binary(name) ->
        # The cache contains just the character name as a string
        # Wrap it in a map to make it compatible with the expected format
        AppLogger.api_debug("✨ ESI cache hit for character (string name)",
          character_id: character_id,
          character_name: name
        )

        # Convert string name to compatible map format
        {:ok, %{"name" => name}}

      other ->
        AppLogger.api_warn("⚠️ Invalid character data in cache",
          character_id: character_id,
          data_type: inspect(other)
        )

        # Default to an error
        {:error, :invalid_cache_data}
    end
  end

  @impl WandererNotifier.Api.ESI.ServiceBehaviour
  def get_corporation_info(corporation_id, _opts \\ []) do
    cache_key = CacheKeys.corporation(corporation_id)

    case CacheRepo.get(cache_key) do
      nil ->
        AppLogger.api_debug("🔍 ESI cache miss for corporation", corporation_id: corporation_id)

        case Client.get_corporation_info(corporation_id, retry_opts()) do
          {:ok, data} = result ->
            CacheRepo.put(cache_key, data)
            result

          error ->
            error
        end

      data when is_map(data) ->
        AppLogger.api_debug("✨ ESI cache hit for corporation (map data)",
          corporation_id: corporation_id
        )

        {:ok, data}

      name when is_binary(name) ->
        # The cache contains just the corporation name as a string
        AppLogger.api_debug("✨ ESI cache hit for corporation (string name)",
          corporation_id: corporation_id,
          corporation_name: name
        )

        # Convert string name to compatible map format
        {:ok, %{"name" => name}}

      other ->
        AppLogger.api_warn("⚠️ Invalid corporation data in cache",
          corporation_id: corporation_id,
          data_type: inspect(other)
        )

        # Default to an error
        {:error, :invalid_cache_data}
    end
  end

  @impl WandererNotifier.Api.ESI.ServiceBehaviour
  def get_alliance_info(alliance_id, _opts \\ []) do
    cache_key = CacheKeys.alliance(alliance_id)

    case CacheRepo.get(cache_key) do
      nil ->
        AppLogger.api_debug("🔍 ESI cache miss for alliance", alliance_id: alliance_id)

        case Client.get_alliance_info(alliance_id, retry_opts()) do
          {:ok, data} = result ->
            CacheRepo.put(cache_key, data)
            result

          error ->
            error
        end

      data when is_map(data) ->
        AppLogger.api_debug("✨ ESI cache hit for alliance (map data)", alliance_id: alliance_id)
        {:ok, data}

      name when is_binary(name) ->
        # The cache contains just the alliance name as a string
        AppLogger.api_debug("✨ ESI cache hit for alliance (string name)",
          alliance_id: alliance_id,
          alliance_name: name
        )

        # Convert string name to compatible map format
        {:ok, %{"name" => name}}

      other ->
        AppLogger.api_warn("⚠️ Invalid alliance data in cache",
          alliance_id: alliance_id,
          data_type: inspect(other)
        )

        # Default to an error
        {:error, :invalid_cache_data}
    end
  end

  @impl true
  def get_ship_type_name(ship_type_id, _opts \\ []) do
    cache_key = CacheKeys.ship_type(ship_type_id)

    case CacheRepo.get(cache_key) do
      nil -> handle_cache_miss(ship_type_id, cache_key)
      data -> handle_cache_hit(ship_type_id, data)
    end
  end

  defp handle_cache_miss(ship_type_id, cache_key) do
    AppLogger.api_debug("🔍 ESI cache miss for ship type", ship_type_id: ship_type_id)

    case Client.get_universe_type(ship_type_id, retry_opts()) do
      {:ok, type_info} -> process_type_info(type_info, cache_key)
      error -> error
    end
  end

  defp handle_cache_hit(ship_type_id, data) do
    AppLogger.api_debug("✨ ESI cache hit for ship type", ship_type_id: ship_type_id)
    {:ok, data}
  end

  defp process_type_info(type_info, cache_key) do
    name = Map.get(type_info, "name")

    if name do
      result = %{"name" => name}
      CacheRepo.put(cache_key, result)
      {:ok, result}
    else
      {:error, :name_not_found}
    end
  end

  @impl WandererNotifier.Api.ESI.ServiceBehaviour
  def get_type_info(type_id, _opts \\ []) do
    cache_key = CacheKeys.ship_type(type_id)

    case CacheRepo.get(cache_key) do
      nil ->
        AppLogger.api_debug("🔍 ESI cache miss for type", type_id: type_id)

        case Client.get_universe_type(type_id, retry_opts()) do
          {:ok, data} = result ->
            CacheRepo.put(cache_key, data)
            result

          error ->
            error
        end

      data ->
        AppLogger.api_debug("✨ ESI cache hit for type", type_id: type_id)
        {:ok, data}
    end
  end

  def search_inventory_type(query, strict \\ true, _opts \\ []) do
    Client.search_inventory_type(query, strict)
  end

  @doc """
  Fetches solar system info from ESI given a solar_system_id.
  Expects the response to include a "name" field.
  """
  def get_solar_system_name(system_id, _opts \\ []) do
    cache_key = CacheKeys.system(system_id)

    case CacheRepo.get(cache_key) do
      nil ->
        AppLogger.api_debug("🔍 ESI cache miss for solar system", system_id: system_id)

        case Client.get_solar_system(system_id, retry_opts()) do
          {:ok, data} = result ->
            CacheRepo.put(cache_key, data)
            result

          error ->
            error
        end

      data ->
        AppLogger.api_debug("✨ ESI cache hit for solar system", system_id: system_id)
        {:ok, data}
    end
  end

  @doc """
  Alias for get_solar_system_name to maintain consistent naming.
  Fetches solar system info from ESI given a system_id.
  """
  @impl WandererNotifier.Api.ESI.ServiceBehaviour
  def get_system_info(system_id, _opts \\ []) do
    cache_key = CacheKeys.system(system_id)

    case CacheRepo.get(cache_key) do
      nil ->
        AppLogger.api_debug("🔍 ESI cache miss for system", system_id: system_id)

        case Client.get_solar_system(system_id, retry_opts()) do
          {:ok, data} = result ->
            CacheRepo.put(cache_key, data)
            result

          error ->
            error
        end

      data when is_map(data) ->
        AppLogger.api_debug("✨ ESI cache hit for system (map data)", system_id: system_id)
        {:ok, data}

      name when is_binary(name) ->
        # The cache contains just the system name as a string
        AppLogger.api_debug("✨ ESI cache hit for system (string name)",
          system_id: system_id,
          system_name: name
        )

        # Convert string name to compatible map format
        {:ok, %{"name" => name}}

      other ->
        AppLogger.api_warn("⚠️ Invalid system data in cache",
          system_id: system_id,
          data_type: inspect(other)
        )

        # Default to an error
        {:error, :invalid_cache_data}
    end
  end

  @doc """
  Fetches region info from ESI given a region_id.
  Expects the response to include a "name" field.
  """
  def get_region_name(region_id, _opts \\ []) do
    cache_key = CacheKeys.region(region_id)

    case CacheRepo.get(cache_key) do
      nil ->
        AppLogger.api_debug("🔍 ESI cache miss for region", region_id: region_id)

        case Client.get_region(region_id) do
          {:ok, data} = result ->
            CacheRepo.put(cache_key, data)
            result

          error ->
            error
        end

      data ->
        AppLogger.api_debug("✨ ESI cache hit for region", region_id: region_id)
        {:ok, data}
    end
  end

  @doc """
  Fetches constellation info from ESI given a constellation_id.
  """
  def get_constellation_info(constellation_id, _opts \\ []) do
    cache_key = CacheKeys.constellation(constellation_id)

    case CacheRepo.get(cache_key) do
      nil ->
        AppLogger.api_debug("🔍 ESI cache miss for constellation",
          constellation_id: constellation_id
        )

        case Client.get_constellation(constellation_id) do
          {:ok, data} = result ->
            CacheRepo.put(cache_key, data)
            result

          error ->
            error
        end

      data ->
        AppLogger.api_debug("✨ ESI cache hit for constellation",
          constellation_id: constellation_id
        )

        {:ok, data}
    end
  end

  @impl WandererNotifier.Api.ESI.ServiceBehaviour
  def get_character(character_id) do
    get_character_info(character_id)
  end

  @impl WandererNotifier.Api.ESI.ServiceBehaviour
  def get_system(system_id) do
    get_system_info(system_id)
  end

  @impl WandererNotifier.Api.ESI.ServiceBehaviour
  def get_type(type_id) do
    get_type_info(type_id)
  end

  @impl true
  def get_system_kills(system_id, limit) do
    AppLogger.api_debug("[ESI] Fetching system kills", system_id: system_id, limit: limit)
    Client.get_system_kills(system_id, limit)
  end

  # Helper to get retry options
  defp retry_opts do
    [
      max_retries: 3,
      # 1 second
      initial_backoff: 1000,
      label: "ESI"
    ]
  end
end
