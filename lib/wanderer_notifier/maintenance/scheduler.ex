defmodule WandererNotifier.Maintenance.Scheduler do
  @moduledoc """
  Schedules and coordinates periodic maintenance tasks.
  """
  require Logger
  alias WandererNotifier.Config.Timings

  @type state :: %{
          last_status_time: integer() | nil,
          last_systems_update: integer() | nil,
          last_characters_update: integer() | nil,
          last_backup_check: integer() | nil,
          service_start_time: integer(),
          processed_kill_ids: map(),
          systems_count: integer(),
          characters_count: integer()
        }

  @spec do_periodic_checks(state()) :: state()
  def do_periodic_checks(state) do
    now = :os.system_time(:second)
    Logger.debug("[Maintenance] Starting periodic checks at time #{now}")

    new_state = state
    |> maybe_send_status(now)
    |> maybe_update_systems(now)
    |> maybe_update_tracked_chars(now)
    |> maybe_check_backup_kills(now)

    # Log cache counts after maintenance
    log_cache_counts()

    new_state
  end

  @spec maybe_send_status(state(), integer()) :: state()
  defp maybe_send_status(state, now) do
    if now - (state.last_status_time || 0) > Timings.status_update_interval() do
      count = map_size(state.processed_kill_ids)
      Logger.debug("[Maintenance] Status update: Processed kills: #{count}")
      %{state | last_status_time: now}
    else
      state
    end
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

  @spec maybe_update_tracked_chars(state(), integer()) :: state()
  defp maybe_update_tracked_chars(state, now) do
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

  @spec maybe_check_backup_kills(state(), integer()) :: state()
  defp maybe_check_backup_kills(state, now) do
    uptime = now - state.service_start_time

    if uptime >= Timings.uptime_required_for_backup() and
         now - (state.last_backup_check || 0) > Timings.backup_kills_interval() do
      Logger.debug("[Maintenance] Triggering check_backup_kills")

      case WandererNotifier.Map.Client.check_backup_kills() do
        {:ok, _msg} ->
          Logger.debug("[Maintenance] check_backup_kills successful")

        {:error, err} ->
          Logger.error("[Maintenance] check_backup_kills failed: #{inspect(err)}")
      end

      %{state | last_backup_check: now}
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
    initialize_cache()

    # Run all checks in sequence
    new_state = state
    |> force_update_systems(now)
    |> force_update_tracked_chars(now)
    |> maybe_check_backup_kills(now)

    # Log cache counts after initial maintenance
    log_cache_counts()

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
end
