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
      :last_error
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

  @doc """
  Starts the RedisQ client.

  ## Options
    * `:queue_id` — unique identifier for this client (required)
    * `:parent` — PID to which raw messages (`{:zkill_message, raw}`) are sent
    * `:poll_interval` — time between polls in milliseconds (default: 1000)
    * `:url` — RedisQ endpoint URL (default: https://zkillredisq.stream/listen.php)
    * `:ttw` — time to wait for new killmails in seconds (default: 5, min: 1, max: 10)
  """
  def start_link(opts) when is_list(opts) do
    GenServer.start_link(__MODULE__, opts)
  end

  @impl true
  def init(opts) do
    queue_id = Keyword.get(opts, :queue_id)
    parent = Keyword.get(opts, :parent)
    poll_interval = Keyword.get(opts, :poll_interval, 1000)
    url = Keyword.get(opts, :url)
    ttw = Keyword.get(opts, :ttw, 5) |> min(10) |> max(1)

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
      last_error: nil
    }

    # Update connection stats
    Stats.update_redisq(%{
      connected: false,
      connecting: true,
      startup_time: state.startup_time,
      url: url
    })

    # Schedule first poll
    Process.send_after(self(), :poll, poll_interval)

    {:ok, state}
  end

  @impl true
  def handle_info({:DOWN, _ref, :process, _pid, reason}, state) do
    AppLogger.api_error("Parent process died, stopping RedisQ client", reason: inspect(reason))
    {:stop, :parent_died, state}
  end

  @impl true
  def handle_info(:poll, state) do
    # Schedule next poll
    Process.send_after(self(), :poll, state.poll_interval)

    # Check if parent is still alive before fetching
    if Process.alive?(state.parent) do
      # Fetch killmail data
      case fetch_killmail(state) do
        {:ok, data} ->
          # Reset retry count on success
          state = %{state | retry_count: 0, last_error: nil}

          # Update connection stats
          Stats.update_redisq(%{
            connected: true,
            connecting: false,
            last_message: DateTime.utc_now()
          })

          # Send to parent
          send(state.parent, {:zkill_message, data})

        {:error, :no_killmail} ->
          # No killmail available, just update connection stats
          Stats.update_redisq(%{
            connected: true,
            connecting: false
          })

        {:error, :timeout} ->
          new_retry_count = state.retry_count + 1
          backoff = calculate_backoff(new_retry_count)

          if new_retry_count < @max_retries do
            AppLogger.api_debug(
              "RedisQ request timed out, retrying in #{backoff}ms (attempt #{new_retry_count}/#{@max_retries})"
            )
          else
            AppLogger.api_warn(
              "RedisQ request timed out, retrying in #{backoff}ms (attempt #{new_retry_count}/#{@max_retries})"
            )
          end

          Process.send_after(self(), :poll, backoff)
          new_state = %{state | retry_count: new_retry_count, last_error: :timeout}
          {:noreply, new_state}

        {:error, reason} ->
          # Other error occurred, update connection stats
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
      end
    else
      AppLogger.api_error("Parent process is not alive, stopping RedisQ client")
      {:stop, :parent_not_alive, state}
    end

    {:noreply, state}
  end

  @impl true
  def handle_info(:stop, state) do
    # Update connection stats
    Stats.update_redisq(%{
      connected: false,
      connecting: false,
      last_disconnect: DateTime.utc_now()
    })

    {:stop, :normal, state}
  end

  # Helper to fetch killmail data
  defp fetch_killmail(state) do
    url = "#{state.url}?queueID=#{state.queue_id}&ttw=#{state.ttw}"

    # Add more generous buffer time (2 seconds instead of 1)
    buffer_time = 2000

    opts = [
      # Add buffer time to both timeout and recv_timeout
      timeout: state.ttw * 1000 + buffer_time,
      recv_timeout: state.ttw * 1000 + buffer_time,
      # Add connection timeout to fail fast if connection can't be established
      connect_timeout: 5000,
      # Add pool timeout to prevent connection pool exhaustion
      pool_timeout: 5000
    ]

    AppLogger.api_info(
      "RedisQ Client: Starting poll for killmails with queue_id=#{state.queue_id} ttw=#{state.ttw}s retry=#{state.retry_count}"
    )

    start_time = System.monotonic_time()

    case HTTPoison.get(url, [], opts) do
      {:ok, %{status_code: 200, body: body}} ->
        duration = System.monotonic_time() - start_time

        AppLogger.api_info(
          "RedisQ Client: Received response in #{duration}μs for queue_id=#{state.queue_id}"
        )

        case Jason.decode(body) do
          {:ok, %{"package" => nil}} ->
            AppLogger.api_info("RedisQ Client: No killmail in response")
            {:error, :no_killmail}

          {:ok, %{"package" => data}} ->
            AppLogger.api_info("RedisQ Client: Found killmail in response #{data["killID"]}")
            {:ok, data}

          {:error, reason} ->
            AppLogger.api_error(
              "RedisQ Client: Failed to decode response for queue_id=#{state.queue_id}: #{inspect(reason)}"
            )

            {:error, reason}
        end

      {:ok, %{status_code: status}} ->
        duration = System.monotonic_time() - start_time

        AppLogger.api_error(
          "RedisQ Client: Received error status #{status} after #{duration}μs for queue_id=#{state.queue_id}"
        )

        {:error, "HTTP error: #{status}"}

      {:error, %{reason: :timeout}} ->
        duration = System.monotonic_time() - start_time

        AppLogger.api_error(
          "RedisQ Client: Request timed out after #{duration}μs for queue_id=#{state.queue_id}"
        )

        {:error, :timeout}

      {:error, %{reason: :connect_timeout}} ->
        duration = System.monotonic_time() - start_time

        AppLogger.api_error(
          "RedisQ Client: Connection timed out after #{duration}μs for queue_id=#{state.queue_id}"
        )

        {:error, :connect_timeout}

      {:error, reason} ->
        duration = System.monotonic_time() - start_time

        AppLogger.api_error(
          "RedisQ Client: Request failed after #{duration}μs for queue_id=#{state.queue_id}: #{inspect(reason)}"
        )

        {:error, reason}
    end
  end
end
