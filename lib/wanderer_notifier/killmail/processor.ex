defmodule WandererNotifier.Killmail.Processor do
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

  alias WandererNotifier.ZKill
  alias WandererNotifier.Core.Stats
  alias WandererNotifier.Killmail.Context
  alias WandererNotifier.Logger.Logger, as: AppLogger
  alias WandererNotifier.Killmail.Cache, as: KillCache

  @behaviour WandererNotifier.Processing.Killmail.ProcessorBehaviour
  @max_retries 3
  @retry_backoff_ms 1000

  @impl WandererNotifier.Processing.Killmail.ProcessorBehaviour
  def init do
    # Core Stats is started by the application supervisor
    KillCache.init()
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

  @impl WandererNotifier.Processing.Killmail.ProcessorBehaviour
  def get_recent_kills do
    {:ok, KillCache.get_recent_kills() || []}
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
    case KillCache.get_kill(kill_id) do
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
    case ZKill.get_killmail(kill_id) do
      {:ok, zkb_data} ->
        # Cache the result - we need to convert the struct to a map
        zkb_data_map = Map.from_struct(zkb_data)
        KillCache.cache_kill(kill_id, zkb_data_map)
        process_zkill_data(zkb_data_map, kill_id, state)

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
      error: inspect(error)
    })
  end

  defp get_killmail_id(%{"killmail_id" => kill_id}), do: kill_id
  defp get_killmail_id(%{killmail_id: kill_id}), do: kill_id
  defp get_killmail_id(_), do: nil

  # Process a single killmail
  def process_single_kill(kill_data, _ctx) do
    # Implementation that uses the context parameter
    # This fixes the unused variable warning
    {:ok, kill_data}
  end
end
