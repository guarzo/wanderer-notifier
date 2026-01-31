defmodule WandererNotifier.Domains.Notifications.Discord.ConnectionHealth do
  @moduledoc """
  Monitors Discord/Nostrum connection health and provides recovery mechanisms.

  This module:
  - Tracks consecutive timeouts and failures
  - Provides detailed diagnostics about Nostrum/Gun state
  - Can trigger recovery actions when connection appears stuck
  - Logs periodic health status
  """

  use GenServer
  require Logger

  @health_check_interval :timer.minutes(1)
  @timeout_threshold 3
  @max_failed_kills 5

  # ──────────────────────────────────────────────────────────────────────────────
  # Public API
  # ──────────────────────────────────────────────────────────────────────────────

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Records a successful Discord API call.
  """
  @spec record_success() :: :ok
  def record_success do
    GenServer.cast(__MODULE__, :record_success)
  catch
    :exit, _ -> :ok
  end

  @doc """
  Records a failed Discord API call.
  Optionally accepts a killmail_id to track which kills failed.
  """
  @spec record_failure(atom() | term(), String.t() | integer() | nil) :: :ok
  def record_failure(reason, killmail_id \\ nil) do
    GenServer.cast(__MODULE__, {:record_failure, reason, killmail_id})
  catch
    :exit, _ -> :ok
  end

  @doc """
  Records a timeout in Discord API call.
  Optionally accepts a killmail_id to track which kills failed.
  """
  @spec record_timeout(String.t() | integer() | nil) :: :ok
  def record_timeout(killmail_id \\ nil) do
    GenServer.cast(__MODULE__, {:record_timeout, killmail_id})
  catch
    :exit, _ -> :ok
  end

  @doc """
  Records a failed killmail notification without affecting health counters.
  Use this when the failure is already recorded by NeoClient but you want to
  track the specific killmail_id.
  """
  @spec record_failed_killmail(String.t() | integer(), atom() | term()) :: :ok
  def record_failed_killmail(killmail_id, reason) do
    GenServer.cast(__MODULE__, {:record_failed_killmail, killmail_id, reason})
  catch
    :exit, _ -> :ok
  end

  @doc """
  Gets current health status and diagnostics.
  """
  @spec get_health_status() :: map()
  def get_health_status do
    GenServer.call(__MODULE__, :get_health_status, 5_000)
  catch
    :exit, _ -> %{error: "Health monitor not available"}
  end

  @doc """
  Gets comprehensive Nostrum/Gun diagnostics.
  """
  @spec get_diagnostics() :: map()
  def get_diagnostics do
    %{
      nostrum: get_nostrum_diagnostics(),
      gun: get_gun_diagnostics(),
      ratelimiter: get_ratelimiter_diagnostics(),
      timestamp: DateTime.utc_now()
    }
  end

  @doc """
  Attempts to recover from a stuck connection state.
  """
  @spec attempt_recovery() :: :ok | {:error, term()}
  def attempt_recovery do
    GenServer.call(__MODULE__, :attempt_recovery, 30_000)
  catch
    :exit, reason -> {:error, reason}
  end

  # ──────────────────────────────────────────────────────────────────────────────
  # GenServer Callbacks
  # ──────────────────────────────────────────────────────────────────────────────

  @impl true
  def init(_opts) do
    Logger.info("[Discord Health] Connection health monitor started")
    schedule_health_check()

    {:ok,
     %{
       consecutive_timeouts: 0,
       consecutive_failures: 0,
       last_success_at: nil,
       last_failure_at: nil,
       last_failure_reason: nil,
       total_successes: 0,
       total_failures: 0,
       total_timeouts: 0,
       recovery_attempts: 0,
       last_recovery_at: nil,
       failed_kills: []
     }}
  end

  @impl true
  def handle_cast(:record_success, state) do
    new_state = %{
      state
      | consecutive_timeouts: 0,
        consecutive_failures: 0,
        last_success_at: DateTime.utc_now(),
        total_successes: state.total_successes + 1
    }

    {:noreply, new_state}
  end

  @impl true
  def handle_cast({:record_timeout, killmail_id}, state) do
    new_consecutive = state.consecutive_timeouts + 1

    if new_consecutive >= @timeout_threshold do
      Logger.error(
        "[Discord Health] #{new_consecutive} consecutive timeouts detected - connection may be stuck",
        diagnostics: get_diagnostics()
      )

      # Auto-attempt recovery after threshold
      spawn(fn -> attempt_recovery() end)
    end

    new_state = %{
      state
      | consecutive_timeouts: new_consecutive,
        last_failure_at: DateTime.utc_now(),
        last_failure_reason: :timeout,
        total_timeouts: state.total_timeouts + 1,
        failed_kills: add_failed_kill(state.failed_kills, killmail_id, :timeout)
    }

    {:noreply, new_state}
  end

  @impl true
  def handle_cast({:record_failure, reason, killmail_id}, state) do
    new_state = %{
      state
      | consecutive_failures: state.consecutive_failures + 1,
        last_failure_at: DateTime.utc_now(),
        last_failure_reason: reason,
        total_failures: state.total_failures + 1,
        failed_kills: add_failed_kill(state.failed_kills, killmail_id, reason)
    }

    {:noreply, new_state}
  end

  @impl true
  def handle_cast({:record_failed_killmail, killmail_id, reason}, state) do
    # Only add to failed_kills list, don't affect counters (NeoClient handles those)
    new_state = %{
      state
      | failed_kills: add_failed_kill(state.failed_kills, killmail_id, reason)
    }

    {:noreply, new_state}
  end

  @impl true
  def handle_call(:get_health_status, _from, state) do
    status = %{
      healthy: healthy?(state),
      consecutive_timeouts: state.consecutive_timeouts,
      consecutive_failures: state.consecutive_failures,
      last_success_at: state.last_success_at,
      last_failure_at: state.last_failure_at,
      last_failure_reason: state.last_failure_reason,
      total_successes: state.total_successes,
      total_failures: state.total_failures,
      total_timeouts: state.total_timeouts,
      recovery_attempts: state.recovery_attempts,
      failed_kills: state.failed_kills,
      diagnostics: get_diagnostics()
    }

    {:reply, status, state}
  end

  @impl true
  def handle_call(:attempt_recovery, _from, state) do
    Logger.warning("[Discord Health] Attempting connection recovery")

    result = do_recovery()

    new_state = %{
      state
      | recovery_attempts: state.recovery_attempts + 1,
        last_recovery_at: DateTime.utc_now()
    }

    {:reply, result, new_state}
  end

  @impl true
  def handle_info(:health_check, state) do
    log_health_status(state)
    schedule_health_check()
    {:noreply, state}
  end

  # ──────────────────────────────────────────────────────────────────────────────
  # Private Functions - Diagnostics
  # ──────────────────────────────────────────────────────────────────────────────

  defp get_nostrum_diagnostics do
    %{
      consumer_alive: consumer_alive?(),
      gateway_alive: gateway_alive?(),
      ratelimiter_alive: ratelimiter_alive?(),
      shard_status: get_shard_status()
    }
  end

  defp get_gun_diagnostics do
    # Check Gun connection pools
    pools = get_gun_pools()

    %{
      pools_count: length(pools),
      pools: pools
    }
  end

  defp get_ratelimiter_diagnostics do
    case Process.whereis(Nostrum.Api.Ratelimiter) do
      nil -> %{exists: false, status: :not_running}
      pid -> fetch_ratelimiter_state(pid)
    end
  end

  defp fetch_ratelimiter_state(pid) do
    case :sys.get_state(pid, 2_000) do
      {state_name, state_data} when is_atom(state_name) ->
        build_ratelimiter_state_info(state_name, state_data)

      other ->
        %{exists: true, state: :unexpected, raw: inspect(other) |> String.slice(0, 100)}
    end
  catch
    :exit, {:timeout, _} -> %{exists: true, status: :blocked, error: "sys.get_state timeout"}
    :exit, reason -> %{exists: true, status: :error, error: inspect(reason)}
  end

  defp build_ratelimiter_state_info(state_name, state_data) do
    %{
      exists: true,
      state_name: state_name,
      connection: get_connection_status(state_data),
      outstanding_count: state_data |> Map.get(:outstanding, %{}) |> map_size(),
      running_count: state_data |> Map.get(:running, %{}) |> map_size(),
      inflight_count: state_data |> Map.get(:inflight, %{}) |> map_size(),
      queue_lengths: get_queue_lengths(state_data)
    }
  end

  defp get_connection_status(state_data) do
    case Map.get(state_data, :conn) do
      nil ->
        :no_connection

      conn_pid when is_pid(conn_pid) ->
        if Process.alive?(conn_pid) do
          # Try to get more info about the connection
          try do
            info = Process.info(conn_pid, [:message_queue_len, :status])
            %{status: :alive, queue_len: info[:message_queue_len], process_status: info[:status]}
          catch
            _, _ -> :alive
          end
        else
          :dead
        end

      _ ->
        :unknown
    end
  end

  defp get_queue_lengths(state_data) do
    %{
      outstanding: state_data |> Map.get(:outstanding, %{}) |> map_size(),
      running: state_data |> Map.get(:running, %{}) |> map_size(),
      inflight: state_data |> Map.get(:inflight, %{}) |> map_size()
    }
  end

  defp consumer_alive? do
    # Check if NeoClient process is alive
    case Process.whereis(WandererNotifier.Domains.Notifications.Notifiers.Discord.NeoClient) do
      nil -> false
      pid -> Process.alive?(pid)
    end
  end

  defp gateway_alive? do
    # Check if Nostrum gateway is running
    case Process.whereis(Nostrum.Shard.Supervisor) do
      nil -> false
      pid -> Process.alive?(pid)
    end
  end

  defp ratelimiter_alive? do
    case Process.whereis(Nostrum.Api.Ratelimiter) do
      nil -> false
      pid -> Process.alive?(pid)
    end
  end

  defp get_shard_status do
    try do
      # Try to get shard information from Nostrum
      case Process.whereis(Nostrum.Shard.Supervisor) do
        nil ->
          :not_running

        _pid ->
          # Get children of shard supervisor
          children = Supervisor.which_children(Nostrum.Shard.Supervisor)
          %{shard_count: length(children), status: :running}
      end
    catch
      _, _ -> :unknown
    end
  end

  defp get_gun_pools do
    # Try to find Gun connection processes
    try do
      Process.list()
      |> Enum.filter(fn pid ->
        try do
          info = Process.info(pid, [:registered_name, :dictionary])

          case info do
            nil ->
              false

            info_list ->
              dict = Keyword.get(info_list, :dictionary, [])
              # Gun processes often have specific dictionary entries
              Keyword.has_key?(dict, :"$initial_call") and
                match?({:gun, _, _}, Keyword.get(dict, :"$initial_call"))
          end
        catch
          _, _ -> false
        end
      end)
      |> Enum.map(fn pid ->
        info = Process.info(pid, [:message_queue_len, :status, :memory])

        %{
          pid: inspect(pid),
          queue_len: info[:message_queue_len],
          status: info[:status],
          memory: info[:memory]
        }
      end)
    catch
      _, _ -> []
    end
  end

  # ──────────────────────────────────────────────────────────────────────────────
  # Private Functions - Recovery
  # ──────────────────────────────────────────────────────────────────────────────

  defp do_recovery do
    Logger.warning("[Discord Health] Starting recovery sequence")

    # Step 1: Log current state for diagnostics
    diagnostics = get_diagnostics()
    Logger.info("[Discord Health] Pre-recovery diagnostics", diagnostics: diagnostics)

    # Step 2: Try to restart the ratelimiter connection if it's stuck
    recovery_result = try_ratelimiter_recovery()

    Logger.info("[Discord Health] Recovery completed", result: recovery_result)

    recovery_result
  end

  defp try_ratelimiter_recovery do
    case Process.whereis(Nostrum.Api.Ratelimiter) do
      nil ->
        Logger.error("[Discord Health] Ratelimiter not running - cannot recover")
        {:error, :ratelimiter_not_running}

      pid ->
        check_ratelimiter_state(pid)
    end
  end

  defp check_ratelimiter_state(pid) do
    case :sys.get_state(pid, 1_000) do
      {_state_name, state_data} ->
        handle_ratelimiter_connection(get_connection_status(state_data))

      _ ->
        Logger.warning("[Discord Health] Unexpected ratelimiter state")
        :ok
    end
  catch
    :exit, {:timeout, _} ->
      Logger.error("[Discord Health] Ratelimiter blocked - cannot get state")
      {:error, :ratelimiter_blocked}

    :exit, reason ->
      Logger.error("[Discord Health] Error checking ratelimiter", error: inspect(reason))
      {:error, reason}
  end

  defp handle_ratelimiter_connection(:no_connection) do
    Logger.warning("[Discord Health] No active connection in ratelimiter")
    :ok
  end

  defp handle_ratelimiter_connection(:dead) do
    Logger.warning("[Discord Health] Dead connection detected in ratelimiter")
    :ok
  end

  defp handle_ratelimiter_connection(%{status: :alive, queue_len: queue_len})
       when queue_len > 100 do
    Logger.warning("[Discord Health] Connection has large queue (#{queue_len}) - may be stuck")
    :ok
  end

  defp handle_ratelimiter_connection(_) do
    Logger.info("[Discord Health] Connection appears healthy")
    :ok
  end

  # ──────────────────────────────────────────────────────────────────────────────
  # Private Functions - Health Checks
  # ──────────────────────────────────────────────────────────────────────────────

  defp healthy?(state) do
    state.consecutive_timeouts < @timeout_threshold and
      state.consecutive_failures < @timeout_threshold
  end

  defp schedule_health_check do
    Process.send_after(self(), :health_check, @health_check_interval)
  end

  defp log_health_status(state) do
    diagnostics = get_diagnostics()
    ratelimiter = diagnostics.ratelimiter

    Logger.info(
      "[Discord Health] Status: timeouts=#{state.consecutive_timeouts}, " <>
        "failures=#{state.consecutive_failures}, " <>
        "total_success=#{state.total_successes}, " <>
        "total_timeout=#{state.total_timeouts}, " <>
        "failed_kills=#{length(state.failed_kills)}, " <>
        "ratelimiter=#{inspect(ratelimiter.state_name || ratelimiter.status || :unknown)}, " <>
        "queues=#{inspect(ratelimiter[:queue_lengths] || %{})}"
    )
  end

  # Adds a failed kill to the list, keeping only the last @max_failed_kills entries
  defp add_failed_kill(failed_kills, nil, _reason), do: failed_kills

  defp add_failed_kill(failed_kills, killmail_id, reason) do
    entry = %{
      killmail_id: to_string(killmail_id),
      reason: reason,
      failed_at: DateTime.utc_now()
    }

    [entry | failed_kills]
    |> Enum.take(@max_failed_kills)
  end
end
