defmodule WandererNotifier.Stats do
  @moduledoc """
  Tracks statistics about notifications sent and application status.
  """
  use GenServer
  require Logger

  # Client API

  @doc """
  Starts the Stats GenServer.
  """
  def start_link(opts \\ []) do
    Logger.info("Starting Stats tracking service...")
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Increments the count for a specific notification type.
  """
  def increment(type) do
    GenServer.cast(__MODULE__, {:increment, type})
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

  # Server Implementation

  @impl true
  def init(_opts) do
    Logger.info("Initializing stats tracking service...")
    
    initial_state = %{
      startup_time: DateTime.utc_now(),
      notifications: %{
        kills: 0,
        errors: 0,
        systems: 0,
        characters: 0,
        total: 0
      },
      websocket: %{
        connected: false,
        last_message: nil,
        reconnects: 0
      }
    }
    
    {:ok, initial_state}
  end

  @impl true
  def handle_cast({:increment, type}, state) do
    notifications = Map.update(state.notifications, type, 1, &(&1 + 1))
    notifications = Map.update(notifications, :total, 1, &(&1 + 1))
    
    {:noreply, %{state | notifications: notifications}}
  end

  @impl true
  def handle_cast({:update_websocket, status}, state) do
    {:noreply, %{state | websocket: status}}
  end

  @impl true
  def handle_call(:get_stats, _from, state) do
    uptime_seconds = DateTime.diff(DateTime.utc_now(), state.startup_time)
    
    stats = %{
      uptime: format_uptime(uptime_seconds),
      uptime_seconds: uptime_seconds,
      startup_time: state.startup_time,
      notifications: state.notifications,
      websocket: state.websocket
    }
    
    {:reply, stats, state}
  end

  # Helper functions

  defp format_uptime(seconds) do
    days = div(seconds, 86400)
    seconds = rem(seconds, 86400)
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
end 