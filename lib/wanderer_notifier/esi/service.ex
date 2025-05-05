defmodule WandererNotifier.ESI.Service do
  @moduledoc """
  Service for interacting with EVE Online's ESI (Swagger Interface) API.
  Provides high-level functions for common ESI operations.
  """

  require Logger
  alias WandererNotifier.ESI.Client
  alias WandererNotifier.ESI.Entities.{Character, Corporation, Alliance, SolarSystem}
  alias WandererNotifier.Cache.Keys, as: CacheKeys
  alias WandererNotifier.Cache.CachexImpl, as: CacheRepo
  alias WandererNotifier.Logger.Logger, as: AppLogger

  @behaviour WandererNotifier.ESI.ServiceBehaviour

  @impl WandererNotifier.ESI.ServiceBehaviour
  def get_killmail(kill_id, killmail_hash) do
    cache_key = CacheKeys.killmail(kill_id, killmail_hash)

    case CacheRepo.get(cache_key) do
      {:ok, data} ->
        AppLogger.api_debug("✨ ESI cache hit for killmail", kill_id: kill_id)
        {:ok, data}

      {:error, _} ->
        AppLogger.api_debug("🔍 ESI cache miss for killmail", kill_id: kill_id)

        case Client.get_killmail(kill_id, killmail_hash, retry_opts()) do
          {:ok, data} = result ->
            CacheRepo.put(cache_key, data)
            result

          error ->
            error
        end
    end
  end

  @impl WandererNotifier.ESI.ServiceBehaviour
  def get_character_info(character_id, _opts \\ []) do
    cache_key = CacheKeys.character(character_id)

    case CacheRepo.get(cache_key) do
      {:ok, data} ->
        AppLogger.api_debug("✨ ESI cache hit for character", character_id: character_id)
        {:ok, data}

      {:error, _} ->
        AppLogger.api_debug("🔍 ESI cache miss for character", character_id: character_id)

        case Client.get_character_info(character_id, retry_opts()) do
          {:ok, data} = result ->
            CacheRepo.put(cache_key, data)
            result

          error ->
            error
        end
    end
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
  def get_corporation_info(corporation_id, _opts \\ []) do
    cache_key = CacheKeys.corporation(corporation_id)

    case CacheRepo.get(cache_key) do
      {:ok, data} ->
        AppLogger.api_debug("✨ ESI cache hit for corporation", corporation_id: corporation_id)
        {:ok, data}

      {:error, _} ->
        AppLogger.api_debug("🔍 ESI cache miss for corporation", corporation_id: corporation_id)

        case Client.get_corporation_info(corporation_id, retry_opts()) do
          {:ok, data} = result ->
            CacheRepo.put(cache_key, data)
            result

          error ->
            error
        end
    end
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
  def get_alliance_info(alliance_id, _opts \\ []) do
    cache_key = CacheKeys.alliance(alliance_id)

    case CacheRepo.get(cache_key) do
      {:ok, data} ->
        AppLogger.api_debug("✨ ESI cache hit for alliance", alliance_id: alliance_id)
        {:ok, data}

      {:error, _} ->
        AppLogger.api_debug("🔍 ESI cache miss for alliance", alliance_id: alliance_id)

        case Client.get_alliance_info(alliance_id, retry_opts()) do
          {:ok, data} = result ->
            CacheRepo.put(cache_key, data)
            result

          error ->
            error
        end
    end
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
  def get_ship_type_name(ship_type_id, _opts \\ []) do
    cache_key = CacheKeys.ship_type(ship_type_id)

    case CacheRepo.get(cache_key) do
      {:ok, data} -> handle_cache_hit(ship_type_id, data)
      {:error, _} -> handle_cache_miss(ship_type_id, cache_key)
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

  @impl WandererNotifier.ESI.ServiceBehaviour
  def get_type_info(type_id, _opts \\ []) do
    cache_key = CacheKeys.ship_type(type_id)

    case CacheRepo.get(cache_key) do
      {:ok, data} ->
        AppLogger.api_debug("✨ ESI cache hit for type", type_id: type_id)
        {:ok, data}

      {:error, _} ->
        AppLogger.api_debug("🔍 ESI cache miss for type", type_id: type_id)

        case Client.get_universe_type(type_id, retry_opts()) do
          {:ok, data} = result ->
            CacheRepo.put(cache_key, data)
            result

          error ->
            error
        end
    end
  end

  @doc """
  Searches for inventory types using the ESI /search/ endpoint.
  """
  def search_inventory_type(query, strict \\ true, _opts \\ []) do
    Client.search_inventory_type(query, strict)
  end

  @doc """
  Fetches solar system info from ESI given a solar_system_id.
  Expects the response to include a "name" field.
  """
  @impl WandererNotifier.ESI.ServiceBehaviour
  def get_system(system_id, _opts \\ []) do
    cache_key = CacheKeys.system(system_id)

    case CacheRepo.get(cache_key) do
      {:ok, data} ->
        AppLogger.api_debug("✨ ESI cache hit for solar system", system_id: system_id)
        {:ok, data}

      {:error, _} ->
        AppLogger.api_debug("🔍 ESI cache miss for solar system", system_id: system_id)

        case Client.get_solar_system(system_id, retry_opts()) do
          {:ok, data} = result ->
            CacheRepo.put(cache_key, data)
            result

          error ->
            error
        end
    end
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
    with {:ok, data} <- get_system(system_id, opts) do
      {:ok, SolarSystem.from_esi_data(data)}
    end
  end

  @doc """
  Alias for get_system to maintain backward compatibility.
  Fetches solar system info from ESI given a system_id.
  """
  @impl WandererNotifier.ESI.ServiceBehaviour
  def get_system_info(system_id, opts \\ []) do
    get_system(system_id, opts)
  end

  @impl WandererNotifier.ESI.ServiceBehaviour
  def get_character(character_id, opts \\ []) do
    get_character_info(character_id, opts)
  end

  @impl WandererNotifier.ESI.ServiceBehaviour
  def get_type(type_id, opts \\ []) do
    get_type_info(type_id, opts)
  end

  @impl WandererNotifier.ESI.ServiceBehaviour
  def get_system_kills(system_id, limit \\ 50, _opts \\ []) do
    Client.get_system_kills(system_id, limit)
  end

  # Get retry options with default values
  defp retry_opts do
    [
      max_attempts: 3,
      base_timeout: 1000,
      max_timeout: 5000
    ]
  end
end
