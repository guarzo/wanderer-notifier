defmodule WandererNotifier.Processing.Killmail.Processor do
  @moduledoc """
  Processes killmail data from various sources.
  This module is responsible for analyzing killmail data, determining what actions
  to take, and orchestrating notifications as needed.

  This is the main entry point for killmail processing and coordinates between specialized modules:
  - Stats: Tracks and reports statistics about processed kills
  - Enrichment: Adds additional data to killmails
  - Notification: Handles notification decisions and dispatch
  - Cache: Manages caching of killmail data
  """

  alias WandererNotifier.Core.Stats
  alias WandererNotifier.Killmail.Context
  alias WandererNotifier.Killmail.Pipeline
  alias WandererNotifier.Logger.Logger, as: AppLogger
  alias WandererNotifier.Processing.Killmail.{Cache, Notification}
  alias WandererNotifier.Killmail.ZKillClient

  @behaviour WandererNotifier.Processing.Killmail.ProcessorBehaviour
  @max_retries 3
  @retry_backoff_ms 1000

  @impl WandererNotifier.Processing.Killmail.ProcessorBehaviour
  def init do
    # Core Stats is started by the application supervisor
    Cache.init()
  end

  @doc """
  Schedules periodic tasks such as stats logging.
  """
  def schedule_tasks do
    # Core Stats handles its own scheduling
    :ok
  end

  @doc """
  Logs kill statistics.
  Called periodically to report stats about processed kills.
  """
  def log_stats do
    Stats.print_summary()
  end

  @doc """
  Processes a websocket message from zKillboard.
  Returns an updated state that tracks processed kills.
  """
  def process_zkill_message(message, state) do
    case Jason.decode(message) do
      {:ok, %{"killmail_id" => _} = killmail} ->
        _kill_id = get_killmail_id(killmail)
        handle_killmail(killmail, state)

      {:ok, payload} ->
        # Log when we receive a message without a killmail_id
        AppLogger.websocket_debug("Received message without killmail_id", %{
          message_type: "unknown",
          payload_keys: Map.keys(payload)
        })

        state

      {:error, reason} ->
        AppLogger.websocket_error("Failed to decode WebSocket message", %{
          error: inspect(reason),
          message_sample: String.slice(message, 0, 100)
        })

        state
    end
  rescue
    error ->
      stacktrace = __STACKTRACE__

      AppLogger.websocket_error("Exception while processing WebSocket message", %{
        error: Exception.message(error),
        stacktrace: Exception.format_stacktrace(stacktrace),
        message_sample: String.slice(message, 0, 100)
      })

      state
  end

  # Handle a killmail from the websocket
  defp handle_killmail(
         %{"killmail_id" => kill_id} = killmail,
         %{processed_kill_ids: processed_kills} = state
       ) do
    if Map.has_key?(processed_kills, kill_id) do
      state
    else
      process_new_killmail(killmail, kill_id, state)
    end
  end

  defp handle_killmail(_killmail, :processed) do
    # If the state is :processed, we can just return it
    :processed
  end

  defp process_new_killmail(_unused_killmail, kill_id, state) do
    # Check cache first
    case Cache.get_kill(kill_id) do
      {:ok, zkb_data} ->
        # Use cached data
        AppLogger.processor_debug("Using cached killmail data", %{
          kill_id: kill_id,
          source: :cache
        })

        process_zkill_data(zkb_data, kill_id, state)

      _ ->
        # Fetch from ZKillboard with retry logic
        fetch_and_process_zkill_data(kill_id, state)
    end
  end

  defp fetch_and_process_zkill_data(kill_id, state, retry_count \\ 0) do
    case ZKillClient.get_single_killmail(kill_id) do
      {:ok, zkb_data} ->
        # Cache the result
        Cache.cache_kill(kill_id, zkb_data)
        process_zkill_data(zkb_data, kill_id, state)

      error when retry_count < @max_retries ->
        # Log and retry
        AppLogger.processor_warn("Retrying killmail fetch", %{
          kill_id: kill_id,
          retry: retry_count + 1,
          max_retries: @max_retries,
          error: inspect(error),
          backoff_ms: (@retry_backoff_ms * :math.pow(2, retry_count)) |> round()
        })

        # Exponential backoff
        backoff = (@retry_backoff_ms * :math.pow(2, retry_count)) |> round()
        :timer.sleep(backoff)
        fetch_and_process_zkill_data(kill_id, state, retry_count + 1)

      error ->
        # Max retries reached, log error and return unchanged state
        log_zkill_error(kill_id, error)
        state
    end
  end

  defp process_zkill_data(kill_data, kill_id, state) do
    # Check if the kill_id from parameters matches the one in data for validation
    kill_id_from_data = Map.get(kill_data, "killmail_id")

    # Log if there's a mismatch between the provided kill_id and the one in the data
    if kill_id_from_data && kill_id_from_data != kill_id do
      AppLogger.processor_warn("Kill ID mismatch", %{
        parameter_kill_id: kill_id,
        data_kill_id: kill_id_from_data
      })
    end

    # Check if we've already processed this kill
    if Map.get(state.processed_kill_ids, kill_id) do
      AppLogger.processor_debug("Skipping already processed kill", %{
        kill_id: kill_id
      })

      # Return state unchanged
      state
    else
      # Create context for processing
      # Don't use kill_id as character_id as that causes errors
      # Instead, set character_id to nil for websocket kills
      ctx = create_realtime_context(nil, "Websocket kill #{kill_id}")

      # Process the kill
      case process_single_kill(kill_data, ctx) do
        {:ok, _result} ->
          # Update state with processed kill
          Map.update!(state, :processed_kill_ids, &Map.put(&1, kill_id, true))

        _ ->
          # Just return state on any error
          state
      end
    end
  end

  defp create_realtime_context(character_id, character_name) do
    %Context{
      mode: %{mode: :realtime},
      character_id: character_id,
      character_name: character_name,
      source: :zkill_websocket
    }
  end

  defp log_zkill_error(kill_id, error) do
    AppLogger.websocket_error("Failed to fetch killmail from ZKill", %{
      kill_id: kill_id,
      error: inspect(error),
      max_retries_reached: true
    })
  end

  # Helper functions

  defp get_killmail_id(killmail) do
    case Map.get(killmail, "killmail_id") do
      id when is_integer(id) -> id
      id when is_binary(id) -> String.to_integer(id)
      _ -> nil
    end
  end

  @impl WandererNotifier.Processing.Killmail.ProcessorBehaviour
  def get_recent_kills do
    Cache.get_recent_kills()
  end

  @doc """
  Sends a test kill notification using recent data.
  """
  def send_test_kill_notification do
    Notification.send_test()
  end

  # Private functions

  defp handle_tq_status(%{"tqStatus" => %{"players" => player_count, "vip" => vip}}) do
    # Store in process dictionary for now, we could use the state or a separate GenServer later
    timestamp = :os.system_time(:second)

    AppLogger.websocket_debug("Received TQ status update", %{
      player_count: player_count,
      vip: vip,
      timestamp: timestamp
    })

    Process.put(:tq_status, %{
      player_count: player_count,
      vip: vip,
      timestamp: timestamp
    })
  end

  defp handle_tq_status(status) do
    AppLogger.websocket_error("Received malformed TQ status message", %{
      status_keys: Map.keys(status),
      status_type: inspect(status)
    })
  end

  @doc """
  Handles an incoming WebSocket message.
  """
  def handle_message(%{"action" => "killmail"} = message, state) do
    {:ok, process_zkill_message(message, state)}
  end

  def handle_message(%{"action" => "tqStatus"} = message, state) do
    handle_tq_status(message)
    {:ok, state}
  end

  def handle_message(message, state) do
    AppLogger.websocket_error("Received unknown message type", %{
      message_keys: Map.keys(message),
      sample_data: inspect(message) |> String.slice(0, 100)
    })

    {:ok, state}
  end

  @doc """
  Process a single killmail using the provided context.

  Returns:
  - :processed - when the kill was successfully processed
  - :skipped - when the kill was skipped (e.g., already exists)
  - {:error, reason} - when an error occurred during processing
  """
  def process_single_kill(kill, ctx) do
    kill_id = kill["killmail_id"]
    hash = get_in(kill, ["zkb", "hash"])

    AppLogger.kill_debug("Processing kill", %{
      kill_id: kill_id,
      hash: hash,
      character_id: ctx.character_id,
      character_name: ctx.character_name,
      batch_id: ctx.batch_id,
      processing_mode: ctx.mode && ctx.mode.mode
    })

    case Pipeline.process_killmail(kill, ctx) do
      {:ok, _} ->
        AppLogger.kill_debug("Kill successfully processed", %{
          kill_id: kill_id,
          character_id: ctx.character_id,
          batch_id: ctx.batch_id
        })

        :processed

      {:error, :skipped} ->
        AppLogger.kill_debug("Kill processing skipped", %{
          kill_id: kill_id,
          character_id: ctx.character_id,
          batch_id: ctx.batch_id
        })

        :skipped

      error ->
        AppLogger.kill_error("Kill processing failed", %{
          kill_id: kill_id,
          character_id: ctx.character_id,
          batch_id: ctx.batch_id,
          error: inspect(error)
        })

        error
    end
  end
end
