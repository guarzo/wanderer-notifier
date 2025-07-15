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
  alias WandererNotifier.Cache.Facade
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

  @impl WandererNotifier.ESI.ServiceBehaviour
  @spec get_killmail(integer(), String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def get_killmail(kill_id, killmail_hash, opts \\ []) do
    case Facade.get_killmail(kill_id, killmail_hash, opts) do
      {:ok, data} when is_map(data) and map_size(data) > 0 ->
        {:ok, data}

      {:error, :not_found} ->
        fetch_from_esi(kill_id, killmail_hash, opts)

      error ->
        error
    end
  end

  defp fetch_from_esi(kill_id, killmail_hash, opts) do
    # Get the raw response from the client
    response =
      esi_client().get_killmail(kill_id, killmail_hash, Keyword.merge(retry_opts(), opts))

    case response do
      {:ok, data} when is_map(data) and map_size(data) > 0 ->
        # Cache the data using the facade
        Facade.put_killmail(kill_id, killmail_hash, data, opts)
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
  @spec get_character_info(integer(), keyword()) :: {:ok, map()} | {:error, term()}
  def get_character_info(character_id, opts \\ []) do
    case Facade.get_character(character_id, opts) do
      {:ok, data} ->
        {:ok, data}

      {:error, :not_found} ->
        case esi_client().get_character_info(character_id, Keyword.merge(retry_opts(), opts)) do
          {:ok, data} when is_map(data) and map_size(data) > 0 ->
            Facade.put_character(character_id, data, opts)
            {:ok, data}

          error ->
            error
        end

      error ->
        error
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
  @spec get_corporation_info(integer(), keyword()) :: {:ok, map()} | {:error, term()}
  def get_corporation_info(corporation_id, opts \\ []) do
    case Facade.get_corporation(corporation_id, opts) do
      {:ok, data} ->
        {:ok, data}

      {:error, :not_found} ->
        case esi_client().get_corporation_info(corporation_id, Keyword.merge(retry_opts(), opts)) do
          {:ok, data} when is_map(data) and map_size(data) > 0 ->
            Facade.put_corporation(corporation_id, data, opts)
            {:ok, data}

          error ->
            error
        end

      error ->
        error
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
  @spec get_alliance_info(integer(), keyword()) :: {:ok, map()} | {:error, term()}
  def get_alliance_info(alliance_id, opts \\ []) do
    case Facade.get_alliance(alliance_id, opts) do
      {:ok, data} ->
        {:ok, data}

      {:error, :not_found} ->
        case esi_client().get_alliance_info(alliance_id, Keyword.merge(retry_opts(), opts)) do
          {:ok, data} when is_map(data) and map_size(data) > 0 ->
            Facade.put_alliance(alliance_id, data, opts)
            {:ok, data}

          error ->
            error
        end

      error ->
        error
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

  @impl WandererNotifier.ESI.ServiceBehaviour
  @spec get_type_info(integer(), keyword()) :: {:ok, map()} | {:error, term()}
  def get_type_info(type_id, opts \\ []) do
    case Facade.get_type(type_id, opts) do
      {:ok, data} ->
        {:ok, data}

      {:error, :not_found} ->
        case esi_client().get_universe_type(type_id, Keyword.merge(retry_opts(), opts)) do
          {:ok, data} when is_map(data) and map_size(data) > 0 ->
            Facade.put_type(type_id, data, opts)
            {:ok, data}

          error ->
            error
        end

      error ->
        error
    end
  end

  @doc """
  Searches for inventory types using the ESI /search/ endpoint.
  """
  def search_inventory_type(query, strict \\ true, opts \\ []) do
    custom_key = CacheKeys.search_inventory_type(query, strict)

    case Facade.get_custom(custom_key, opts) do
      {:ok, data} ->
        {:ok, data}

      {:error, :not_found} ->
        case esi_client().search_inventory_type(query, Keyword.merge(retry_opts(), opts)) do
          {:ok, data} ->
            Facade.put_custom(custom_key, data, opts)
            {:ok, data}

          error ->
            error
        end

      error ->
        error
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
  @impl WandererNotifier.ESI.ServiceBehaviour
  @spec get_system(integer() | String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def get_system(system_id, opts \\ []) do
    case Facade.get_system(system_id, opts) do
      {:ok, data} ->
        {:ok, data}

      {:error, :not_found} ->
        case esi_client().get_system(system_id, Keyword.merge(retry_opts(), opts)) do
          {:ok, data} when is_map(data) and map_size(data) > 0 ->
            Facade.put_system(system_id, data, opts)
            {:ok, data}

          error ->
            error
        end

      error ->
        error
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
  @spec get_system_info(integer(), keyword()) :: {:ok, map()} | {:error, term()}
  def get_system_info(system_id, opts \\ []) do
    get_system(system_id, opts)
  end


  @impl WandererNotifier.ESI.ServiceBehaviour
  @spec get_character(integer(), keyword()) :: {:ok, map()} | {:error, term()}
  def get_character(character_id, opts \\ []) do
    get_character_info(character_id, opts)
  end

  @impl WandererNotifier.ESI.ServiceBehaviour
  @spec get_type(integer(), keyword()) :: {:ok, map()} | {:error, term()}
  def get_type(type_id, opts \\ []) do
    get_type_info(type_id, opts)
  end

  @impl WandererNotifier.ESI.ServiceBehaviour
  @spec get_system_kills(integer(), integer(), keyword()) :: {:ok, list(map())} | {:error, term()}
  def get_system_kills(system_id, limit, opts \\ []) do
    custom_key = CacheKeys.system_kills(system_id, limit)

    case Facade.get_custom(custom_key, opts) do
      {:ok, data} ->
        {:ok, data}

      {:error, :not_found} ->
        case esi_client().get_system_kills(system_id, limit, Keyword.merge(retry_opts(), opts)) do
          {:ok, data} ->
            Facade.put_custom(custom_key, data, opts)
            {:ok, data}

          error ->
            error
        end

      error ->
        error
    end
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

  @impl true
  @spec search(String.t(), list(String.t()), keyword()) :: {:ok, map()} | {:error, term()}
  def search(_category, _search, _opts \\ []), do: {:error, :not_implemented}

end
