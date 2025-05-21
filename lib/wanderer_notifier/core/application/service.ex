# lib/wanderer_notifier/core/application/service.ex
defmodule WandererNotifier.Core.Application.Service do
  @moduledoc """
  Coordinates the websocket connection, kill processing, and periodic updates.
  """

  use GenServer

  alias WandererNotifier.Config
  alias WandererNotifier.Killmail.Processor, as: KillmailProcessor
  alias WandererNotifier.Schedulers.{CharacterUpdateScheduler, SystemUpdateScheduler}
  alias WandererNotifier.Killmail.Websocket
  alias WandererNotifier.Logger.Logger, as: AppLogger
  alias WandererNotifier.Cache.Keys

  @default_interval 30_000

  @typedoc "Internal state for the Service GenServer"
  @type state :: %__MODULE__.State{
          ws_pid: pid() | nil,
          service_start_time: integer()
        }

  defmodule State do
    @moduledoc false
    defstruct [
      :ws_pid,
      service_start_time: nil,
      reconnect_attempts: 0,
      last_reconnect_time: nil,
      # Track the timer reference
      reconnect_timer: nil
    ]
  end

  # Constants for reconnection strategy
  @max_reconnect_attempts 10
  # 1 second
  @base_reconnect_delay 1_000
  # 1 minute
  @max_reconnect_delay 60_000
  # 5 minutes
  @reconnect_reset_timeout 300_000

  ## Public API

  @doc "Start the service under its registered name"
  def start_link(opts \\ []), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @doc "Mark a kill ID as processed (for deduplication)"
  @spec mark_as_processed(integer() | String.t()) :: :ok
  def mark_as_processed(kill_id), do: GenServer.cast(__MODULE__, {:mark_as_processed, kill_id})

  @doc "Get the list of recent kills (for API)"
  defdelegate get_recent_kills(), to: KillmailProcessor

  @doc """
  Checks if a service is running.
  """
  def running?(service_name) do
    case Process.whereis(service_name) do
      nil -> false
      pid when is_pid(pid) -> Process.alive?(pid)
    end
  end

  @doc """
  Gets the current environment.
  """
  def environment do
    Application.get_env(:wanderer_notifier, :environment, :dev)
  end

  @doc """
  Checks if we're in development mode.
  """
  def dev_mode? do
    environment() == :dev
  end

  @doc """
  Checks if we're in test mode.
  """
  def test_mode? do
    environment() == :test
  end

  @doc """
  Checks if we're in production mode.
  """
  def prod_mode? do
    environment() == :prod
  end

  @doc """
  Gets a configuration value.
  """
  def get_config(key, default \\ nil) do
    Application.get_env(:wanderer_notifier, key, default)
  end

  @doc """
  Sets a configuration value.
  """
  def set_config(key, value) do
    Application.put_env(:wanderer_notifier, key, value)
  end

  @doc """
  Gets a feature flag value.
  """
  def get_feature_flag(key, default \\ false) do
    get_config(:features, %{})
    |> Map.get(key, default)
  end

  @doc """
  Sets a feature flag value.
  """
  def set_feature_flag(key, value) do
    features = get_config(:features, %{})
    set_config(:features, Map.put(features, key, value))
  end

  @doc """
  Checks if a feature is enabled.
  """
  def feature_enabled?(key) do
    get_feature_flag(key)
  end

  @doc """
  Gets a cache value.
  """
  def get_cache(key) do
    cache_name = Application.get_env(:wanderer_notifier, :cache_name, :wanderer_cache)
    Cachex.get(cache_name, key)
  end

  @doc """
  Sets a cache value.
  """
  def set_cache(key, value, ttl \\ nil) do
    cache_name = Application.get_env(:wanderer_notifier, :cache_name, :wanderer_cache)
    Cachex.put(cache_name, key, value, ttl: ttl)
  end

  @doc """
  Deletes a cache value.
  """
  def delete_cache(key) do
    cache_name = Application.get_env(:wanderer_notifier, :cache_name, :wanderer_cache)
    Cachex.del(cache_name, key)
  end

  @doc """
  Clears the cache.
  """
  def clear_cache do
    cache_name = Application.get_env(:wanderer_notifier, :cache_name, :wanderer_cache)
    Cachex.clear(cache_name)
  end

  ## GenServer callbacks

  @impl true
  def init(_opts) do
    AppLogger.startup_debug("Initializing WandererNotifier Service")
    Process.flag(:trap_exit, true)

    now = System.system_time(:second)
    KillmailProcessor.init()

    state =
      %State{service_start_time: now}
      |> connect_websocket()
      |> schedule_startup_notice()
      |> schedule_maintenance(@default_interval)
      |> schedule_websocket_health_check()

    # Schedule killmail stats logging
    KillmailProcessor.schedule_tasks()

    # Schedule the very first systems/characters update
    Process.send_after(self(), :update_tracked_data, 10_000)

    {:ok, state}
  end

  @impl true
  def handle_cast({:mark_as_processed, kill_id}, state) do
    ttl = Config.kill_dedup_ttl()
    key = Keys.killmail(kill_id, "processed")

    # Cache the deduplication key
    cache_name = Application.get_env(:wanderer_notifier, :cache_name, :wanderer_cache)

    case Cachex.put(cache_name, key, true, ttl: ttl) do
      :ok ->
        {:noreply, state}

      {:error, reason} ->
        AppLogger.api_error("Failed to cache deduplication key", error: inspect(reason))
        {:noreply, state}
    end
  end

  @impl true
  def handle_info(:update_tracked_data, state) do
    SystemUpdateScheduler.run()
    CharacterUpdateScheduler.run()
    {:noreply, state}
  rescue
    e ->
      AppLogger.startup_error("Initial data update failed", error: Exception.message(e))
      Process.send_after(self(), :update_tracked_data, 5_000)
      {:noreply, state}
  end

  @impl true
  def handle_info(:send_startup_notification, state) do
    uptime = System.system_time(:second) - state.service_start_time
    AppLogger.startup_info("Service started", uptime: uptime)

    WandererNotifier.Notifiers.StatusNotifier.send_status_message(
      "WandererNotifier Service Status",
      "The service has started and is now operational."
    )

    {:noreply, state}
  rescue
    e ->
      AppLogger.startup_error("Startup notification failed", error: Exception.message(e))
      {:noreply, state}
  end

  @impl true
  def handle_info(:run_maintenance, state) do
    try do
      run_maintenance()
      # Log maintenance execution
    rescue
      e ->
        AppLogger.scheduler_error("Maintenance error", error: Exception.message(e))
    end

    # schedule next tick regardless of success/failure
    state = schedule_maintenance(state, @default_interval)
    {:noreply, state}
  end

  @impl true
  def handle_info({:zkill_message, data}, state) do
    # Save a backup of the current state in process dictionary
    # This helps recover if something goes wrong during processing
    Process.put(:backup_state, state)

    # Process through the consolidated API
    case KillmailProcessor.process_killmail(data, source: :zkill_websocket, state: state) do
      {:ok, _result} ->
        # Successfully processed
        {:noreply, state}

      {:error, reason} ->
        # Error occurred, log it but don't crash the process
        AppLogger.websocket_error("Error processing zkill message", error: inspect(reason))
        {:noreply, state}

      unexpected ->
        # Unexpected return value, log for debugging
        AppLogger.websocket_error("Unexpected return from process_killmail",
          return_value: inspect(unexpected)
        )

        {:noreply, state}
    end
  end

  @impl true
  def handle_info(:attempt_connection, state) do
    case start_websocket(Config.websocket_config().url, state) do
      {:ok, new_state} ->
        # Reset reconnect attempts on successful connection
        {:noreply,
         %{new_state | reconnect_attempts: 0, last_reconnect_time: nil, reconnect_timer: nil}}

      {:error, reason} ->
        AppLogger.websocket_error("Failed to start websocket", %{error: reason})

        # Only schedule retry if we haven't exceeded max attempts
        if state.reconnect_attempts < @max_reconnect_attempts do
          # Calculate next retry delay with exponential backoff
          next_delay = calculate_reconnect_delay(state)

          # Update state with new attempt count and time
          new_state = %{
            state
            | reconnect_attempts: state.reconnect_attempts + 1,
              last_reconnect_time: DateTime.utc_now(),
              reconnect_timer: Process.send_after(self(), :attempt_connection, next_delay)
          }

          {:noreply, new_state}
        else
          # We've hit max attempts, wait for the reset timeout
          next_delay = @reconnect_reset_timeout

          new_state = %{
            state
            | reconnect_timer: Process.send_after(self(), :reset_reconnect_attempts, next_delay)
          }

          AppLogger.websocket_warn("Max reconnection attempts reached, waiting for reset timeout",
            attempts: state.reconnect_attempts,
            reset_in: div(next_delay, 1000)
          )

          {:noreply, new_state}
        end
    end
  end

  @impl true
  def handle_info(:reconnect_ws, state) do
    # Cancel any existing reconnect timer
    if state.reconnect_timer do
      Process.cancel_timer(state.reconnect_timer)
    end

    # Log the reconnection attempt
    AppLogger.websocket_info("Attempting to reconnect websocket",
      attempt: state.reconnect_attempts + 1,
      max_attempts: @max_reconnect_attempts
    )

    # Make sure we properly monitor the new connection
    new_state = connect_websocket(state)

    # If reconnection failed, schedule another attempt with backoff
    if new_state.ws_pid == nil do
      if new_state.reconnect_attempts < @max_reconnect_attempts do
        next_delay = calculate_reconnect_delay(new_state)

        new_state = %{
          new_state
          | reconnect_timer: Process.send_after(self(), :reconnect_ws, next_delay)
        }

        AppLogger.websocket_warn("Reconnection failed, scheduling another attempt",
          attempt: new_state.reconnect_attempts + 1,
          next_attempt_in: div(next_delay, 1000)
        )
      else
        # We've hit max attempts, wait for the reset timeout
        next_delay = @reconnect_reset_timeout

        new_state = %{
          new_state
          | reconnect_timer: Process.send_after(self(), :reset_reconnect_attempts, next_delay)
        }

        AppLogger.websocket_warn("Max reconnection attempts reached, waiting for reset timeout",
          attempts: new_state.reconnect_attempts,
          reset_in: div(next_delay, 1000)
        )
      end
    else
      AppLogger.websocket_info("Websocket reconnected successfully",
        pid: inspect(new_state.ws_pid)
      )
    end

    {:noreply, new_state}
  end

  @impl true
  def handle_info(:reset_reconnect_attempts, state) do
    AppLogger.websocket_info("Resetting reconnection attempts after timeout")
    {:noreply, %{state | reconnect_attempts: 0, last_reconnect_time: nil, reconnect_timer: nil}}
  end

  @impl true
  def handle_info(:check_websocket_health, state) do
    # Ensure state is a proper State struct, if not recreate it to prevent crashes
    state = ensure_valid_state(state)

    # Schedule the next check
    state = schedule_websocket_health_check(state)

    # Get the current stats
    stats = WandererNotifier.Core.Stats.get_stats()
    ws_status = stats.websocket

    AppLogger.websocket_debug("Checking websocket health",
      connected: ws_status.connected,
      connecting: ws_status.connecting,
      ws_pid: if(state.ws_pid, do: inspect(state.ws_pid), else: "nil"),
      last_message:
        if(ws_status.last_message, do: DateTime.to_string(ws_status.last_message), else: "never"),
      reconnects: ws_status.reconnects
    )

    # Check if we need to force a reconnect
    if websocket_needs_reconnect?(state, ws_status) do
      # Send a reconnect message
      AppLogger.websocket_info("Health check initiating websocket reconnect")
      self() |> send(:reconnect_ws)
    end

    {:noreply, state}
  rescue
    e ->
      # If an error occurs during websocket health check, log it and ensure we have a valid state
      AppLogger.websocket_error("Error in websocket health check",
        error: Exception.message(e),
        state_type: inspect(state)
      )

      # Create a fresh state to avoid further errors
      fresh_state = %State{service_start_time: System.system_time(:second)}
      Process.send_after(self(), :reconnect_ws, 5_000)

      # Make sure we schedule another health check in the future
      schedule_websocket_health_check(fresh_state)

      {:noreply, fresh_state}
  end

  @impl true
  def handle_info({:websocket_terminated, pid, reason}, %{ws_pid: current_pid} = state) do
    # Only handle if this is our current websocket
    if pid == current_pid do
      AppLogger.websocket_info("Received websocket termination notification",
        pid: inspect(pid),
        reason: inspect(reason)
      )

      # Mark the process as nil
      new_state = %{state | ws_pid: nil}

      # Schedule reconnection
      reconnect_delay = min(Config.websocket_reconnect_delay(), 3_000)
      Process.send_after(self(), :reconnect_ws, reconnect_delay)

      {:noreply, new_state}
    else
      # This is a termination for an old websocket we don't care about
      AppLogger.websocket_debug("Ignoring termination for old websocket",
        terminated_pid: inspect(pid),
        current_pid: inspect(current_pid)
      )

      {:noreply, state}
    end
  end

  @impl true
  # Catch-all to make unhandled messages visible in logs
  def handle_info(other, state) do
    AppLogger.processor_debug("Unhandled message in Service", msg: inspect(other))
    {:noreply, state}
  end

  ## Internal helpers

  defp check_pid_and_connect(pid, state) do
    if Process.alive?(pid) do
      state
    else
      # PID exists but process is dead, clear it and reconnect
      AppLogger.websocket_debug("Websocket PID exists but process is dead", pid: inspect(pid))
      connect_websocket(%{state | ws_pid: nil})
    end
  end

  # (Re)establish the Killmail Websocket, if enabled
  defp connect_websocket(%State{ws_pid: pid} = state) when is_pid(pid),
    do: check_pid_and_connect(pid, state)

  defp connect_websocket(state) do
    if Config.websocket_enabled?() do
      AppLogger.websocket_debug("Starting Killmail Websocket")
      state = clear_previous_connection(state)
      state = update_websocket_stats(state)
      attempt_websocket_connection(state)
    else
      AppLogger.websocket_info("Websocket disabled by configuration")
      state
    end
  end

  defp clear_previous_connection(state) do
    if state.ws_pid != nil do
      AppLogger.websocket_debug("Clearing previous websocket PID",
        old_pid: inspect(state.ws_pid)
      )
    end

    %{state | ws_pid: nil}
  end

  defp update_websocket_stats(state) do
    WandererNotifier.Core.Stats.update_websocket(%{connecting: true})
    state
  end

  defp attempt_websocket_connection(state) do
    # Schedule connection attempt after a short delay
    Process.send_after(self(), :attempt_connection, 100)
    state
  end

  defp start_websocket(url, state) do
    case Websocket.start_link(url: url, parent: self()) do
      {:ok, ws_pid} ->
        monitor_ref = Process.monitor(ws_pid)

        AppLogger.websocket_info("Successfully started websocket",
          pid: inspect(ws_pid),
          monitor_ref: inspect(monitor_ref)
        )

        {:ok, %{state | ws_pid: ws_pid}}

      {:error, reason} ->
        AppLogger.websocket_error("Websocket start failed", error: inspect(reason))
        reconnect_delay = min(Config.websocket_reconnect_delay(), 5_000)
        Process.send_after(self(), :reconnect_ws, reconnect_delay)
        {:error, reason}
    end
  end

  # Schedule the startup notification
  defp schedule_startup_notice(state) do
    Process.send_after(self(), :send_startup_notification, 2_000)
    state
  end

  # Schedule the maintenance loop
  @spec schedule_maintenance(state(), non_neg_integer()) :: state()
  defp schedule_maintenance(state, interval) do
    Process.send_after(self(), :run_maintenance, interval)
    state
  end

  # Schedule a periodic websocket health check
  defp schedule_websocket_health_check(state) do
    # Check every 60 seconds instead of 10
    Process.send_after(self(), :check_websocket_health, 60_000)
    state
  end

  # What runs on each maintenance tick
  defp run_maintenance do
    # Let the scheduler supervisor handle running the schedulers
    KillmailProcessor.schedule_tasks()
    :ok
  end

  # Helper to ensure we have a valid State struct
  defp ensure_valid_state(state) do
    cond do
      # Valid State struct with ws_pid field
      is_map(state) and is_map_key(state, :ws_pid) and is_map_key(state, :service_start_time) ->
        state

      # Process dictionary has state backup
      Process.get(:backup_state) ->
        AppLogger.websocket_info("Restored state from backup")
        Process.get(:backup_state)

      # Create new state as fallback
      true ->
        AppLogger.websocket_warn("Created new State struct due to invalid state",
          received: inspect(state)
        )

        %State{service_start_time: System.system_time(:second)}
    end
  end

  # Helper function to determine if websocket needs reconnection
  defp websocket_needs_reconnect?(state, ws_status) do
    cond do
      # No process ID for websocket
      state.ws_pid == nil ->
        AppLogger.websocket_warn("Health check found nil websocket PID")
        true

      # PID exists but process is dead
      not Process.alive?(state.ws_pid) ->
        AppLogger.websocket_warn("Health check found dead websocket process",
          pid: inspect(state.ws_pid)
        )

        true

      # Everything looks connected in stats
      ws_status.connected ->
        false

      # We're in connecting state - check if we're actually stalled
      ws_status.connecting ->
        # If we're receiving messages, we're not stalled
        if ws_status.last_message &&
             DateTime.diff(DateTime.utc_now(), ws_status.last_message, :second) < 120 do
          false
        else
          # Only consider stalled if we've been disconnected for a while
          stalled_reconnect?(ws_status.last_disconnect)
        end

      # Not connected or connecting - force reconnect
      true ->
        AppLogger.websocket_warn("Health check found disconnected websocket")
        true
    end
  end

  # Helper to determine if a reconnect attempt has stalled
  defp stalled_reconnect?(nil), do: false

  defp stalled_reconnect?(timestamp) do
    diff = DateTime.diff(DateTime.utc_now(), timestamp, :second)

    # 5 minutes
    if diff > 300 do
      AppLogger.websocket_warn("Health check found stalled reconnect",
        seconds_since_disconnect: diff
      )

      true
    else
      false
    end
  end

  # Calculate next reconnect delay using exponential backoff
  defp calculate_reconnect_delay(state) do
    # If we haven't tried to reconnect yet, use base delay
    if state.reconnect_attempts == 0 do
      @base_reconnect_delay
    else
      # Check if we should reset the backoff (if last attempt was long ago)
      if state.last_reconnect_time &&
           DateTime.diff(DateTime.utc_now(), state.last_reconnect_time, :millisecond) >
             @reconnect_reset_timeout do
        @base_reconnect_delay
      else
        # Calculate exponential backoff: base * 2^attempts, capped at max delay
        delay = @base_reconnect_delay * :math.pow(2, state.reconnect_attempts)
        min(trunc(delay), @max_reconnect_delay)
      end
    end
  end
end
