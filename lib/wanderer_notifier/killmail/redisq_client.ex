defmodule WandererNotifier.Killmail.RedisQClient do
  @moduledoc """
  RedisQ client for receiving killmails from zKillboard.
  Polls the RedisQ endpoint and processes incoming killmails.
  """

  use GenServer
  alias WandererNotifier.Telemetry
  alias WandererNotifier.Logger.Logger, as: AppLogger
  alias WandererNotifier.Http.Utils.RateLimiter
  alias WandererNotifier.Constants
  alias WandererNotifier.Killmail.Schema
  alias WandererNotifier.Utils.TimeUtils
  alias WandererNotifier.Http.ResponseHandler

  # Internal state struct
  defmodule State do
    @moduledoc false
    defstruct [
      :parent,
      :parent_monitor_ref,
      :queue_id,
      :poll_interval,
      :poll_timer,
      :url,
      :startup_time,
      :ttw,
      :retry_count,
      :last_error,
      :backoff_timer,
      # Track consecutive timeouts
      :consecutive_timeouts,
      # Track when we last got data successfully
      :last_successful_poll
    ]
  end

  @max_retries 3
  @timeout_threshold 5

  # Cancel existing timer if it exists
  defp cancel_timer(nil), do: :ok
  defp cancel_timer(timer_ref), do: Process.cancel_timer(timer_ref)

  @doc """
  Starts the RedisQ client.

  ## Options
    * `:queue_id` — unique identifier for this client (required)
    * `:parent` — PID to which raw messages (`{:zkill_message, raw}`) are sent
    * `:poll_interval` — time between polls in milliseconds (default: 5000)
    * `:url` — RedisQ endpoint URL (default: https://zkillredisq.stream/listen.php)
    * `:ttw` — time to wait for new killmails in seconds (default: 3, min: 1, max: 10)
    * `:timeout_buffer` — additional timeout buffer in milliseconds (default: 5000)
  """
  def start_link(opts) when is_list(opts) do
    GenServer.start_link(__MODULE__, opts)
  end

  @impl true
  def init(opts) do
    queue_id = Keyword.get(opts, :queue_id)
    parent = Keyword.get(opts, :parent)
    poll_interval = Keyword.get(opts, :poll_interval, 5000)
    url = Keyword.get(opts, :url)
    ttw = Keyword.get(opts, :ttw, 3) |> min(10) |> max(1)

    # Monitor the parent process
    parent_monitor_ref = Process.monitor(parent)

    # Initialize state
    state = %State{
      queue_id: queue_id,
      parent: parent,
      parent_monitor_ref: parent_monitor_ref,
      poll_interval: poll_interval,
      url: url,
      startup_time: TimeUtils.now(),
      ttw: ttw,
      retry_count: 0,
      last_error: nil,
      backoff_timer: nil,
      consecutive_timeouts: 0,
      last_successful_poll: TimeUtils.now()
    }

    # Log initialization
    AppLogger.processor_info("🚀 RedisQ client initialized",
      queue_id: queue_id,
      url: url,
      ttw: ttw,
      poll_interval: poll_interval
    )

    # Update connection stats
    Telemetry.redisq_status_changed(%{
      connected: false,
      connecting: true,
      startup_time: state.startup_time,
      url: url
    })

    # Schedule first poll immediately
    timer_ref = Process.send_after(self(), :poll, 100)
    state = %{state | poll_timer: timer_ref}

    {:ok, state}
  end

  @impl true
  def handle_info({:DOWN, ref, :process, pid, reason}, state) do
    if ref == state.parent_monitor_ref do
      AppLogger.api_error("Parent process died, stopping RedisQ client", reason: inspect(reason))
      {:stop, :parent_died, state}
    else
      # This is a task failure, log it but don't crash the client
      AppLogger.processor_debug("Background task failed",
        ref: inspect(ref),
        pid: inspect(pid),
        reason: inspect(reason)
      )

      {:noreply, state}
    end
  end

  @impl true
  def handle_info(:poll, state) do
    # Check if parent is still alive before fetching
    if Process.alive?(state.parent) do
      handle_fetch_and_schedule(state)
    else
      AppLogger.api_error("Parent process is not alive, stopping RedisQ client")
      {:stop, :parent_not_alive, state}
    end
  end

  @impl true
  def handle_info(:stop, state) do
    # Cancel any active timers
    cancel_timer(state.poll_timer)
    cancel_timer(state.backoff_timer)

    # Update connection stats
    Telemetry.redisq_status_changed(%{
      connected: false,
      connecting: false,
      last_disconnect: TimeUtils.now()
    })

    {:stop, :normal, state}
  end

  # Handle task completion messages
  def handle_info({ref, _result}, state) when is_reference(ref) do
    # Task completed successfully, dereference it
    Process.demonitor(ref, [:flush])
    {:noreply, state}
  end

  # Handle the fetch operation and schedule next poll
  defp handle_fetch_and_schedule(state) do
    case fetch_killmail(state) do
      {:ok, data} ->
        handle_successful_fetch(state, data)

      {:error, :no_killmail} ->
        handle_no_killmail(state)

      {:error, :timeout} ->
        handle_timeout_retry(state)

      {:error, reason} ->
        handle_fetch_error(state, reason)
    end
  end

  # Handle successful killmail fetch
  defp handle_successful_fetch(state, data) do
    # Reset retry count and timeout counters on success
    new_state = %{
      state
      | retry_count: 0,
        last_error: nil,
        consecutive_timeouts: 0,
        last_successful_poll: TimeUtils.now()
    }

    # Update connection stats
    Telemetry.redisq_status_changed(%{
      connected: true,
      connecting: false,
      last_message: TimeUtils.now()
    })

    # Track killmail received
    # Handle both killmail_id and killID formats
    kill_id =
      Map.get(data, "killmail_id") || Map.get(data, "killID") ||
        get_in(data, ["killmail", "killmail_id"]) ||
        get_in(data, Schema.package_killmail_id_path())

    Telemetry.killmail_received(kill_id)

    # Log the received killmail
    system_id =
      get_in(data, ["killmail", "solar_system_id"]) ||
        get_in(data, ["solar_system_id"])

    # Spawn supervised async task to log with system name to avoid blocking the GenServer
    _task =
      Task.Supervisor.async_nolink(WandererNotifier.TaskSupervisor, fn ->
        system_name = get_system_name(system_id)

        AppLogger.processor_info(
          "💀 📥 Killmail #{kill_id} | #{system_name} | Received from RedisQ"
        )
      end)

    # The task is supervised and errors will be logged by the TaskSupervisor

    # Send to parent
    send(state.parent, {:zkill_message, data})

    # Immediate retry when killmail received (hot polling during activity)
    AppLogger.processor_debug(
      "Scheduling immediate poll for hot polling during activity",
      queue_id: state.queue_id
    )

    schedule_immediate_poll(new_state)
  end

  # Handle case when no killmail is available
  defp handle_no_killmail(state) do
    # No killmail available, just update connection stats
    Telemetry.redisq_status_changed(%{
      connected: true,
      connecting: false
    })

    # Reset retry count and timeout counters on successful connection (even if no killmail)
    new_state = %{
      state
      | retry_count: 0,
        last_error: nil,
        consecutive_timeouts: 0,
        last_successful_poll: TimeUtils.now()
    }

    # Regular polling interval when no activity
    # Only log occasionally to avoid spam
    if rem(System.system_time(:second), 60) < 5 do
      AppLogger.processor_debug("RedisQ poll complete - no new killmails")
    end

    schedule_next_poll(new_state)
  end

  # Handle non-timeout errors
  defp handle_fetch_error(state, reason) do
    # Update connection stats
    Telemetry.redisq_status_changed(%{
      connected: false,
      connecting: false,
      last_error: reason
    })

    AppLogger.processor_error(
      "Error fetching killmail",
      error: inspect(reason),
      queue_id: state.queue_id
    )

    # For non-timeout errors, continue with regular polling
    new_state = %{state | last_error: reason}

    AppLogger.api_debug(
      "Continuing with regular polling interval of #{state.poll_interval}ms after error",
      queue_id: state.queue_id
    )

    schedule_next_poll(new_state)
  end

  @impl true
  def terminate(reason, state) do
    # Clean up timers on process termination
    cancel_timer(state.poll_timer)
    cancel_timer(state.backoff_timer)

    # Update connection stats
    Telemetry.redisq_status_changed(%{
      connected: false,
      connecting: false,
      last_disconnect: TimeUtils.now()
    })

    AppLogger.api_debug("RedisQ client terminated",
      reason: inspect(reason),
      queue_id: state.queue_id,
      uptime_seconds: TimeUtils.elapsed_seconds(state.startup_time)
    )

    :ok
  end

  # Helper to fetch killmail data
  defp fetch_killmail(state) do
    url = "#{state.url}?queueID=#{state.queue_id}&ttw=#{state.ttw}"
    http_client = get_http_client()
    opts = build_http_options(state)

    AppLogger.processor_debug("🔄 Polling RedisQ for killmails...",
      queue_id: state.queue_id,
      ttw: state.ttw
    )

    result =
      RateLimiter.run(
        fn ->
          case http_client.get(url, [], opts) do
            {:ok, response} -> {:ok, response}
            {:error, reason} -> {:error, reason}
            # Wrap bare responses
            response -> {:ok, response}
          end
        end,
        context: "RedisQ request",
        max_retries: @max_retries,
        base_backoff: Constants.redisq_base_backoff()
      )

    case result do
      {:ok, response} -> handle_http_response({:ok, response}, state)
      {:error, reason} -> handle_http_response({:error, reason}, state)
    end
  end

  # Get the configured HTTP client
  defp get_http_client, do: WandererNotifier.Core.Dependencies.http_client()

  # Build HTTP request options based on state
  defp build_http_options(state) do
    # Calculate timeouts based on the TTW parameter
    # RedisQ endpoint holds connection open for up to TTW seconds
    # We need generous buffers to account for network latency and server processing
    # Get configurable timeout buffer or use default
    timeout_buffer = Application.get_env(:wanderer_notifier, :redisq_timeout_buffer, 5000)
    total_timeout = state.ttw * 1000 + timeout_buffer

    [
      # Timeout for the entire request (TTW + configurable buffer)
      timeout: total_timeout,
      # Timeout for receiving data once connected (same as total)
      recv_timeout: total_timeout,
      # Connection timeout - keep reasonable to detect network issues
      connect_timeout: Application.get_env(:wanderer_notifier, :redisq_connect_timeout, 15_000),
      # Pool timeout to prevent connection pool exhaustion
      pool_timeout: Application.get_env(:wanderer_notifier, :redisq_pool_timeout, 5000)
    ]
  end

  # Handle HTTP response and decode body
  defp handle_http_response(response, state) do
    # Use ResponseHandler for basic response handling, but maintain RedisQ-specific logic
    case ResponseHandler.handle_response(response,
           success_codes: [200],
           error_format: :string,
           log_context: %{client: "RedisQ", queue_id: state.queue_id}
         ) do
      {:ok, body} ->
        handle_successful_response(body)

      {:error, :timeout} ->
        handle_timeout_error(state)

      {:error, :connect_timeout} ->
        handle_connect_timeout_error(state)

      {:error, reason} = error ->
        handle_general_error(reason, state)
        error
    end
  end

  defp handle_successful_response(body) do
    case decode_response_body(body) do
      {:ok, %{"package" => nil}} ->
        {:error, :no_killmail}

      {:ok, %{"package" => data}} ->
        {:ok, data}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp handle_timeout_error(state) do
    log_level = if state.consecutive_timeouts > @timeout_threshold, do: :debug, else: :warn
    log_timeout_message(log_level, state)
    {:error, :timeout}
  end

  defp log_timeout_message(:debug, state) do
    AppLogger.api_debug(
      "RedisQ timeout (frequent pattern)",
      queue_id: state.queue_id,
      consecutive_timeouts: state.consecutive_timeouts
    )
  end

  defp log_timeout_message(:warn, state) do
    AppLogger.api_warn(
      "RedisQ timeout (#{state.consecutive_timeouts + 1} consecutive)",
      queue_id: state.queue_id
    )
  end

  defp handle_connect_timeout_error(state) do
    AppLogger.api_error("RedisQ Client: Connection timed out for queue_id=#{state.queue_id}")
    {:error, :connect_timeout}
  end

  defp handle_general_error(reason, state) do
    AppLogger.api_error(
      "RedisQ Client: Request failed for queue_id=#{state.queue_id}: #{inspect(reason)}"
    )
  end

  # Handle response body - ResponseHandler already decodes JSON, so we just need to wrap maps
  # This function exists to handle edge cases where the body might still be binary
  defp decode_response_body(body) when is_binary(body) do
    # This should rarely happen as ResponseHandler decodes JSON
    # But we keep it for safety and backward compatibility
    Jason.decode(body)
  end

  defp decode_response_body(body) when is_map(body) do
    # Most common case - body is already decoded by ResponseHandler
    {:ok, body}
  end

  # Schedule an immediate poll (for when killmail activity is detected)
  defp schedule_immediate_poll(state) do
    # Cancel existing timer to prevent leaks
    cancel_timer(state.poll_timer)

    timer_ref = Process.send_after(self(), :poll, 0)
    new_state = %{state | poll_timer: timer_ref, backoff_timer: nil}
    {:noreply, new_state}
  end

  # Schedule the next regular poll
  defp schedule_next_poll(state) do
    # Cancel existing timer to prevent leaks
    cancel_timer(state.poll_timer)

    timer_ref = Process.send_after(self(), :poll, state.poll_interval)
    new_state = %{state | poll_timer: timer_ref, backoff_timer: nil}
    {:noreply, new_state}
  end

  # Handle timeout errors with retry logic
  defp handle_timeout_retry(state) do
    new_retry_count = state.retry_count + 1
    new_consecutive_timeouts = state.consecutive_timeouts + 1

    new_state = %{
      state
      | retry_count: new_retry_count,
        last_error: :timeout,
        consecutive_timeouts: new_consecutive_timeouts
    }

    # If we've had many consecutive timeouts, treat this as normal behavior
    # and don't increment retry count as aggressively
    if new_consecutive_timeouts > @timeout_threshold do
      handle_frequent_timeouts(new_state)
    else
      if new_retry_count <= @max_retries do
        handle_retry_with_backoff(new_state)
      else
        handle_max_retries_exceeded(new_state)
      end
    end
  end

  defp handle_retry_with_backoff(state) do
    # Use exponential backoff similar to RateLimiter
    base_backoff = Constants.redisq_base_backoff()
    max_backoff = Constants.max_backoff()

    # Calculate exponential backoff: base * 2^(attempt - 1)
    exponential = base_backoff * :math.pow(2, state.retry_count - 1)
    backoff = min(exponential, max_backoff) |> round()

    AppLogger.api_info("Retrying RedisQ request",
      attempt: state.retry_count,
      backoff: backoff,
      reason: inspect(state.last_error)
    )

    # Cancel existing timer to prevent leaks
    cancel_timer(state.poll_timer)

    timer_ref = Process.send_after(self(), :poll, backoff)
    new_state = %{state | poll_timer: timer_ref, backoff_timer: nil}
    {:noreply, new_state}
  end

  defp handle_max_retries_exceeded(state) do
    # Max retries exceeded, fall back to regular polling
    AppLogger.api_error(
      "RedisQ max retries exceeded, falling back to regular polling interval of #{state.poll_interval}ms"
    )

    Telemetry.redisq_status_changed(%{
      connected: false,
      connecting: false,
      last_error: :max_retries_exceeded
    })

    # Reset retry count and go back to regular polling
    new_state = %{state | retry_count: 0}
    schedule_next_poll(new_state)
  end

  # Handle frequent timeout scenario - treat as normal long-polling behavior
  defp handle_frequent_timeouts(state) do
    AppLogger.api_debug(
      "Frequent timeouts detected (#{state.consecutive_timeouts} consecutive), " <>
        "treating as normal long-polling behavior",
      queue_id: state.queue_id
    )

    # Update connection stats but don't mark as error
    Telemetry.redisq_status_changed(%{
      # Still consider connected since timeouts are expected
      connected: true,
      connecting: false,
      # Don't treat frequent timeouts as errors
      last_error: nil
    })

    # Reset retry count since frequent timeouts are expected behavior
    new_state = %{state | retry_count: 0}

    # Use regular polling interval instead of backoff
    schedule_next_poll(new_state)
  end

  defp get_system_name(system_id) do
    WandererNotifier.Killmail.Cache.get_system_name(system_id)
  end
end
