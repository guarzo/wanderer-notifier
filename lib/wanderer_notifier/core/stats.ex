defmodule WandererNotifier.Core.Stats do
  @moduledoc """
  Statistics tracking for WandererNotifier.
  Maintains counters and metrics for application monitoring.
  Also tracks first notification flags for feature gating.
  """
  use GenServer
  require Logger
  alias WandererNotifier.Logger.Logger, as: AppLogger

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
       first_notifications: %{
         kill: true,
         character: true,
         system: true
       }
     }}
  end

  @impl true
  def handle_cast({:increment, type}, state) do
    notifications = Map.update(state.notifications, type, 1, &(&1 + 1))
    notifications = Map.update(notifications, :total, 1, &(&1 + 1))

    {:noreply, %{state | notifications: notifications}}
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
  def handle_call(:get_stats, _from, state) do
    uptime_seconds = case state.websocket.startup_time do
      nil -> 0
      startup_time -> DateTime.diff(DateTime.utc_now(), startup_time)
    end

    stats = %{
      uptime: format_uptime(uptime_seconds),
      uptime_seconds: uptime_seconds,
      startup_time: state.websocket.startup_time,
      notifications: state.notifications,
      websocket: state.websocket,
      first_notifications: Map.get(state, :first_notifications, %{})
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
      {key, %DateTime{} = dt} -> {key, dt}
      {key, nil} -> {key, nil}
      {key, val} when is_integer(val) and key in [:startup_time] ->
        {key, DateTime.from_unix!(val)}
      {key, val} -> {key, val}
    end)
    |> Map.new()
  end
end
