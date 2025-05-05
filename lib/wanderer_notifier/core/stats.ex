defmodule WandererNotifier.Core.Stats do
  @moduledoc """
  Statistics tracking for WandererNotifier.
  Maintains counters and metrics for application monitoring.
  Also tracks first notification flags for feature gating.
  """
  use GenServer
  alias WandererNotifier.Logger.Logger, as: AppLogger
  require Logger

  # Client API

  @doc """
  Starts the Stats GenServer.
  """
  def start_link(opts \\ []) do
    AppLogger.startup_debug("Starting Stats tracking service...")
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Increments the count for a specific notification type.
  """
  def increment(type) do
    GenServer.cast(__MODULE__, {:increment, type})
  end

  @doc """
  Alias for increment/1, provided for backward compatibility.
  Will be deprecated in the future.
  """
  def update(type) do
    increment(type)
  end

  @doc """
  Returns the current statistics.
  """
  def get_stats do
    GenServer.call(__MODULE__, :get_stats)
  end

  @doc """
  Updates the websocket status.
  """
  def update_websocket(status) do
    GenServer.cast(__MODULE__, {:update_websocket, status})
  end

  @doc """
  Checks if this is the first notification of a specific type since application startup.
  Returns true if it's the first notification, false otherwise.

  ## Parameters
    - type: The notification type (:kill, :character, or :system)
  """
  def is_first_notification?(type) when type in [:kill, :character, :system] do
    GenServer.call(__MODULE__, {:is_first_notification, type})
  end

  @doc """
  Marks that the first notification of a specific type has been sent.
  This updates application state so future checks will return false.

  ## Parameters
    - type: The notification type (:kill, :character, or :system)
  """
  def mark_notification_sent(type) when type in [:kill, :character, :system] do
    GenServer.cast(__MODULE__, {:mark_notification_sent, type})
  end

  @doc """
  Prints a summary of current statistics to the log.
  """
  def print_summary do
    stats = get_stats()

    # Format uptime
    uptime = stats.uptime

    # Format notification counts
    notifications = stats.notifications
    total_notifications = notifications.total
    _kills_notified = notifications.kills
    systems_notified = notifications.systems
    characters_notified = notifications.characters

    # Format processing stats
    processing = stats.processing
    kills_processed = processing.kills_processed
    kills_notified = processing.kills_notified

    # Format websocket status
    websocket = stats.websocket
    connected = if websocket.connected, do: "connected", else: "disconnected"

    last_message =
      case websocket.last_message do
        nil -> "never"
        dt -> "#{DateTime.diff(DateTime.utc_now(), dt)}s ago"
      end

    # Log the summary
    AppLogger.kill_info("📊 Stats Summary:
    Uptime: #{uptime}
    Notifications: #{total_notifications} total (#{kills_notified} kills, #{systems_notified} systems, #{characters_notified} characters)
    Processing: #{kills_processed} kills processed, #{kills_notified} kills notified
    WebSocket: #{connected}, last message #{last_message}")
  end

  @doc """
  Sets the tracked count for a specific type (:systems or :characters).
  """
  def set_tracked_count(type, count) when type in [:systems, :characters] and is_integer(count) do
    GenServer.cast(__MODULE__, {:set_tracked_count, type, count})
  end

  # Server Implementation

  @impl true
  def init(_opts) do
    AppLogger.startup_debug("Initializing stats tracking service...")
    # Initialize the state with default values
    {:ok,
     %{
       websocket: %{
         connected: false,
         connecting: false,
         last_message: nil,
         startup_time: nil,
         reconnects: 0,
         url: nil,
         last_disconnect: nil
       },
       notifications: %{
         total: 0,
         kills: 0,
         systems: 0,
         characters: 0
       },
       processing: %{
         kills_processed: 0,
         kills_notified: 0
       },
       first_notifications: %{
         kill: true,
         character: true,
         system: true
       }
     }}
  end

  @impl true
  def handle_cast({:increment, type}, state) do
    case type do
      :kill_processed ->
        processing = Map.update(state.processing, :kills_processed, 1, &(&1 + 1))
        {:noreply, %{state | processing: processing}}

      :kill_notified ->
        processing = Map.update(state.processing, :kills_notified, 1, &(&1 + 1))
        {:noreply, %{state | processing: processing}}

      _ ->
        notifications = Map.update(state.notifications, type, 1, &(&1 + 1))
        notifications = Map.update(notifications, :total, 1, &(&1 + 1))
        {:noreply, %{state | notifications: notifications}}
    end
  end

  @impl true
  def handle_cast({:update_websocket, status}, state) do
    # Merge the new status with existing websocket state to preserve fields
    # Convert any DateTime fields to ensure proper comparison
    normalized_status = normalize_datetime_fields(status)
    updated_websocket = Map.merge(state.websocket, normalized_status)

    # Log the update for debugging
    AppLogger.websocket_debug("Updated websocket status",
      old_status: state.websocket,
      new_status: updated_websocket
    )

    {:noreply, %{state | websocket: updated_websocket}}
  end

  @impl true
  def handle_cast({:mark_notification_sent, type}, state) do
    # Update the first_notifications map to mark this type as sent
    first_notifications = Map.put(state.first_notifications, type, false)
    AppLogger.config_debug("Marked #{type} notification as sent - no longer first notification")

    {:noreply, %{state | first_notifications: first_notifications}}
  end

  @impl true
  def handle_cast({:set_tracked_count, type, count}, state) do
    key =
      case type do
        :systems -> :systems_count
        :characters -> :characters_count
      end
    {:noreply, Map.put(state, key, count)}
  end

  @impl true
  def handle_cast({:update_counts, systems_count, characters_count, notifications_count}, state) do
    # Update only the provided counts, leave others unchanged
    state =
      state
      |> maybe_update(:systems_count, systems_count)
      |> maybe_update(:characters_count, characters_count)
      |> maybe_update_notifications(notifications_count)

    {:noreply, state}
  end

  defp maybe_update(state, _key, nil), do: state
  defp maybe_update(state, key, value), do: Map.put(state, key, value)

  defp maybe_update_notifications(state, nil), do: state
  defp maybe_update_notifications(state, count) do
    notifications = Map.put(state.notifications, :total, count)
    %{state | notifications: notifications}
  end

  @impl true
  def handle_call(:get_stats, _from, state) do
    uptime_seconds =
      case state.websocket.startup_time do
        nil -> 0
        startup_time -> DateTime.diff(DateTime.utc_now(), startup_time)
      end

    stats = %{
      uptime: format_uptime(uptime_seconds),
      uptime_seconds: uptime_seconds,
      startup_time: state.websocket.startup_time,
      notifications: state.notifications,
      websocket: state.websocket,
      first_notifications: Map.get(state, :first_notifications, %{}),
      processing: state.processing,
      systems_count: Map.get(state, :systems_count, 0),
      characters_count: Map.get(state, :characters_count, 0)
    }

    {:reply, stats, state}
  end

  @impl true
  def handle_call({:is_first_notification, type}, _from, state) do
    # Look up the first notification status from the state
    is_first = Map.get(state.first_notifications, type, true)

    {:reply, is_first, state}
  end

  # Helper functions

  defp format_uptime(seconds) do
    days = div(seconds, 86_400)
    seconds = rem(seconds, 86_400)
    hours = div(seconds, 3600)
    seconds = rem(seconds, 3600)
    minutes = div(seconds, 60)
    seconds = rem(seconds, 60)

    cond do
      days > 0 -> "#{days}d #{hours}h #{minutes}m #{seconds}s"
      hours > 0 -> "#{hours}h #{minutes}m #{seconds}s"
      minutes > 0 -> "#{minutes}m #{seconds}s"
      true -> "#{seconds}s"
    end
  end

  # Helper to normalize DateTime fields in the status map
  defp normalize_datetime_fields(status) do
    status
    |> Enum.map(fn
      {key, %DateTime{} = dt} ->
        {key, dt}

      {key, nil} ->
        {key, nil}

      {key, val} when is_integer(val) and key in [:startup_time] ->
        {key, DateTime.from_unix!(val)}

      {key, val} ->
        {key, val}
    end)
    |> Map.new()
  end
end
