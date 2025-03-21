defmodule WandererNotifier.Helpers.DeduplicationHelper do
  @moduledoc """
  Helper module for preventing duplicate notifications in WandererNotifier.
  Uses ETS for fast lookups and automatic expiration of entries.
  """
  use GenServer
  require Logger

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
  def check_and_mark_system(system_id) when is_binary(system_id) or is_integer(system_id) do
    system_id_str = to_string(system_id)
    key = "system:#{system_id_str}"

    # Log more details about the system deduplication check
    Logger.debug("[DeduplicationHelper] Checking system deduplication for ID: #{system_id_str}")

    check_and_mark(key)
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
    Logger.debug(
      "[DeduplicationHelper] Checking character deduplication for ID: #{character_id_str}"
    )

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
    Logger.info("[DeduplicationHelper] Checking kill deduplication for ID: #{kill_id_str}")

    # Check in the ETS table
    result = check_and_mark(key)

    # Log the result with more details
    case result do
      {:ok, :new} ->
        Logger.info("[DeduplicationHelper] Kill #{kill_id_str} is new, notification allowed")

      {:ok, :duplicate} ->
        Logger.info(
          "[DeduplicationHelper] Kill #{kill_id_str} is a duplicate, notification skipped"
        )

      _ ->
        Logger.warning(
          "[DeduplicationHelper] Unexpected result for kill check: #{inspect(result)}"
        )
    end

    result
  end

  @doc """
  Checks if a generic notification with the given key was recently sent.
  If not, marks the key as notified.

  Returns:
  - `{:ok, :new}` if this is a new notification (not a duplicate)
  - `{:ok, :duplicate}` if this is a duplicate notification
  """
  def check_and_mark(key) do
    try do
      # Make sure the table exists before trying to use it
      if :ets.info(@dedup_table) == :undefined do
        Logger.error("[DeduplicationHelper] ETS table doesn't exist, creating it now")
        create_dedup_table()
      end

      # Look up the key in the ETS table
      case :ets.lookup(@dedup_table, key) do
        [] ->
          # Not in table, insert and return :new
          :ets.insert(@dedup_table, {key, :os.system_time(:millisecond)})
          # Schedule deletion after TTL
          Process.send_after(__MODULE__, {:clear_dedup_key, key}, @dedup_ttl)
          {:ok, :new}

        [{^key, _timestamp}] ->
          # Already in table, return :duplicate
          {:ok, :duplicate}
      end
    rescue
      e ->
        Logger.error("[DeduplicationHelper] Error in deduplication check: #{inspect(e)}")

        Logger.error(
          "[DeduplicationHelper] Stacktrace: #{inspect(Process.info(self(), :current_stacktrace))}"
        )

        # If there's an error, allow the notification to proceed
        {:ok, :new}
    end
  end

  @doc """
  Handles the expiration message for a deduplication key.
  """
  def handle_clear_key(key) do
    Logger.debug("[DeduplicationHelper] Clearing expired deduplication key: #{key}")
    :ets.delete(@dedup_table, key)
    :ok
  end

  @doc """
  Clears all deduplication entries (mainly for testing).
  """
  def clear_all do
    if :ets.info(@dedup_table) != :undefined do
      :ets.delete_all_objects(@dedup_table)
      Logger.info("[DeduplicationHelper] Cleared all deduplication entries")
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

    Logger.info("[DeduplicationHelper] Created new deduplication table")
  end

  # Server callbacks

  @impl true
  def init(_opts) do
    Logger.info("[DeduplicationHelper] Initializing notification deduplication table")

    # Create ETS table for deduplication if it doesn't already exist
    if :ets.info(@dedup_table) == :undefined do
      create_dedup_table()
    else
      Logger.debug("[DeduplicationHelper] Deduplication table already exists")
    end

    {:ok, %{}}
  end

  @impl true
  def handle_info({:clear_dedup_key, key}, state) do
    handle_clear_key(key)
    {:noreply, state}
  end
end
