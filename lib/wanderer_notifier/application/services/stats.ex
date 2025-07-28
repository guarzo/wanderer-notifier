defmodule WandererNotifier.Application.Services.Stats do
  @moduledoc """
  Statistics tracking for WandererNotifier.
  Maintains counters and metrics for application monitoring.
  Also tracks first notification flags for feature gating.
  """
  use GenServer
  require Logger
  alias WandererNotifier.Shared.Utils.TimeUtils
  require Logger

  # State struct for the Stats GenServer
  defmodule State do
    @moduledoc """
    State structure for the Stats GenServer.

    Maintains all application statistics including RedisQ status,
    notification counts, processing metrics, and first notification flags.
    """

    @type redisq_status :: %{
            connected: boolean(),
            connecting: boolean(),
            last_message: DateTime.t() | nil,
            startup_time: DateTime.t() | nil,
            reconnects: non_neg_integer(),
            url: String.t() | nil,
            last_disconnect: DateTime.t() | nil
          }

    @type notifications :: %{
            total: non_neg_integer(),
            kills: non_neg_integer(),
            systems: non_neg_integer(),
            characters: non_neg_integer()
          }

    @type processing :: %{
            kills_processed: non_neg_integer(),
            kills_notified: non_neg_integer()
          }

    @type first_notifications :: %{
            kill: boolean(),
            character: boolean(),
            system: boolean()
          }

    @type t :: %__MODULE__{
            redisq: redisq_status(),
            notifications: notifications(),
            processing: processing(),
            first_notifications: first_notifications(),
            metrics: map(),
            killmails_received: non_neg_integer(),
            systems_count: non_neg_integer(),
            characters_count: non_neg_integer()
          }

    defstruct redisq: %{
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
              },
              metrics: %{},
              killmails_received: 0,
              systems_count: 0,
              characters_count: 0,
              websocket: %{}

    @doc """
    Creates a new Stats state with default values.
    """
    @spec new() :: t()
    def new, do: %__MODULE__{}
  end

  # Client API

  @doc """
  Starts the Stats GenServer.
  """
  def start_link(opts \\ []) do
    Logger.debug("Starting Stats tracking service...", category: :startup)
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
  Track the start of killmail processing.
  """
  def track_processing_start do
    increment(:killmail_processing_start)
  end

  @doc """
  Track the completion of killmail processing.
  """
  def track_processing_complete(result) do
    increment(:killmail_processing_complete)

    # Also track success or error specifically
    status = if match?({:ok, _}, result), do: :success, else: :error
    increment(:"killmail_processing_complete_#{status}")
  end

  @doc """
  Track a skipped killmail.
  """
  def track_processing_skipped do
    increment(:killmail_processing_skipped)
  end

  @doc """
  Track a processing error.
  """
  def track_processing_error do
    increment(:killmail_processing_error)
  end

  @doc """
  Track a notification being sent.
  """
  def track_notification_sent do
    increment(:notification_sent)
  end

  @doc """
  Track a killmail received from RedisQ/zkill.
  """
  def track_killmail_received do
    GenServer.cast(__MODULE__, {:track_killmail_received})
  end

  @doc """
  Updates the last activity timestamp.
  """
  def update_last_activity do
    GenServer.cast(__MODULE__, {:update_last_activity})
  end

  @doc """
  Updates WebSocket connection stats.
  """
  def update_websocket_stats(stats) do
    GenServer.cast(__MODULE__, {:update_websocket_stats, stats})
  end

  @doc """
  Returns the current statistics.
  """
  def get_stats do
    GenServer.call(__MODULE__, :get_stats)
  end

  @doc """
  Updates the redisq status.
  """
  def update_redisq(status) do
    GenServer.cast(__MODULE__, {:update_redisq, status})
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

    # Format killmail metrics
    metrics = stats.metrics || %{}
    processing_start = Map.get(metrics, :killmail_processing_start, 0)
    processing_complete = Map.get(metrics, :killmail_processing_complete, 0)
    processing_skipped = Map.get(metrics, :killmail_processing_skipped, 0)
    processing_error = Map.get(metrics, :killmail_processing_error, 0)

    # Format redisq status
    redisq = stats.redisq
    connected = if redisq.connected, do: "connected", else: "disconnected"

    last_message =
      case redisq.last_message do
        nil -> "never"
        dt -> "#{TimeUtils.elapsed_seconds(dt)}s ago"
      end

    # Log the summary
    Logger.info("📊 Stats Summary:
    Uptime: #{uptime}
    Notifications: #{total_notifications} total (#{kills_notified} kills, #{systems_notified} systems, #{characters_notified} characters)
    Processing: #{kills_processed} kills processed, #{kills_notified} kills notified
    Killmail Metrics: #{processing_start} started, #{processing_complete} completed, #{processing_skipped} skipped, #{processing_error} errors
    RedisQ: #{connected}, last message #{last_message}",
      category: :processor
    )
  end

  @doc """
  Sets the tracked count for a specific type (:systems or :characters).
  """
  def set_tracked_count(type, count) when type in [:systems, :characters] and is_integer(count) do
    GenServer.cast(__MODULE__, {:set_tracked_count, type, count})
  end

  # Server Implementation

  @killmail_metrics [
    :killmail_processing_start,
    :killmail_processing_complete,
    :killmail_processing_complete_success,
    :killmail_processing_complete_error,
    :killmail_processing_skipped,
    :killmail_processing_error,
    :notification_sent
  ]

  @impl true
  def init(_opts) do
    Logger.debug("Initializing stats tracking service...", category: :startup)
    # Initialize with current time as startup time
    state = State.new()
    startup_time = DateTime.utc_now()
    updated_redisq = Map.put(state.redisq, :startup_time, startup_time)
    {:ok, %{state | redisq: updated_redisq}}
  end

  defp handle_kill_processed(state) do
    processing = Map.update(state.processing, :kills_processed, 1, &(&1 + 1))
    {:noreply, %{state | processing: processing}}
  end

  defp handle_kill_notified(state) do
    processing = Map.update(state.processing, :kills_notified, 1, &(&1 + 1))
    {:noreply, %{state | processing: processing}}
  end

  defp handle_killmail_metric(type, state) do
    metrics = Map.update(state.metrics || %{}, type, 1, &(&1 + 1))
    {:noreply, %{state | metrics: metrics}}
  end

  defp handle_notification_increment(type, state) do
    notifications = Map.update(state.notifications, type, 1, &(&1 + 1))
    notifications = Map.update(notifications, :total, 1, &(&1 + 1))
    {:noreply, %{state | notifications: notifications}}
  end

  @impl true
  def handle_cast({:increment, type}, state) do
    case type do
      :kill_processed -> handle_kill_processed(state)
      :kill_notified -> handle_kill_notified(state)
      type when type in @killmail_metrics -> handle_killmail_metric(type, state)
      _ -> handle_notification_increment(type, state)
    end
  end

  @impl true
  def handle_cast({:update_redisq, status}, state) do
    # Merge the new status with existing redisq state to preserve fields
    # Convert any DateTime fields to ensure proper comparison
    normalized_status = normalize_datetime_fields(status)
    updated_redisq = Map.merge(state.redisq, normalized_status)

    # Log the update for debugging
    Logger.debug("Updated RedisQ status",
      old_status: state.redisq,
      new_status: updated_redisq,
      category: :processor
    )

    {:noreply, %{state | redisq: updated_redisq}}
  end

  @impl true
  def handle_cast({:mark_notification_sent, type}, state) do
    # Update the first_notifications map to mark this type as sent
    first_notifications = Map.put(state.first_notifications, type, false)

    Logger.debug("Marked #{type} notification as sent - no longer first notification",
      category: :config
    )

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
  def handle_cast({:track_killmail_received}, state) do
    {:noreply, Map.update(state, :killmails_received, 1, &(&1 + 1))}
  end

  @impl true
  def handle_cast({:update_last_activity}, state) do
    updated_redisq = Map.put(state.redisq, :last_message, DateTime.utc_now())
    {:noreply, %{state | redisq: updated_redisq}}
  end

  @impl true
  def handle_cast({:update_websocket_stats, stats}, state) do
    {:noreply, %{state | websocket: stats}}
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
      case state.redisq.startup_time do
        nil ->
          # Fallback: if startup_time is nil, set it to current time
          Logger.debug("Startup time was nil, setting to current time", category: :processor)
          0

        startup_time ->
          TimeUtils.elapsed_seconds(startup_time)
      end

    stats = %{
      uptime: format_uptime(uptime_seconds),
      uptime_seconds: uptime_seconds,
      startup_time: state.redisq.startup_time,
      notifications: state.notifications,
      redisq: state.redisq,
      first_notifications: Map.get(state, :first_notifications, %{}),
      processing: state.processing,
      systems_count: Map.get(state, :systems_count, 0),
      characters_count: Map.get(state, :characters_count, 0),
      metrics: state.metrics || %{},
      killmails_received: Map.get(state, :killmails_received, 0),
      websocket: Map.get(state, :websocket, %{})
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
    TimeUtils.format_uptime(seconds)
  end

  # Helper to normalize DateTime fields in the status map
  defp normalize_datetime_fields(status) do
    Enum.into(status, %{}, fn
      {key, %DateTime{} = dt} ->
        {key, dt}

      {key, nil} ->
        {key, nil}

      {key, val} when is_integer(val) and key in [:startup_time] ->
        {key, DateTime.from_unix!(val)}

      {key, val} ->
        {key, val}
    end)
  end
end
