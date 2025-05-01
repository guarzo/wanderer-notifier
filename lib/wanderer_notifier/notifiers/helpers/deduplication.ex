defmodule WandererNotifier.Notifiers.Helpers.Deduplication do
  @moduledoc """
  Helper module for preventing duplicate notifications in WandererNotifier.
  Uses ETS for fast lookups and automatic expiration of entries.
  """
  use GenServer
  require Logger
  alias WandererNotifier.Logger.Logger, as: AppLogger

  # TTL for deduplication entries - 12 hours by default for better protection against restarts
  @dedup_ttl 12 * 60 * 60 * 1000

  # ETS table name for deduplication
  @dedup_table :notification_deduplication

  # Client API

  @doc """
  Starts the deduplication helper GenServer.
  """
  def start_link(_opts) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  @doc """
  Checks if a notification for a system with the given ID was recently sent.
  If not, marks the system as notified.

  Returns:
  - `{:ok, :new}` if this is a new notification (not a duplicate)
  - `{:ok, :duplicate}` if this is a duplicate notification
  """
  def check_system_notification(system_id) do
    GenServer.call(__MODULE__, {:check_system, system_id})
  end

  @doc """
  Checks if a notification for a character with the given ID was recently sent.
  If not, marks the character as notified.

  Returns:
  - `{:ok, :new}` if this is a new notification (not a duplicate)
  - `{:ok, :duplicate}` if this is a duplicate notification
  """
  def check_and_mark_character(character_id)
      when is_binary(character_id) or is_integer(character_id) do
    character_id_str = to_string(character_id)
    key = "character:#{character_id_str}"

    # Log more details about the character deduplication check
    AppLogger.cache_debug("Checking character deduplication", character_id: character_id_str)

    check_and_mark(key)
  end

  @doc """
  Checks if a notification for a system with the given ID was recently sent.
  If not, marks the system as notified.

  Returns:
  - `{:ok, :new}` if this is a new notification (not a duplicate)
  - `{:ok, :duplicate}` if this is a duplicate notification
  """
  def check_and_mark_system(system_id) when is_binary(system_id) or is_integer(system_id) do
    system_id_str = to_string(system_id)
    key = "system:#{system_id_str}"

    # Log more details about the system deduplication check
    AppLogger.cache_debug("Checking system deduplication", system_id: system_id_str)

    check_and_mark(key)
  end

  @doc """
  Checks if a notification for a kill with the given ID was recently sent.
  If not, marks the kill as notified.

  Returns:
  - `{:ok, :new}` if this is a new notification (not a duplicate)
  - `{:ok, :duplicate}` if this is a duplicate notification
  """
  def check_and_mark_kill(kill_id) when is_binary(kill_id) or is_integer(kill_id) do
    kill_id_str = to_string(kill_id)
    key = "kill:#{kill_id_str}"

    # Log detailed debugging information for kill notifications
    AppLogger.kill_info("Checking kill deduplication", kill_id: kill_id_str)

    # Check in the ETS table
    result = check_and_mark(key)

    # Log the result with more details
    case result do
      {:ok, :new} ->
        AppLogger.kill_info("Kill is new, notification allowed", kill_id: kill_id_str)

      {:ok, :duplicate} ->
        AppLogger.kill_debug("Kill is a duplicate, notification skipped", kill_id: kill_id_str)

      _ ->
        AppLogger.kill_warn("Unexpected result for kill check", result: inspect(result))
    end

    result
  end

  @doc """
  Checks if a generic notification with the given key was recently sent.
  If not, marks the key as notified.

  Returns:
  - `{:ok, :new}` if this is a new notification (not seen before)
  - `{:ok, :duplicate}` if this is a duplicate notification (already seen)
  """
  def check_and_mark(key) do
    # Make sure the table exists before trying to use it
    if :ets.info(@dedup_table) == :undefined do
      AppLogger.cache_error("ETS table doesn't exist, creating it now")
      create_dedup_table()
    end

    AppLogger.cache_debug("[Deduplication] Checking key", key: key)

    # Look up the key in the ETS table
    case :ets.lookup(@dedup_table, key) do
      [] ->
        # Not in table, insert and return :new
        AppLogger.cache_info("[Deduplication] Key not found, marking as new", key: key)
        :ets.insert(@dedup_table, {key, :os.system_time(:millisecond)})
        # Schedule deletion after TTL
        if Process.whereis(__MODULE__) do
          Process.send_after(__MODULE__, {:clear_dedup_key, key}, @dedup_ttl)
        end

        {:ok, :new}

      [{^key, timestamp}] ->
        # Already in table, return :duplicate
        age = :os.system_time(:millisecond) - timestamp

        AppLogger.cache_info("[Deduplication] Key found (duplicate)",
          key: key,
          age_ms: age
        )

        {:ok, :duplicate}
    end
  rescue
    e ->
      AppLogger.cache_error("Error in deduplication check",
        error: inspect(e),
        key: key,
        stacktrace: inspect(Process.info(self(), :current_stacktrace))
      )

      # If there's an error, allow the notification to proceed
      {:ok, :new}
  end

  @doc """
  Handles the expiration message for a deduplication key.
  """
  def handle_clear_key(key) do
    AppLogger.cache_debug("Clearing expired deduplication key", key: key)
    :ets.delete(@dedup_table, key)
    :ok
  end

  @doc """
  Clears all deduplication entries (mainly for testing).
  """
  def clear_all do
    if :ets.info(@dedup_table) != :undefined do
      :ets.delete_all_objects(@dedup_table)
      AppLogger.cache_info("Cleared all deduplication entries")
    end

    :ok
  end

  # Create the ETS table if it doesn't exist
  defp create_dedup_table do
    :ets.new(@dedup_table, [
      :named_table,
      :set,
      :public,
      read_concurrency: true,
      write_concurrency: true
    ])

    AppLogger.cache_info("Created new deduplication table")
  end

  # Server callbacks

  @impl true
  def init(_) do
    # Create the ETS table on startup
    create_dedup_table()
    {:ok, %{}}
  end

  @impl true
  def handle_call({:check_system, system_id}, _from, state) do
    result = check_and_mark_system(system_id)
    {:reply, result, state}
  end

  @impl true
  def handle_info({:clear_dedup_key, key}, state) do
    handle_clear_key(key)
    {:noreply, state}
  end

  @impl true
  def handle_info(_, state), do: {:noreply, state}
end
