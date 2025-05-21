defmodule WandererNotifier.ESI.Service do
  @moduledoc """
  Service for interacting with EVE Online's ESI (Swagger Interface) API.
  Provides high-level functions for common ESI operations.
  """

  require Logger
  alias WandererNotifier.ESI.Entities.{Character, Corporation, Alliance, SolarSystem}
  alias WandererNotifier.Cache.Keys, as: CacheKeys
  alias WandererNotifier.Logger.Logger, as: AppLogger

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

  defp cache_repo do
    repo =
      Application.get_env(
        :wanderer_notifier,
        :cache_repo,
        Cachex
      )

    # Ensure the module is loaded and available
    if Code.ensure_loaded?(repo) do
      repo
    else
      # Log this only once per minute to avoid log spam
      cache_error_key = :esi_cache_repo_error_logged
      last_logged = Process.get(cache_error_key)
      now = System.monotonic_time(:second)

      if is_nil(last_logged) || now - last_logged > 60 do
        AppLogger.api_warn(
          "Cache repository module #{inspect(repo)} not available in ESI Service, using fallback"
        )

        Process.put(cache_error_key, now)
      end

      # Return a dummy cache module that won't crash
      SafeCache
    end
  end

  defp cache_repo(cache_name) do
    repo = cache_repo()
    fn key -> repo.get(cache_name, key) end
  end

  @impl WandererNotifier.ESI.ServiceBehaviour
  def get_killmail(kill_id, killmail_hash, opts \\ []) do
    cache_name =
      Keyword.get(
        opts,
        :cache_name,
        Application.get_env(:wanderer_notifier, :cache_name, :wanderer_cache)
      )

    cache_key = CacheKeys.killmail(kill_id, killmail_hash)

    case cache_repo(cache_name).(cache_key) do
      {:ok, data} ->
        AppLogger.api_debug("✨ ESI cache hit for killmail", kill_id: kill_id)
        {:ok, data}

      {:error, _} ->
        AppLogger.api_debug("🔍 ESI cache miss for killmail", kill_id: kill_id)

        case esi_client().get_killmail(kill_id, killmail_hash, Keyword.merge(retry_opts(), opts)) do
          {:ok, data} = result ->
            cache_put(cache_name, cache_key, data)
            result

          error ->
            error
        end
    end
  end

  @impl WandererNotifier.ESI.ServiceBehaviour
  def get_character_info(character_id, opts \\ []) do
    cache_name =
      Keyword.get(
        opts,
        :cache_name,
        Application.get_env(:wanderer_notifier, :cache_name, :wanderer_cache)
      )

    cache_key = CacheKeys.character(character_id)

    case cache_repo(cache_name).(cache_key) do
      {:ok, data} ->
        AppLogger.api_debug("✨ ESI cache hit for character", character_id: character_id)
        {:ok, data}

      {:error, _} ->
        AppLogger.api_debug("🔍 ESI cache miss for character", character_id: character_id)

        case esi_client().get_character_info(character_id, Keyword.merge(retry_opts(), opts)) do
          {:ok, data} = result ->
            cache_put(cache_name, cache_key, data)
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
  def get_corporation_info(corporation_id, opts \\ []) do
    cache_name =
      Keyword.get(
        opts,
        :cache_name,
        Application.get_env(:wanderer_notifier, :cache_name, :wanderer_cache)
      )

    cache_key = CacheKeys.corporation(corporation_id)

    case cache_repo(cache_name).(cache_key) do
      {:ok, data} ->
        AppLogger.api_debug("✨ ESI cache hit for corporation", corporation_id: corporation_id)
        {:ok, data}

      {:error, _} ->
        AppLogger.api_debug("🔍 ESI cache miss for corporation", corporation_id: corporation_id)

        case esi_client().get_corporation_info(corporation_id, Keyword.merge(retry_opts(), opts)) do
          {:ok, data} = result ->
            cache_put(cache_name, cache_key, data)
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
  def get_alliance_info(alliance_id, opts \\ []) do
    cache_name =
      Keyword.get(
        opts,
        :cache_name,
        Application.get_env(:wanderer_notifier, :cache_name, :wanderer_cache)
      )

    cache_key = CacheKeys.alliance(alliance_id)

    case cache_repo(cache_name).(cache_key) do
      {:ok, data} ->
        AppLogger.api_debug("✨ ESI cache hit for alliance", alliance_id: alliance_id)
        {:ok, data}

      {:error, _} ->
        AppLogger.api_debug("🔍 ESI cache miss for alliance", alliance_id: alliance_id)

        case esi_client().get_alliance_info(alliance_id, Keyword.merge(retry_opts(), opts)) do
          {:ok, data} = result ->
            cache_put(cache_name, cache_key, data)
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
  def get_ship_type_name(ship_type_id, opts \\ []) do
    cache_name =
      Keyword.get(
        opts,
        :cache_name,
        Application.get_env(:wanderer_notifier, :cache_name, :wanderer_cache)
      )

    cache_key = CacheKeys.type(ship_type_id)

    case cache_repo(cache_name).(cache_key) do
      {:ok, data} ->
        handle_cache_hit(ship_type_id, data)

      {:error, _} ->
        handle_cache_miss(ship_type_id, cache_key, opts)
    end
  end

  defp handle_cache_miss(ship_type_id, cache_key, opts) do
    AppLogger.api_debug("🔍 ESI cache miss for ship type", ship_type_id: ship_type_id)

    case esi_client().get_ship_type_name(ship_type_id, Keyword.merge(retry_opts(), opts)) do
      {:ok, type_info} -> process_type_info(type_info, cache_key)
      error -> error
    end
  end

  defp handle_cache_hit(ship_type_id, data) do
    AppLogger.api_debug("✨ ESI cache hit for ship type", ship_type_id: ship_type_id)
    {:ok, data}
  end

  defp process_type_info(type_info, cache_key) do
    cache_repo().put(cache_key, type_info)
    {:ok, type_info}
  end

  @impl WandererNotifier.ESI.ServiceBehaviour
  def get_type_info(type_id, opts \\ []) do
    cache_name =
      Keyword.get(
        opts,
        :cache_name,
        Application.get_env(:wanderer_notifier, :cache_name, :wanderer_cache)
      )

    cache_key = CacheKeys.type(type_id)

    case cache_repo(cache_name).(cache_key) do
      {:ok, data} ->
        handle_cache_hit(type_id, data)

      {:error, _} ->
        handle_cache_miss(type_id, cache_key, opts)
    end
  end

  @doc """
  Searches for inventory types using the ESI /search/ endpoint.
  """
  def search_inventory_type(query, strict \\ true, _opts \\ []) do
    esi_client().search_inventory_type(query, strict)
  end

  @doc """
  Fetches solar system info from ESI given a solar_system_id.
  Expects the response to include a "name" field.
  """
  @impl WandererNotifier.ESI.ServiceBehaviour
  def get_system(system_id, opts \\ []) do
    cache_name =
      Keyword.get(
        opts,
        :cache_name,
        Application.get_env(:wanderer_notifier, :cache_name, :wanderer_cache)
      )

    cache_key = CacheKeys.system(system_id)

    case cache_repo(cache_name).(cache_key) do
      {:ok, data} ->
        AppLogger.api_debug("✨ ESI cache hit for solar system", system_id: system_id)
        {:ok, data}

      {:error, _} ->
        AppLogger.api_debug("🔍 ESI cache miss for solar system", system_id: system_id)

        case esi_client().get_system(system_id, Keyword.merge(retry_opts(), opts)) do
          {:ok, data} = result ->
            cache_put(cache_name, cache_key, data)
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
    with {:ok, data} when not is_nil(data) <- get_system(system_id, opts) do
      {:ok, SolarSystem.from_esi_data(data)}
    else
      _ -> {:error, :system_not_found}
    end
  end

  @doc """
  Alias for get_system to maintain backward compatibility.
  Fetches solar system info from ESI given a system_id.
  """
  @impl WandererNotifier.ESI.ServiceBehaviour
  def get_system_info(system_id, opts \\ []) do
    cache_name =
      Keyword.get(
        opts,
        :cache_name,
        Application.get_env(:wanderer_notifier, :cache_name, :wanderer_cache)
      )

    cache_key = CacheKeys.system(system_id)

    case cache_repo(cache_name).(cache_key) do
      {:ok, data} when not is_nil(data) ->
        {:ok, data}
      {:ok, nil} ->
        cache_repo().del(cache_name, cache_key)
        fetch_and_cache_system(system_id, cache_name, cache_key, opts)
      {:error, _error} ->
        fetch_and_cache_system(system_id, cache_name, cache_key, opts)
    end
  end

  defp fetch_and_cache_system(system_id, cache_name, cache_key, opts) do
    case esi_client().get_system(system_id, Keyword.merge(retry_opts(), opts)) do
      {:ok, data} when not is_nil(data) ->
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
    cache_name =
      Keyword.get(
        opts,
        :cache_name,
        Application.get_env(:wanderer_notifier, :cache_name, :wanderer_cache)
      )

    cache_key = CacheKeys.character(character_id)

    case cache_repo(cache_name).(cache_key) do
      {:ok, data} ->
        AppLogger.api_debug("✨ ESI cache hit for character", character_id: character_id)
        {:ok, data}

      {:error, _} ->
        AppLogger.api_debug("🔍 ESI cache miss for character", character_id: character_id)

        case esi_client().get_character(character_id, Keyword.merge(retry_opts(), opts)) do
          {:ok, data} = result ->
            cache_put(cache_name, cache_key, data)
            result

          error ->
            error
        end
    end
  end

  @impl WandererNotifier.ESI.ServiceBehaviour
  def get_type(type_id, opts \\ []) do
    cache_name =
      Keyword.get(
        opts,
        :cache_name,
        Application.get_env(:wanderer_notifier, :cache_name, :wanderer_cache)
      )

    cache_key = CacheKeys.type(type_id)

    case cache_repo(cache_name).(cache_key) do
      {:ok, data} ->
        AppLogger.api_debug("✨ ESI cache hit for type", type_id: type_id)
        {:ok, data}

      {:error, _} ->
        AppLogger.api_debug("🔍 ESI cache miss for type", type_id: type_id)

        case esi_client().get_type(type_id, Keyword.merge(retry_opts(), opts)) do
          {:ok, data} = result ->
            cache_put(cache_name, cache_key, data)
            result

          error ->
            error
        end
    end
  end

  @impl WandererNotifier.ESI.ServiceBehaviour
  def get_system_kills(system_id, limit, opts \\ []) do
    cache_name =
      Keyword.get(
        opts,
        :cache_name,
        Application.get_env(:wanderer_notifier, :cache_name, :wanderer_cache)
      )

    cache_key = CacheKeys.system_kills(system_id, limit)

    case cache_repo(cache_name).(cache_key) do
      {:ok, data} ->
        AppLogger.api_debug("✨ ESI cache hit for system kills", system_id: system_id)
        {:ok, data}

      {:error, _} ->
        AppLogger.api_debug("🔍 ESI cache miss for system kills", system_id: system_id)

        case esi_client().get_system_kills(system_id, limit, Keyword.merge(retry_opts(), opts)) do
          {:ok, data} = result ->
            cache_put(cache_name, cache_key, data)
            result

          error ->
            error
        end
    end
  end

  # Get retry options with default values
  defp retry_opts do
    [
      max_attempts: 3,
      base_timeout: 1000,
      max_timeout: 5000
    ]
  end

  defp esi_client do
    client = Application.get_env(:wanderer_notifier, :esi_client, WandererNotifier.ESI.Client)

    if Code.ensure_loaded?(client) do
      client
    else
      # Fallback to the real client if the module is not available
      AppLogger.api_warn(
        "ESI client module #{inspect(client)} not available, falling back to WandererNotifier.ESI.Client"
      )

      WandererNotifier.ESI.Client
    end
  end

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
  def get_universe_type(_id, _opts \\ []), do: {:error, :not_implemented}

  @impl true
  def search(_category, _search, _opts \\ []), do: {:error, :not_implemented}

  defp cache_put(cache_name, key, value) do
    repo = cache_repo()
    repo.put(cache_name, key, value)
  end
end
