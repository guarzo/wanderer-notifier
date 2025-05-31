defmodule WandererNotifier.Killmail.RedisQClient do
  @moduledoc """
  RedisQ client for receiving killmails from zKillboard.
  Polls the RedisQ endpoint and processes incoming killmails.
  """

  use GenServer
  alias WandererNotifier.Core.Stats
  alias WandererNotifier.Logger.Logger, as: AppLogger

  # Internal state struct
  defmodule State do
    @moduledoc false
    defstruct [
      :parent,
      :queue_id,
      :poll_interval,
      :poll_timer,
      :url,
      :startup_time,
      :ttw,
      :retry_count,
      :last_error,
      :backoff_timer
    ]
  end

  @max_retries 3
  # 2 seconds base backoff
  @base_backoff 2000
  # Maximum backoff of 30 seconds
  @max_backoff 30_000

  # Add jitter to prevent thundering herd
  defp calculate_backoff(retry_count) do
    base = @base_backoff * :math.pow(2, retry_count - 1)
    # Add up to 20% jitter
    jitter = :rand.uniform() * 0.2 * base
    # Cap at max backoff
    min(base + jitter, @max_backoff) |> round()
  end

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
    Process.monitor(parent)

    # Initialize state
    state = %State{
      queue_id: queue_id,
      parent: parent,
      poll_interval: poll_interval,
      url: url,
      startup_time: DateTime.utc_now(),
      ttw: ttw,
      retry_count: 0,
      last_error: nil,
      backoff_timer: nil
    }

    # Update connection stats
    Stats.update_redisq(%{
      connected: false,
      connecting: true,
      startup_time: state.startup_time,
      url: url
    })

    # Schedule first poll using the proper timer management
    timer_ref = Process.send_after(self(), :poll, poll_interval)
    state = %{state | poll_timer: timer_ref}

    {:ok, state}
  end

  @impl true
  def handle_info({:DOWN, _ref, :process, _pid, reason}, state) do
    AppLogger.api_error("Parent process died, stopping RedisQ client", reason: inspect(reason))
    {:stop, :parent_died, state}
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
    Stats.update_redisq(%{
      connected: false,
      connecting: false,
      last_disconnect: DateTime.utc_now()
    })

    {:stop, :normal, state}
  end

  # Handle the fetch operation and schedule next poll
  defp handle_fetch_and_schedule(state) do
    case fetch_killmail(state) do
      {:ok, data} ->
        handle_successful_fetch(state, data)

      {:error, :no_killmail} ->
        handle_no_killmail(state)

      {:error, :timeout} ->
        handle_timeout_error(state)

      {:error, reason} ->
        handle_fetch_error(state, reason)
    end
  end

  # Handle successful killmail fetch
  defp handle_successful_fetch(state, data) do
    # Reset retry count on success
    new_state = %{state | retry_count: 0, last_error: nil}

    # Update connection stats
    Stats.update_redisq(%{
      connected: true,
      connecting: false,
      last_message: DateTime.utc_now()
    })

    # Send to parent
    send(state.parent, {:zkill_message, data})

    # Immediate retry when killmail received (hot polling during activity)
    AppLogger.api_debug(
      "Killmail received, scheduling immediate poll for hot polling during activity",
      queue_id: state.queue_id
    )

    schedule_immediate_poll(new_state)
  end

  # Handle case when no killmail is available
  defp handle_no_killmail(state) do
    # No killmail available, just update connection stats
    Stats.update_redisq(%{
      connected: true,
      connecting: false
    })

    # Reset retry count on successful connection (even if no killmail)
    new_state = %{state | retry_count: 0, last_error: nil}
    # Regular polling interval when no activity
    AppLogger.api_debug("No killmail available, polling again in #{state.poll_interval}ms")
    schedule_next_poll(new_state)
  end

  # Handle non-timeout errors
  defp handle_fetch_error(state, reason) do
    # Update connection stats
    Stats.update_redisq(%{
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
    Stats.update_redisq(%{
      connected: false,
      connecting: false,
      last_disconnect: DateTime.utc_now()
    })

    AppLogger.api_debug("RedisQ client terminated",
      reason: inspect(reason),
      queue_id: state.queue_id,
      uptime_seconds: DateTime.diff(DateTime.utc_now(), state.startup_time)
    )

    :ok
  end

  # Helper to fetch killmail data
  defp fetch_killmail(state) do
    url = "#{state.url}?queueID=#{state.queue_id}&ttw=#{state.ttw}"
    http_client = get_http_client()
    opts = build_http_options(state)

    AppLogger.api_debug("RedisQ request starting",
      url: url,
      ttw: state.ttw,
      timeout: opts[:timeout],
      queue_id: state.queue_id
    )

    start_time = System.monotonic_time()

    http_client.get(url, [], opts)
    |> handle_http_response(state, start_time)
  end

  # Get the configured HTTP client
  defp get_http_client do
    Application.get_env(:wanderer_notifier, :http_client, WandererNotifier.HttpClient.Httpoison)
  end

  # Build HTTP request options based on state
  defp build_http_options(state) do
    # Calculate timeouts based on the TTW parameter
    # RedisQ endpoint holds connection open for up to TTW seconds
    # We need generous buffers to account for network latency and server processing
    buffer_time = 3000
    total_timeout = state.ttw * 1000 + buffer_time

    [
      # Timeout for the entire request (TTW + 3s buffer)
      timeout: total_timeout,
      # Timeout for receiving data once connected (same as total)
      recv_timeout: total_timeout,
      # Connection timeout - keep fast to detect network issues quickly
      connect_timeout: 10_000,
      # Pool timeout to prevent connection pool exhaustion
      pool_timeout: 3000
    ]
  end

  # Handle HTTP response and decode body
  defp handle_http_response({:ok, %{status_code: 200, body: body}}, _state, _start_time) do
    case decode_response_body(body) do
      {:ok, %{"package" => nil}} ->
        {:error, :no_killmail}

      {:ok, %{"package" => data}} ->
        {:ok, data}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp handle_http_response({:ok, %{status_code: status}}, state, start_time) do
    duration = System.monotonic_time() - start_time

    AppLogger.api_error(
      "RedisQ Client: Received error status #{status} after #{duration}μs for queue_id=#{state.queue_id}"
    )

    {:error, "HTTP error: #{status}"}
  end

  defp handle_http_response({:error, :timeout}, state, start_time) do
    duration = System.monotonic_time() - start_time

    AppLogger.api_error(
      "RedisQ Client: Request timed out after #{duration}μs for queue_id=#{state.queue_id}"
    )

    {:error, :timeout}
  end

  defp handle_http_response({:error, :connect_timeout}, state, start_time) do
    duration = System.monotonic_time() - start_time

    AppLogger.api_error(
      "RedisQ Client: Connection timed out after #{duration}μs for queue_id=#{state.queue_id}"
    )

    {:error, :connect_timeout}
  end

  defp handle_http_response({:error, reason}, state, start_time) do
    duration = System.monotonic_time() - start_time

    AppLogger.api_error(
      "RedisQ Client: Request failed after #{duration}μs for queue_id=#{state.queue_id}: #{inspect(reason)}"
    )

    {:error, reason}
  end

  # Handle response body decoding (may already be decoded by HTTP client)
  defp decode_response_body(body) when is_binary(body) do
    Jason.decode(body)
  end

  defp decode_response_body(body) when is_map(body) do
    {:ok, body}
  end

  # Schedule an immediate poll (for when killmail activity is detected)
  defp schedule_immediate_poll(state) do
    timer_ref = Process.send_after(self(), :poll, 0)
    new_state = %{state | poll_timer: timer_ref, backoff_timer: nil}
    {:noreply, new_state}
  end

  # Schedule the next regular poll
  defp schedule_next_poll(state) do
    timer_ref = Process.send_after(self(), :poll, state.poll_interval)
    new_state = %{state | poll_timer: timer_ref, backoff_timer: nil}
    {:noreply, new_state}
  end

  # Schedule a backoff poll (after timeouts)
  defp schedule_backoff_poll(state, backoff_time) do
    timer_ref = Process.send_after(self(), :poll, backoff_time)
    new_state = %{state | backoff_timer: timer_ref, poll_timer: nil}
    {:noreply, new_state}
  end

  # Handle timeout errors with retry logic
  defp handle_timeout_error(state) do
    new_retry_count = state.retry_count + 1
    new_state = %{state | retry_count: new_retry_count, last_error: :timeout}

    if new_retry_count <= @max_retries do
      handle_retry_attempt(new_state, new_retry_count)
    else
      handle_max_retries_exceeded(new_state)
    end
  end

  defp handle_retry_attempt(state, retry_count) do
    backoff = calculate_backoff(retry_count)

    log_retry_attempt(retry_count, backoff)

    # Update connection stats for timeout
    Stats.update_redisq(%{
      connected: false,
      connecting: true,
      last_error: :timeout
    })

    # Schedule backoff poll
    schedule_backoff_poll(state, backoff)
  end

  defp handle_max_retries_exceeded(state) do
    # Max retries exceeded, fall back to regular polling
    AppLogger.api_error(
      "RedisQ max retries exceeded, falling back to regular polling interval of #{state.poll_interval}ms"
    )

    Stats.update_redisq(%{
      connected: false,
      connecting: false,
      last_error: :max_retries_exceeded
    })

    # Reset retry count and go back to regular polling
    new_state = %{state | retry_count: 0}
    schedule_next_poll(new_state)
  end

  defp log_retry_attempt(retry_count, backoff) do
    if retry_count < @max_retries do
      AppLogger.api_debug(
        "RedisQ request timed out, retrying in #{backoff}ms (attempt #{retry_count}/#{@max_retries})"
      )
    else
      AppLogger.api_warn(
        "RedisQ request timed out, retrying in #{backoff}ms (attempt #{retry_count}/#{@max_retries})"
      )
    end
  end
end
