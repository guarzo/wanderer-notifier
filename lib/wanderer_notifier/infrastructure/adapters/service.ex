defmodule WandererNotifier.Infrastructure.Adapters.ESI.Service do
  @moduledoc """
  Service for interacting with EVE Online's ESI (Swagger Interface) API.
  Provides high-level functions for common ESI operations.

  This service uses the cache facade for all cache operations.
  """

  # 30 seconds default timeout
  @default_timeout 30_000

  require Logger

  alias WandererNotifier.Infrastructure.Adapters.ESI.Entities.{
    Character,
    Corporation,
    Alliance,
    SolarSystem
  }

  alias WandererNotifier.Infrastructure.Cache
  alias WandererNotifier.Shared.Logger.Logger, as: AppLogger

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
    # Get from cache or fetch from ESI

    case Cache.get_killmail(kill_id, killmail_hash, opts) do
      {:ok, data} ->
        {:ok, data}

      {:error, :not_found} ->
        case esi_client().get_killmail(kill_id, killmail_hash, Keyword.merge(retry_opts(), opts)) do
          {:ok, data} when is_map(data) ->
            Cache.put_killmail(kill_id, killmail_hash, data, opts)
            {:ok, data}

          {:error, reason} ->
            handle_killmail_error(reason, kill_id)
        end

      {:error, reason} ->
        handle_killmail_error(reason, kill_id)
    end
  end

  @impl WandererNotifier.Infrastructure.Adapters.ESI.ServiceBehaviour
  @spec get_character_info(integer(), keyword()) :: {:ok, map()} | {:error, term()}
  def get_character_info(character_id, opts \\ []) do
    case Cache.get_character(character_id, opts) do
      {:ok, data} ->
        {:ok, data}

      {:error, :not_found} ->
        case esi_client().get_character_info(character_id, Keyword.merge(retry_opts(), opts)) do
          {:ok, data} when is_map(data) ->
            Cache.put_character(character_id, data, opts)
            {:ok, data}

          {:error, reason} ->
            {:error, reason}
        end

      {:error, reason} ->
        {:error, reason}
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

  @impl WandererNotifier.Infrastructure.Adapters.ESI.ServiceBehaviour
  @spec get_corporation_info(integer(), keyword()) :: {:ok, map()} | {:error, term()}
  def get_corporation_info(corporation_id, opts \\ []) do
    case Cache.get_corporation(corporation_id, opts) do
      {:ok, data} ->
        {:ok, data}

      {:error, :not_found} ->
        case esi_client().get_corporation_info(corporation_id, Keyword.merge(retry_opts(), opts)) do
          {:ok, data} when is_map(data) ->
            Cache.put_corporation(corporation_id, data, opts)
            {:ok, data}

          {:error, reason} ->
            {:error, reason}
        end

      {:error, reason} ->
        {:error, reason}
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

  @impl WandererNotifier.Infrastructure.Adapters.ESI.ServiceBehaviour
  @spec get_alliance_info(integer(), keyword()) :: {:ok, map()} | {:error, term()}
  def get_alliance_info(alliance_id, opts \\ []) do
    case Cache.get_alliance(alliance_id, opts) do
      {:ok, data} ->
        {:ok, data}

      {:error, :not_found} ->
        case esi_client().get_alliance_info(alliance_id, Keyword.merge(retry_opts(), opts)) do
          {:ok, data} when is_map(data) ->
            Cache.put_alliance(alliance_id, data, opts)
            {:ok, data}

          {:error, reason} ->
            {:error, reason}
        end

      {:error, reason} ->
        {:error, reason}
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
  @spec get_ship_type_name(integer(), keyword()) :: {:ok, map()} | {:error, term()}
  def get_ship_type_name(ship_type_id, opts \\ []) do
    case get_type_info(ship_type_id, opts) do
      {:ok, %{"name" => name}} ->
        {:ok, %{"name" => name}}

      {:ok, _} ->
        AppLogger.api_error("ESI Service: Missing name in type info")
        {:error, :esi_data_missing}

      error ->
        error
    end
  end

  @impl WandererNotifier.Infrastructure.Adapters.ESI.ServiceBehaviour
  @spec get_type_info(integer(), keyword()) :: {:ok, map()} | {:error, term()}
  def get_type_info(type_id, opts \\ []) do
    case Cache.get_type(type_id, opts) do
      {:ok, data} ->
        {:ok, data}

      {:error, :not_found} ->
        case esi_client().get_universe_type(type_id, Keyword.merge(retry_opts(), opts)) do
          {:ok, data} when is_map(data) ->
            Cache.put_type(type_id, data, opts)
            {:ok, data}

          {:error, reason} ->
            {:error, reason}
        end

      {:error, reason} ->
        {:error, reason}
    end
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
            Cache.put_with_ttl(cache_key, data, :timer.hours(1))
            {:ok, data}

          {:error, reason} ->
            {:error, reason}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  @impl true
  @spec get_universe_type(integer(), keyword()) :: {:ok, map()} | {:error, term()}
  def get_universe_type(type_id, opts \\ []) do
    get_type_info(type_id, opts)
  end

  @doc """
  Fetches solar system info from ESI given a solar_system_id.
  Expects the response to include a "name" field.
  """
  @impl WandererNotifier.Infrastructure.Adapters.ESI.ServiceBehaviour
  @spec get_system(integer() | String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def get_system(system_id, opts \\ []) do
    case Cache.get_system(system_id, opts) do
      {:ok, data} ->
        {:ok, data}

      {:error, :not_found} ->
        case esi_client().get_system(system_id, Keyword.merge(retry_opts(), opts)) do
          {:ok, data} when is_map(data) ->
            Cache.put_system(system_id, data, opts)
            {:ok, data}

          {:error, reason} ->
            {:error, reason}
        end

      {:error, reason} ->
        {:error, reason}
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
  Get the system information by system_id.
  Alias for get_system/2 to maintain compatibility.
  """
  @impl WandererNotifier.Infrastructure.Adapters.ESI.ServiceBehaviour
  @spec get_system_info(integer() | String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def get_system_info(system_id, opts \\ []) do
    get_system(system_id, opts)
  end

  # Additional behaviour implementations for compatibility

  @impl WandererNotifier.Infrastructure.Adapters.ESI.ServiceBehaviour
  def get_character(character_id, opts \\ []) do
    get_character_info(character_id, opts)
  end

  @impl WandererNotifier.Infrastructure.Adapters.ESI.ServiceBehaviour
  def get_type(type_id, opts \\ []) do
    get_type_info(type_id, opts)
  end

  @impl WandererNotifier.Infrastructure.Adapters.ESI.ServiceBehaviour
  def get_system_kills(system_id, limit, opts \\ []) do
    # Delegate to existing system lookup or return empty list as this is primarily for ZKillboard
    # This V2 service focuses on ESI data, not system kills tracking
    _ = {system_id, limit, opts}
    {:ok, []}
  end

  @impl WandererNotifier.Infrastructure.Adapters.ESI.ServiceBehaviour
  def search(query, categories, opts \\ []) do
    # Simple implementation that delegates to inventory type search for backwards compatibility
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
        AppLogger.api_error(
          "ESI Service: Request timed out for kill_id=#{kill_id} after #{@default_timeout}ms"
        )

      _ ->
        AppLogger.api_error(
          "ESI Service: Failed to fetch killmail data for kill_id=#{kill_id}: #{inspect(reason)}"
        )
    end

    {:error, reason}
  end
end
