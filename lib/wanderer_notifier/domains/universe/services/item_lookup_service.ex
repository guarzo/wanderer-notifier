defmodule WandererNotifier.Domains.Universe.Services.ItemLookupService do
  @moduledoc """
  High-performance item and ship name lookup service.

  This service provides fast lookups for EVE Online item names and ship types
  using cached CSV data from Wanderer SDE with ESI fallback for missing items.

  The service maintains an in-memory cache of all items and ships for O(1) lookups.

  ## Data Source

  Item data is loaded from CSV files downloaded from the Wanderer SDE repository:
  `https://github.com/wanderer-industries/wanderer-assets/tree/main/sde-files`

  ## Version Tracking

  The service tracks the SDE version and can check for updates via `check_for_updates/0`.
  """

  use GenServer
  require Logger

  alias WandererNotifier.Domains.Universe.Entities.ItemType
  alias WandererNotifier.Domains.Universe.Services.{WandererSdeService, CsvProcessor}
  alias WandererNotifier.Infrastructure.{Cache, Http}

  # Use centralized TTL functions from Cache module

  # GenServer state
  defstruct [
    :items,
    :ships,
    :stats,
    :loaded_at,
    :loading,
    :sde_version,
    :background_refresh_in_progress
  ]

  @type state :: %__MODULE__{
          items: %{integer() => ItemType.t()} | nil,
          ships: %{integer() => ItemType.t()} | nil,
          stats: map() | nil,
          loaded_at: DateTime.t() | nil,
          loading: boolean(),
          sde_version: String.t() | nil,
          background_refresh_in_progress: boolean()
        }

  # Public API

  @doc """
  Starts the ItemLookupService.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Gets an item name by type ID with fast in-memory lookup.

  Falls back to ESI if the item is not found in the local data.
  """
  @spec get_item_name(integer()) :: String.t()
  def get_item_name(type_id) when is_integer(type_id) do
    case GenServer.call(__MODULE__, {:get_item, type_id}) do
      {:ok, %ItemType{name: name}} ->
        name

      {:error, :not_found} ->
        Logger.debug("Item type_id #{type_id} not in SDE, falling back to ESI",
          category: :item_lookup
        )

        get_item_name_fallback(type_id)

      {:error, :not_loaded} ->
        Logger.warning(
          "SDE data not loaded yet, falling back to ESI for type_id #{type_id}. " <>
            "This may indicate a startup race condition.",
          category: :item_lookup
        )

        get_item_name_fallback(type_id)
    end
  end

  def get_item_name(type_id) when is_binary(type_id) do
    case Integer.parse(type_id, 10) do
      {int_id, ""} -> get_item_name(int_id)
      _ -> "Unknown Item"
    end
  end

  def get_item_name(_), do: "Unknown Item"

  @doc """
  Gets multiple item names efficiently.

  Returns a map of type_id => name.
  """
  @spec get_item_names([integer()]) :: %{String.t() => String.t()}
  def get_item_names(type_ids) when is_list(type_ids) do
    case GenServer.call(__MODULE__, {:get_items, type_ids}) do
      {:ok, found_items, missing_ids} ->
        found_map = Map.new(found_items, fn {id, item} -> {to_string(id), item.name} end)
        missing_map = get_missing_items_fallback(missing_ids)
        Map.merge(found_map, missing_map)

      {:error, :not_loaded} ->
        get_missing_items_fallback(type_ids)
    end
  end

  @doc """
  Gets a ship name by type ID.

  This is an alias for get_item_name/1 but specifically for ships.
  """
  @spec get_ship_name(integer()) :: String.t()
  def get_ship_name(type_id), do: get_item_name(type_id)

  @doc """
  Checks if a type ID represents a ship.
  """
  @spec ship?(integer()) :: boolean()
  def ship?(type_id) when is_integer(type_id) do
    case GenServer.call(__MODULE__, {:get_ship, type_id}) do
      {:ok, _ship} -> true
      _ -> false
    end
  end

  def ship?(_), do: false

  @doc """
  Gets information about loaded data.
  """
  @spec get_status() :: map()
  def get_status do
    GenServer.call(__MODULE__, :get_status)
  end

  @doc """
  Forces a reload of the CSV data.
  """
  @spec reload() :: :ok | {:error, term()}
  def reload do
    # 2 minute timeout
    GenServer.call(__MODULE__, :reload, 120_000)
  end

  @doc """
  Downloads fresh CSV files and reloads.
  """
  @spec refresh() :: :ok | {:error, term()}
  def refresh do
    # 5 minute timeout
    GenServer.call(__MODULE__, :refresh, 300_000)
  end

  @doc """
  Checks if a new SDE version is available.

  Returns:
  - `{:update_available, version}` if a newer version exists
  - `:up_to_date` if local version matches remote
  - `:check_failed` if unable to determine
  """
  @spec check_for_updates() :: {:update_available, String.t()} | :up_to_date | :check_failed
  def check_for_updates do
    WandererSdeService.check_for_updates()
  end

  @doc """
  Gets the currently loaded SDE version.
  """
  @spec get_sde_version() :: String.t() | nil
  def get_sde_version do
    GenServer.call(__MODULE__, :get_sde_version)
  end

  # GenServer callbacks

  @impl GenServer
  def init(_opts) do
    state = %__MODULE__{
      items: nil,
      ships: nil,
      stats: nil,
      loaded_at: nil,
      loading: false,
      sde_version: nil,
      background_refresh_in_progress: false
    }

    # Only load data if not in test mode
    if Application.get_env(:wanderer_notifier, :env) != :test do
      # Schedule initial load
      send(self(), :load_data)

      # Schedule periodic refresh
      Process.send_after(self(), :periodic_refresh, :timer.hours(1))
    end

    {:ok, state}
  end

  @impl GenServer
  def handle_call({:get_item, type_id}, _from, %{items: items, ships: ships} = state)
      when items != nil do
    result =
      case Map.get(items, type_id) || Map.get(ships, type_id) do
        nil -> {:error, :not_found}
        item -> {:ok, item}
      end

    {:reply, result, state}
  end

  def handle_call({:get_item, _type_id}, _from, state) do
    {:reply, {:error, :not_loaded}, state}
  end

  def handle_call({:get_ship, type_id}, _from, %{ships: ships} = state) when ships != nil do
    result =
      case Map.get(ships, type_id) do
        nil -> {:error, :not_found}
        ship -> {:ok, ship}
      end

    {:reply, result, state}
  end

  def handle_call({:get_ship, _type_id}, _from, state) do
    {:reply, {:error, :not_loaded}, state}
  end

  def handle_call({:get_items, type_ids}, _from, %{items: items, ships: ships} = state)
      when items != nil do
    {found_items, missing_ids} =
      Enum.reduce(type_ids, {[], []}, fn type_id, {found, missing} ->
        case Map.get(items, type_id) || Map.get(ships, type_id) do
          nil -> {found, [type_id | missing]}
          item -> {[{type_id, item} | found], missing}
        end
      end)

    {:reply, {:ok, found_items, missing_ids}, state}
  end

  def handle_call({:get_items, _type_ids}, _from, state) do
    {:reply, {:error, :not_loaded}, state}
  end

  def handle_call(:get_status, _from, state) do
    status = %{
      loaded: not is_nil(state.items),
      loading: state.loading,
      loaded_at: state.loaded_at,
      stats: state.stats || %{},
      sde_version: state.sde_version
    }

    {:reply, status, state}
  end

  def handle_call(:get_sde_version, _from, state) do
    {:reply, state.sde_version, state}
  end

  def handle_call(:reload, _from, state) do
    case load_csv_data() do
      {:ok, items, ships, stats} ->
        sde_version = get_local_sde_version()

        new_state = %{
          state
          | items: items,
            ships: ships,
            stats: stats,
            loaded_at: DateTime.utc_now(),
            loading: false,
            sde_version: sde_version
        }

        {:reply, :ok, new_state}

      {:error, reason} = error ->
        Logger.error("Failed to reload CSV data: #{inspect(reason)}")
        {:reply, error, %{state | loading: false}}
    end
  end

  def handle_call(:refresh, _from, state) do
    new_state = %{state | loading: true}

    case refresh_csv_data() do
      {:ok, items, ships, stats} ->
        sde_version = get_local_sde_version()

        final_state = %{
          new_state
          | items: items,
            ships: ships,
            stats: stats,
            loaded_at: DateTime.utc_now(),
            loading: false,
            sde_version: sde_version
        }

        {:reply, :ok, final_state}

      {:error, reason} = error ->
        Logger.error("Failed to refresh CSV data: #{inspect(reason)}")
        {:reply, error, %{new_state | loading: false}}
    end
  end

  @impl GenServer
  def handle_info(:load_data, state) do
    new_state = %{state | loading: true}

    case load_csv_data() do
      {:ok, items, ships, stats} ->
        sde_version = get_local_sde_version()

        Logger.info("Loaded item lookup data",
          items: map_size(items),
          ships: map_size(ships),
          sde_version: sde_version
        )

        final_state = %{
          new_state
          | items: items,
            ships: ships,
            stats: stats,
            loaded_at: DateTime.utc_now(),
            loading: false,
            sde_version: sde_version
        }

        {:noreply, final_state}

      {:error, reason} ->
        Logger.error("Failed to load CSV data on startup: #{inspect(reason)}")
        # Retry in 5 minutes
        Process.send_after(self(), :load_data, :timer.minutes(5))
        {:noreply, %{new_state | loading: false}}
    end
  end

  def handle_info(:periodic_refresh, %{background_refresh_in_progress: true} = state) do
    Logger.debug("Skipping periodic SDE update check - refresh already in progress")

    # Schedule next refresh
    Process.send_after(self(), :periodic_refresh, :timer.hours(1))

    {:noreply, state}
  end

  def handle_info(:periodic_refresh, state) do
    Logger.debug("Running periodic SDE update check")

    # Schedule next refresh
    Process.send_after(self(), :periodic_refresh, :timer.hours(1))

    # Mark refresh as in progress and check for updates in background
    # Use supervised task with try/after to ensure flag is always reset
    Task.Supervisor.start_child(WandererNotifier.TaskSupervisor, fn ->
      try do
        check_and_refresh_if_needed()
      rescue
        error ->
          Logger.error("Background SDE refresh crashed: #{inspect(error)}")
          GenServer.cast(__MODULE__, :background_refresh_complete)
      end
    end)

    {:noreply, %{state | background_refresh_in_progress: true}}
  end

  @impl GenServer
  def handle_cast({:update_data, items, ships, stats, sde_version}, state) do
    Logger.info("Updated item lookup data from periodic refresh",
      items: map_size(items),
      ships: map_size(ships),
      sde_version: sde_version
    )

    new_state = %{
      state
      | items: items,
        ships: ships,
        stats: stats,
        loaded_at: DateTime.utc_now(),
        sde_version: sde_version,
        background_refresh_in_progress: false
    }

    {:noreply, new_state}
  end

  def handle_cast(:background_refresh_complete, state) do
    {:noreply, %{state | background_refresh_in_progress: false}}
  end

  # Private functions

  defp load_csv_data do
    if WandererSdeService.csv_files_exist?() do
      load_from_csv()
    else
      Logger.info("CSV files don't exist, downloading from Wanderer SDE")
      refresh_csv_data()
    end
  end

  defp refresh_csv_data do
    with {:ok, _paths} <- WandererSdeService.download_csv_files(force_download: true),
         {:ok, items, ships, stats} <- load_from_csv() do
      {:ok, items, ships, stats}
    end
  end

  defp load_from_csv do
    file_paths = WandererSdeService.get_csv_file_paths()

    case CsvProcessor.process_csv_files(file_paths.types_path, file_paths.groups_path) do
      {:ok, %{items: items, ships: ships, stats: stats}} ->
        {:ok, items, ships, stats}

      {:error, reason} = error ->
        Logger.error("Failed to process CSV files: #{inspect(reason)}")
        error
    end
  end

  defp get_local_sde_version do
    file_info = WandererSdeService.get_csv_file_info()
    file_info[:local_version]
  end

  defp check_and_refresh_if_needed do
    case WandererSdeService.check_for_updates() do
      {:update_available, new_version} ->
        perform_periodic_refresh(new_version)

      :up_to_date ->
        Logger.debug("SDE data is up to date")
        GenServer.cast(__MODULE__, :background_refresh_complete)

      :check_failed ->
        Logger.warning("Failed to check for SDE updates")
        GenServer.cast(__MODULE__, :background_refresh_complete)
    end
  end

  defp perform_periodic_refresh(new_version) do
    Logger.info("New SDE version available: #{new_version}, refreshing data")

    case refresh_csv_data() do
      {:ok, items, ships, stats} ->
        # background_refresh_in_progress is reset in the :update_data handler
        GenServer.cast(__MODULE__, {:update_data, items, ships, stats, new_version})

      {:error, reason} ->
        Logger.warning("Periodic refresh failed: #{inspect(reason)}")
        GenServer.cast(__MODULE__, :background_refresh_complete)
    end
  end

  defp get_item_name_fallback(type_id) do
    cache_key = Cache.Keys.universe_type(type_id)

    case Cache.get(cache_key) do
      {:ok, type_data} ->
        Map.get(type_data, "name", "Unknown Item")

      {:error, _reason} ->
        # Cache miss or error, fallback to ESI
        fetch_from_esi_and_cache(type_id, cache_key)
    end
  end

  defp fetch_from_esi_and_cache(type_id, cache_key) do
    case fetch_type_from_esi(type_id) do
      {:ok, type_data} ->
        name = Map.get(type_data, "name", "Unknown Item")
        Cache.put(cache_key, type_data, Cache.ttl(:universe_type))

        Logger.debug("ESI lookup succeeded for type_id #{type_id}: #{name}",
          category: :item_lookup
        )

        name

      {:error, reason} ->
        Logger.warning(
          "ESI lookup failed for type_id #{type_id}: #{inspect(reason)}. " <>
            "Item will be sent to Janice as numeric ID which will fail.",
          category: :item_lookup
        )

        "Unknown Item"
    end
  end

  defp get_missing_items_fallback(type_ids) do
    type_ids
    |> Enum.map(fn type_id ->
      name = get_item_name_fallback(type_id)
      {to_string(type_id), name}
    end)
    |> Map.new()
  end

  defp fetch_type_from_esi(type_id) do
    url = "https://esi.evetech.net/latest/universe/types/#{type_id}/"

    case Http.esi_get(url) do
      {:ok, %{status_code: 200, body: body}} ->
        {:ok, body}

      {:ok, %{status_code: 404}} ->
        {:error, :not_found}

      {:ok, %{status_code: status}} ->
        {:error, {:http_error, status}}

      {:error, reason} ->
        {:error, reason}
    end
  end
end
