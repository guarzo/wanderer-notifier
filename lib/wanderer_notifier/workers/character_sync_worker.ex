defmodule WandererNotifier.Workers.CharacterSyncWorker do
  @moduledoc """
  GenServer that periodically syncs characters from cache to database.
  This worker ensures that character data in the cache is properly persisted
  to the database at regular intervals, preventing inconsistencies.
  """
  use GenServer
  require Logger

  # 15 minutes in milliseconds
  @sync_interval 15 * 60 * 1000

  # Start the GenServer
  def start_link(args) do
    GenServer.start_link(__MODULE__, args, name: __MODULE__)
  end

  @impl true
  def init(_args) do
    # Schedule immediate sync
    # Wait 5 seconds after startup before first sync
    schedule_sync(5000)

    # Return initial state
    {:ok, %{last_sync: nil, sync_count: 0}}
  end

  @impl true
  def handle_info(:sync, state) do
    # Perform the sync
    result = run_sync()

    # Update state with new sync time and result
    new_state = %{
      last_sync: DateTime.utc_now(),
      sync_count: state.sync_count + 1,
      last_result: result
    }

    # Schedule next sync
    schedule_sync()

    # Return updated state
    {:noreply, new_state}
  end

  # Run the character sync
  defp run_sync do
    Logger.info("[CharacterSyncWorker] Running periodic character sync...")

    # Get character counts
    cached_characters = WandererNotifier.Data.Cache.Repository.get("map:characters") || []

    # Only run if we have characters in the cache
    if length(cached_characters) > 0 do
      Logger.info(
        "[CharacterSyncWorker] Syncing #{length(cached_characters)} characters from cache to database"
      )

      # Run the sync
      case WandererNotifier.Resources.TrackedCharacter.sync_from_cache() do
        {:ok, result} ->
          Logger.info("[CharacterSyncWorker] Sync completed: #{inspect(result)}")
          {:ok, result}

        {:error, reason} ->
          Logger.error("[CharacterSyncWorker] Sync failed: #{inspect(reason)}")
          {:error, reason}
      end
    else
      Logger.info("[CharacterSyncWorker] No characters in cache, skipping sync")
      {:ok, :no_characters}
    end
  rescue
    e ->
      Logger.error("[CharacterSyncWorker] Error during sync: #{Exception.message(e)}")
      Logger.debug("[CharacterSyncWorker] #{Exception.format_stacktrace()}")
      {:error, e}
  end

  # Schedule next sync with default interval
  defp schedule_sync do
    schedule_sync(@sync_interval)
  end

  # Schedule sync with specific interval
  defp schedule_sync(interval) do
    Process.send_after(self(), :sync, interval)
  end
end
