defmodule WandererNotifier.Maintenance.Scheduler do
  @moduledoc """
  Schedules and coordinates periodic maintenance tasks.
  """
  require Logger
  use GenServer
  alias WandererNotifier.Config.Timings

  @type state :: %{
          service_start_time: integer(),
          last_systems_update: integer() | nil,
          last_characters_update: integer() | nil,
          systems_count: integer(),
          characters_count: integer()
        }

  @spec tick(state()) :: state()
  def tick(state) do
    now = :os.system_time(:second)

    state
    |> maybe_update_systems(now)
    |> maybe_update_characters(now)
  end

  @spec maybe_update_systems(state(), integer()) :: state()
  defp maybe_update_systems(state, now) do
    if now - (state.last_systems_update || 0) > Timings.systems_update_interval() do
      Logger.debug("[Maintenance] Triggering update_systems")

      case WandererNotifier.Map.Client.update_systems() do
        {:ok, new_systems} ->
          Logger.debug(
            "[Maintenance] update_systems successful: found #{length(new_systems)} wormhole systems (previously had #{state.systems_count})"
          )

          # Update only the count in the state
          %{state | last_systems_update: now, systems_count: length(new_systems)}

        {:error, err} ->
          Logger.error("[Maintenance] update_systems failed: #{inspect(err)}")
          %{state | last_systems_update: now}
      end
    else
      state
    end
  end

  @spec maybe_update_characters(state(), integer()) :: state()
  defp maybe_update_characters(state, now) do
    if now - (state.last_characters_update || 0) > Timings.character_update_interval() do
      Logger.debug("[Maintenance] Triggering update_tracked_characters")

      case WandererNotifier.Map.Client.update_tracked_characters() do
        {:ok, chars} ->
          Logger.debug(
            "[Maintenance] update_tracked_characters successful: found #{length(chars)} characters (previously had #{state.characters_count})"
          )

          # Update only the count in the state
          %{state | last_characters_update: now, characters_count: length(chars)}

        {:error, err} ->
          Logger.error("[Maintenance] update_tracked_characters failed: #{inspect(err)}")
          %{state | last_characters_update: now}
      end
    else
      state
    end
  end

  @spec do_initial_checks(state()) :: state()
  def do_initial_checks(state) do
    now = :os.system_time(:second)
    Logger.info("[Maintenance] Starting initial checks at time #{now}")

    # Instead of clearing the cache, ensure it's initialized with empty arrays if not present
    Logger.debug("[Maintenance] Ensuring systems and characters cache is initialized")

    # Wrap initialization in a try/rescue to prevent crashes
    try do
      initialize_cache()
    rescue
      e ->
        Logger.error("[Maintenance] Error initializing cache: #{inspect(e)}")
        Logger.error("[Maintenance] Stacktrace: #{inspect(Process.info(self(), :current_stacktrace))}")
    end

    # Run all checks in sequence with error handling for each step
    new_state = state

    # Update systems with error handling
    new_state = try do
      force_update_systems(new_state, now)
    rescue
      e ->
        Logger.error("[Maintenance] Error updating systems: #{inspect(e)}")
        Logger.error("[Maintenance] Stacktrace: #{inspect(Process.info(self(), :current_stacktrace))}")
        %{new_state | last_systems_update: now}
    end

    # Update characters with error handling
    new_state = try do
      force_update_tracked_chars(new_state, now)
    rescue
      e ->
        Logger.error("[Maintenance] Error updating characters: #{inspect(e)}")
        Logger.error("[Maintenance] Stacktrace: #{inspect(Process.info(self(), :current_stacktrace))}")
        %{new_state | last_characters_update: now}
    end

    # Log cache counts after initial maintenance
    try do
      log_cache_counts()
    rescue
      e ->
        Logger.error("[Maintenance] Error logging cache counts: #{inspect(e)}")
    end

    new_state
  end

  # Initialize cache with empty arrays if keys don't exist
  defp initialize_cache do
    alias WandererNotifier.Cache.Repository, as: CacheRepo

    # Initialize systems cache if it doesn't exist or is empty
    systems = CacheRepo.get("map:systems")
    if systems == nil or (is_list(systems) and length(systems) == 0) do
      Logger.debug("[Maintenance] Initializing empty systems cache")
      CacheRepo.put("map:systems", [])
    else
      Logger.debug("[Maintenance] Systems cache already exists with #{length(systems)} systems")
    end

    # Initialize characters cache if it doesn't exist or is empty
    characters = CacheRepo.get("map:characters")
    if characters == nil or (is_list(characters) and length(characters) == 0) do
      Logger.debug("[Maintenance] Initializing empty characters cache")
      CacheRepo.put("map:characters", [])
    else
      Logger.debug("[Maintenance] Characters cache already exists with #{length(characters)} characters")
    end
  end

  # Force update systems regardless of last update time
  @spec force_update_systems(state(), integer()) :: state()
  defp force_update_systems(state, now) do
    Logger.debug("[Maintenance] Forcing update_systems")

    case WandererNotifier.Map.Client.update_systems() do
      {:ok, new_systems} ->
        Logger.debug(
          "[Maintenance] update_systems successful: found #{length(new_systems)} wormhole systems"
        )

        # Update the count in the state
        %{state | last_systems_update: now, systems_count: length(new_systems)}

      {:error, err} ->
        Logger.error("[Maintenance] update_systems failed: #{inspect(err)}")
        %{state | last_systems_update: now}
    end
  end

  # Force update tracked characters regardless of last update time
  @spec force_update_tracked_chars(state(), integer()) :: state()
  defp force_update_tracked_chars(state, now) do
    Logger.debug("[Maintenance] Forcing update_tracked_characters")

    case WandererNotifier.Map.Client.update_tracked_characters() do
      {:ok, chars} ->
        Logger.debug(
          "[Maintenance] update_tracked_characters successful: found #{length(chars)} characters"
        )

        # Update the count in the state
        %{state | last_characters_update: now, characters_count: length(chars)}

      {:error, err} ->
        Logger.error("[Maintenance] update_tracked_characters failed: #{inspect(err)}")
        %{state | last_characters_update: now}
    end
  end

  # Log the counts of systems and characters in the cache
  defp log_cache_counts do
    alias WandererNotifier.Cache.Repository, as: CacheRepo

    # Get systems count
    systems = CacheRepo.get("map:systems") || []
    Logger.debug("[Maintenance] Cache count - Systems: #{length(systems)}")

    # Get characters count
    characters = CacheRepo.get("map:characters") || []
    Logger.debug("[Maintenance] Cache count - Characters: #{length(characters)}")
  end

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    # Initialize state
    state = %{
      service_start_time: :os.system_time(:second),
      last_systems_update: nil,
      last_characters_update: nil,
      systems_count: 0,
      characters_count: 0
    }

    {:ok, state}
  end
end
