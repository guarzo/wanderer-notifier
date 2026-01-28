defmodule WandererNotifier.Shared.Metrics do
  @moduledoc """
  Simple metrics tracking without GenServer overhead.

  Uses Agent for lightweight state management and provides
  a clean interface for metric collection throughout the application.
  """

  use Agent
  require Logger

  @type metric_type :: atom()
  @type notification_type :: :kill | :character | :system

  # ──────────────────────────────────────────────────────────────────────────────
  # Public API
  # ──────────────────────────────────────────────────────────────────────────────

  @doc """
  Starts the metrics agent.
  """
  def start_link(_opts) do
    Agent.start_link(fn -> initial_state() end, name: __MODULE__)
  end

  @doc """
  Increments a metric counter.
  """
  @spec increment(metric_type()) :: :ok
  def increment(type) do
    Agent.update(__MODULE__, fn state ->
      update_in(state, [:counters, type], &((&1 || 0) + 1))
    end)
  end

  @doc """
  Gets all metrics statistics.
  """
  @spec get_stats() :: map()
  def get_stats do
    Agent.get(__MODULE__, & &1)
  end

  @doc """
  Gets a specific counter value.
  """
  @spec get_counter(metric_type()) :: non_neg_integer()
  def get_counter(type) do
    Agent.get(__MODULE__, fn state ->
      get_in(state, [:counters, type]) || 0
    end)
  end

  @doc """
  Checks if this is the first notification of a specific type.
  """
  @spec first_notification?(notification_type()) :: boolean()
  def first_notification?(type) when type in [:kill, :character, :system] do
    Agent.get(__MODULE__, fn state ->
      not get_in(state, [:notifications_sent, type])
    end)
  end

  @doc """
  Marks that a notification of the given type has been sent.
  """
  @spec mark_notification_sent(notification_type()) :: :ok
  def mark_notification_sent(type) when type in [:kill, :character, :system] do
    Agent.update(__MODULE__, fn state ->
      put_in(state, [:notifications_sent, type], true)
    end)
  end

  @doc """
  Sets the tracked count for systems or characters.
  """
  @spec set_tracked_count(:systems | :characters, non_neg_integer()) :: :ok
  def set_tracked_count(type, count) when type in [:systems, :characters] and is_integer(count) do
    key = String.to_atom("#{type}_count")

    Agent.update(__MODULE__, fn state ->
      Map.put(state, key, count)
    end)
  end

  @doc """
  Gets uptime in seconds since startup.
  """
  @spec get_uptime_seconds() :: non_neg_integer()
  def get_uptime_seconds do
    Agent.get(__MODULE__, fn state ->
      case state.startup_time do
        nil ->
          0

        startup_time ->
          DateTime.diff(DateTime.utc_now(), startup_time, :second)
      end
    end)
  end

  @doc """
  Updates websocket connection info.
  """
  @spec update_websocket_info(map()) :: :ok
  def update_websocket_info(info) do
    Agent.update(__MODULE__, fn state ->
      websocket_info = Map.get(state, :websocket, %{})
      updated_info = Map.merge(websocket_info, info)
      Map.put(state, :websocket, updated_info)
    end)
  end

  @doc """
  Records that a killmail was received from the WebSocket.
  """
  @spec record_killmail_received(String.t() | integer()) :: :ok
  def record_killmail_received(killmail_id) do
    now = DateTime.utc_now()

    Agent.update(__MODULE__, fn state ->
      killmail_activity = Map.get(state, :killmail_activity, %{})

      updated_activity =
        killmail_activity
        |> Map.put(:last_received_at, now)
        |> Map.put(:last_received_id, to_string(killmail_id))
        |> Map.update(:received_count, 1, &(&1 + 1))

      Map.put(state, :killmail_activity, updated_activity)
    end)
  end

  @doc """
  Records that a killmail notification was sent.
  """
  @spec record_killmail_notified(String.t() | integer()) :: :ok
  def record_killmail_notified(killmail_id) do
    now = DateTime.utc_now()

    Agent.update(__MODULE__, fn state ->
      killmail_activity = Map.get(state, :killmail_activity, %{})

      updated_activity =
        killmail_activity
        |> Map.put(:last_notified_at, now)
        |> Map.put(:last_notified_id, to_string(killmail_id))
        |> Map.update(:notified_count, 1, &(&1 + 1))

      Map.put(state, :killmail_activity, updated_activity)
    end)
  end

  @doc """
  Gets killmail activity statistics.
  """
  @spec get_killmail_activity() :: map()
  def get_killmail_activity do
    Agent.get(__MODULE__, fn state ->
      Map.get(state, :killmail_activity, %{
        last_received_at: nil,
        last_received_id: nil,
        received_count: 0,
        last_notified_at: nil,
        last_notified_id: nil,
        notified_count: 0
      })
    end)
  end

  # ──────────────────────────────────────────────────────────────────────────────
  # Private Functions
  # ──────────────────────────────────────────────────────────────────────────────

  defp initial_state do
    %{
      counters: %{},
      startup_time: DateTime.utc_now(),
      notifications_sent: %{kill: false, character: false, system: false},
      systems_count: 0,
      characters_count: 0,
      killmail_activity: %{
        last_received_at: nil,
        last_received_id: nil,
        received_count: 0,
        last_notified_at: nil,
        last_notified_id: nil,
        notified_count: 0
      }
    }
  end
end
