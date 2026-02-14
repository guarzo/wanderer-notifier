defmodule WandererNotifier.Map.MapRegistry do
  @moduledoc """
  Registry of all configured maps.

  Fetches map configurations from the Wanderer server API and stores them
  in ETS for efficient concurrent reads. Supports 300+ maps with O(1) lookup.

  ## Features

  - **API-driven**: Fetches map configs from `GET {MAP_URL}/api/v1/notifier/config`
  - **Legacy fallback**: Falls back to env vars when API is unavailable
  - **Periodic refresh**: Polls every 5 minutes for config changes
  - **Reverse indexes**: Maintains `system_id -> [map_slugs]` and `character_id -> [map_slugs]` for O(1) killmail fan-out
  - **PubSub events**: Broadcasts changes so SSE supervisor can react

  ## ETS Tables

  - `:map_registry_configs` - `{slug, MapConfig.t()}`
  - `:map_registry_system_index` - `{system_id, [map_slug]}`
  - `:map_registry_character_index` - `{character_id, [map_slug]}`
  """

  use GenServer
  require Logger

  alias WandererNotifier.Map.MapConfig
  alias WandererNotifier.Infrastructure.Http
  alias WandererNotifier.Shared.Config

  @refresh_interval :timer.minutes(5)
  @configs_table :map_registry_configs
  @system_index_table :map_registry_system_index
  @character_index_table :map_registry_character_index

  @type state :: %{
          version: integer(),
          last_fetched_at: DateTime.t() | nil,
          mode: :api | :legacy,
          refresh_timer: reference() | nil
        }

  # ============================================================================
  # Public API
  # ============================================================================

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc "Returns all map configurations."
  @spec all_maps() :: [MapConfig.t()]
  def all_maps do
    @configs_table
    |> :ets.tab2list()
    |> Enum.map(fn {_slug, config} -> config end)
  rescue
    ArgumentError -> []
  end

  @doc "Gets a map configuration by slug."
  @spec get_map(String.t()) :: {:ok, MapConfig.t()} | {:error, :not_found}
  def get_map(slug) when is_binary(slug) do
    case :ets.lookup(@configs_table, slug) do
      [{^slug, config}] -> {:ok, config}
      [] -> {:error, :not_found}
    end
  rescue
    ArgumentError -> {:error, :not_found}
  end

  @doc "Returns all map slugs."
  @spec map_slugs() :: [String.t()]
  def map_slugs do
    @configs_table
    |> :ets.tab2list()
    |> Enum.map(fn {slug, _config} -> slug end)
  rescue
    ArgumentError -> []
  end

  @doc """
  Returns map configs that track a given system ID.

  Uses the reverse index for O(1) lookup. Returns an empty list
  if no maps track the system.
  """
  @spec maps_tracking_system(String.t() | integer()) :: [MapConfig.t()]
  def maps_tracking_system(system_id) do
    system_key = to_string(system_id)

    case :ets.lookup(@system_index_table, system_key) do
      [{^system_key, slugs}] -> resolve_configs(slugs)
      [] -> []
    end
  rescue
    ArgumentError -> []
  end

  @doc "Returns the number of registered maps."
  @spec count() :: non_neg_integer()
  def count do
    :ets.info(@configs_table, :size)
  rescue
    ArgumentError -> 0
  end

  @doc "Forces an immediate refresh of map configurations."
  @spec refresh() :: :ok
  def refresh do
    GenServer.cast(__MODULE__, :refresh)
  end

  @doc """
  Adds a system to the reverse index for a specific map.

  Called by SystemHandler when a system is added to a map via SSE.
  """
  @spec index_system(String.t(), String.t() | integer()) :: :ok
  def index_system(map_slug, system_id) when is_binary(map_slug) do
    system_key = to_string(system_id)

    current_slugs =
      case :ets.lookup(@system_index_table, system_key) do
        [{^system_key, slugs}] -> slugs
        [] -> []
      end

    unless map_slug in current_slugs do
      :ets.insert(@system_index_table, {system_key, [map_slug | current_slugs]})
    end

    :ok
  rescue
    ArgumentError -> :ok
  end

  @doc """
  Removes a system from the reverse index for a specific map.

  Called by SystemHandler when a system is removed from a map via SSE.
  """
  @spec deindex_system(String.t(), String.t() | integer()) :: :ok
  def deindex_system(map_slug, system_id) when is_binary(map_slug) do
    system_key = to_string(system_id)

    case :ets.lookup(@system_index_table, system_key) do
      [{^system_key, slugs}] ->
        updated = List.delete(slugs, map_slug)

        if updated == [] do
          :ets.delete(@system_index_table, system_key)
        else
          :ets.insert(@system_index_table, {system_key, updated})
        end

      [] ->
        :ok
    end

    :ok
  rescue
    ArgumentError -> :ok
  end

  @doc """
  Returns map configs that track a given character ID.

  Uses the reverse index for O(1) lookup. Returns an empty list
  if no maps track the character.
  """
  @spec maps_tracking_character(String.t() | integer()) :: [MapConfig.t()]
  def maps_tracking_character(character_id) do
    char_key = to_string(character_id)

    case :ets.lookup(@character_index_table, char_key) do
      [{^char_key, slugs}] -> resolve_configs(slugs)
      [] -> []
    end
  rescue
    ArgumentError -> []
  end

  @doc """
  Adds a character to the reverse index for a specific map.

  Called by CharacterHandler when a character is added to a map via SSE.
  """
  @spec index_character(String.t(), String.t() | integer()) :: :ok
  def index_character(map_slug, character_id) when is_binary(map_slug) do
    char_key = to_string(character_id)

    current_slugs =
      case :ets.lookup(@character_index_table, char_key) do
        [{^char_key, slugs}] -> slugs
        [] -> []
      end

    unless map_slug in current_slugs do
      :ets.insert(@character_index_table, {char_key, [map_slug | current_slugs]})
    end

    :ok
  rescue
    ArgumentError -> :ok
  end

  @doc """
  Removes a character from the reverse index for a specific map.

  Called by CharacterHandler when a character is removed from a map via SSE.
  """
  @spec deindex_character(String.t(), String.t() | integer()) :: :ok
  def deindex_character(map_slug, character_id) when is_binary(map_slug) do
    char_key = to_string(character_id)

    case :ets.lookup(@character_index_table, char_key) do
      [{^char_key, slugs}] ->
        updated = List.delete(slugs, map_slug)

        if updated == [] do
          :ets.delete(@character_index_table, char_key)
        else
          :ets.insert(@character_index_table, {char_key, updated})
        end

      [] ->
        :ok
    end

    :ok
  rescue
    ArgumentError -> :ok
  end

  @doc "Returns the current operating mode (:api or :legacy)."
  @spec mode() :: :api | :legacy
  def mode do
    GenServer.call(__MODULE__, :mode)
  end

  # ============================================================================
  # GenServer Callbacks
  # ============================================================================

  @impl true
  def init(_opts) do
    # Create ETS tables for concurrent reads
    :ets.new(@configs_table, [:named_table, :set, :public, read_concurrency: true])
    :ets.new(@system_index_table, [:named_table, :set, :public, read_concurrency: true])
    :ets.new(@character_index_table, [:named_table, :set, :public, read_concurrency: true])

    state = %{
      version: 0,
      last_fetched_at: nil,
      mode: :legacy,
      refresh_timer: nil
    }

    {:ok, state, {:continue, :initial_fetch}}
  end

  @impl true
  def handle_continue(:initial_fetch, state) do
    new_state = do_fetch_and_update(state)
    timer = schedule_refresh()
    {:noreply, %{new_state | refresh_timer: timer}}
  end

  @impl true
  def handle_cast(:refresh, state) do
    new_state = do_fetch_and_update(state)
    {:noreply, new_state}
  end

  @impl true
  def handle_info(:refresh, state) do
    new_state = do_fetch_and_update(state)
    timer = schedule_refresh()
    {:noreply, %{new_state | refresh_timer: timer}}
  end

  @impl true
  def handle_call(:mode, _from, state) do
    {:reply, state.mode, state}
  end

  # ============================================================================
  # Private Implementation
  # ============================================================================

  defp resolve_configs(slugs) do
    Enum.flat_map(slugs, fn slug ->
      case get_map(slug) do
        {:ok, config} -> [config]
        {:error, _} -> []
      end
    end)
  end

  defp do_fetch_and_update(state) do
    case fetch_map_configs() do
      {:ok, configs, version} ->
        apply_config_changes(configs, state)

        Logger.info("Map configs loaded from API",
          count: length(configs),
          version: version
        )

        %{state | version: version, last_fetched_at: DateTime.utc_now(), mode: :api}

      {:error, reason} ->
        handle_fetch_failure(state, reason)
    end
  end

  defp handle_fetch_failure(%{mode: :api} = state, reason) do
    # Already running from API, keep existing configs on refresh failure
    Logger.warning("Map config refresh failed, keeping existing configs",
      reason: inspect(reason),
      map_count: count()
    )

    state
  end

  defp handle_fetch_failure(state, reason) do
    # First load or never connected to API - use legacy fallback
    Logger.info("Map config API unavailable, using legacy env vars",
      reason: inspect(reason)
    )

    legacy_config = MapConfig.from_env()
    apply_config_changes([legacy_config], state)
    %{state | last_fetched_at: DateTime.utc_now(), mode: :legacy}
  end

  defp fetch_map_configs do
    base_url = Config.map_url_safe()
    api_key = Config.map_api_key()

    case base_url do
      {:ok, url} ->
        do_fetch_from_api(url, api_key)

      {:error, _} ->
        {:error, :map_url_not_configured}
    end
  rescue
    e -> {:error, {:fetch_exception, Exception.message(e)}}
  end

  defp do_fetch_from_api(base_url, api_key) do
    url = "#{base_url}/api/v1/notifier/config"

    headers = [
      {"Authorization", "Bearer #{api_key}"},
      {"Content-Type", "application/json"},
      {"Accept", "application/json"}
    ]

    case Http.request(:get, url, nil, headers, service: :map) do
      {:ok, %{status_code: 200, body: body}} ->
        parse_api_response(body)

      {:ok, %{status_code: 404}} ->
        {:error, :endpoint_not_found}

      {:ok, %{status_code: status}} ->
        {:error, {:api_error, status}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp parse_api_response(%{"data" => %{"maps" => maps, "version" => version}})
       when is_list(maps) do
    configs =
      maps
      |> Enum.map(&MapConfig.from_api/1)
      |> Enum.flat_map(fn
        {:ok, config} ->
          [config]

        {:error, reason} ->
          Logger.warning("Skipping invalid map config", reason: inspect(reason))
          []
      end)

    {:ok, configs, version}
  end

  defp parse_api_response(%{"data" => %{"maps" => maps}}) when is_list(maps) do
    parse_api_response(%{"data" => %{"maps" => maps, "version" => 0}})
  end

  defp parse_api_response(_body) do
    {:error, :invalid_response_format}
  end

  defp apply_config_changes(new_configs, _state) do
    new_slugs = MapSet.new(new_configs, & &1.slug)
    old_slugs = MapSet.new(map_slugs())

    # Detect changes
    added = MapSet.difference(new_slugs, old_slugs)
    removed = MapSet.difference(old_slugs, new_slugs)

    # Remove old configs
    Enum.each(removed, fn slug ->
      :ets.delete(@configs_table, slug)
      Logger.info("Map removed from registry", map_slug: slug)
    end)

    # Insert/update configs
    Enum.each(new_configs, fn config ->
      :ets.insert(@configs_table, {config.slug, config})
    end)

    # Broadcast changes if there were additions or removals
    if MapSet.size(added) > 0 or MapSet.size(removed) > 0 do
      broadcast_changes(added, removed)
    end

    :ok
  end

  defp broadcast_changes(added, removed) do
    changes = %{
      added: MapSet.to_list(added),
      removed: MapSet.to_list(removed)
    }

    Phoenix.PubSub.broadcast(
      WandererNotifier.PubSub,
      "map_registry",
      {:maps_updated, changes}
    )

    # Notify SSESupervisor to start/stop SSE clients for changed maps
    notify_sse_supervisor(changes)
  rescue
    # PubSub may not be started yet during initialization
    _ -> :ok
  end

  defp notify_sse_supervisor(changes) do
    WandererNotifier.Map.SSESupervisor.handle_maps_updated(changes)
  rescue
    # SSESupervisor may not be started yet during initialization
    _ -> :ok
  end

  defp schedule_refresh do
    Process.send_after(self(), :refresh, @refresh_interval)
  end
end
