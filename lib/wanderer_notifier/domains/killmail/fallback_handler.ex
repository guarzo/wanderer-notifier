defmodule WandererNotifier.Domains.Killmail.FallbackHandler do
  @moduledoc """
  Handles fallback scenarios when WebSocket connection is unavailable.

  This module provides resilience by using the HTTP API to fetch killmail data
  when the real-time WebSocket connection is down. It can also be used for
  bulk loading operations and data recovery.
  """

  use GenServer
  require Logger

  alias WandererNotifier.Domains.Killmail.WandererKillsAPI
  alias WandererNotifier.Shared.Utils.{EntityUtils, Retry}

  # Check every 30 seconds
  @check_interval 30_000

  # Circuit breaker settings
  @failure_threshold 5
  # 5 minutes
  @recovery_time 300_000
  # 2 seconds base backoff
  @backoff_base 2_000

  defstruct [
    :websocket_pid,
    :last_check,
    :fallback_active,
    :tracked_systems,
    :tracked_characters,
    check_timer: nil,
    circuit_breaker_state: :closed,
    failure_count: 0,
    last_failure_time: nil,
    next_retry_time: nil
  ]

  # Client API

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Notifies the fallback handler that WebSocket is down.
  """
  def websocket_down do
    GenServer.cast(__MODULE__, :websocket_down)
  end

  @doc """
  Notifies the fallback handler that WebSocket is connected.
  """
  def websocket_connected do
    GenServer.cast(__MODULE__, :websocket_connected)
  end

  @doc """
  Manually triggers a data fetch for all tracked systems.
  """
  def fetch_recent_data do
    GenServer.call(__MODULE__, :fetch_recent_data, 30_000)
  end

  @doc """
  Performs bulk loading of historical data.
  """
  def bulk_load(hours \\ 24) do
    GenServer.call(__MODULE__, {:bulk_load, hours}, 60_000)
  end

  # Server Callbacks

  @impl true
  def init(opts) do
    websocket_pid = Keyword.get(opts, :websocket_pid)

    state = %__MODULE__{
      websocket_pid: websocket_pid,
      last_check: nil,
      fallback_active: false,
      tracked_systems: MapSet.new(),
      tracked_characters: MapSet.new()
    }

    # Schedule periodic checks
    {:ok, schedule_check(state)}
  end

  @impl true
  def handle_cast(:websocket_down, state) do
    Logger.info("WebSocket connection down, activating HTTP fallback for killmail processing")

    # Update tracked entities first
    updated_state = update_tracked_entities(state)
    new_state = %{updated_state | fallback_active: true}

    # Immediately fetch recent data in background
    Task.start(fn ->
      case fetch_all_recent_data(new_state) do
        {:ok, _result, _updated_state} -> :ok
        {:error, :circuit_breaker_open} -> :ok
      end
    end)

    {:noreply, new_state}
  end

  @impl true
  def handle_cast(:websocket_connected, state) do
    Logger.info(
      "WebSocket connection restored, deactivating HTTP fallback (returning to real-time WebSocket)"
    )

    {:noreply, %{state | fallback_active: false}}
  end

  @impl true
  def handle_call(:fetch_recent_data, _from, state) do
    # Update tracked entities first
    updated_state = update_tracked_entities(state)

    case fetch_all_recent_data(updated_state) do
      {:ok, result, new_state} ->
        {:reply, {:ok, result}, %{new_state | last_check: DateTime.utc_now()}}

      {:error, :circuit_breaker_open} ->
        {:reply, {:error, :circuit_breaker_open}, updated_state}
    end
  end

  @impl true
  def handle_call({:bulk_load, hours}, _from, state) do
    Logger.info("Starting bulk load for last #{hours} hours")

    # Update tracked entities
    state = update_tracked_entities(state)

    # Perform bulk load
    systems_list = MapSet.to_list(state.tracked_systems)
    result = WandererKillsAPI.bulk_load_system_kills(systems_list, hours)

    case result do
      {:ok, %{loaded: count, errors: errors}} ->
        Logger.info("Bulk load completed: #{count} killmails loaded, #{length(errors)} errors")

        if not Enum.empty?(errors) do
          Logger.info("Bulk load errors", errors: inspect(errors))
        end
    end

    {:reply, result, state}
  end

  @impl true
  def handle_info(:periodic_check, state) do
    new_state =
      if state.fallback_active do
        # Only fetch data if WebSocket is still down
        case fetch_all_recent_data(state) do
          {:ok, _result, updated_state} ->
            %{updated_state | last_check: DateTime.utc_now()}

          {:error, :circuit_breaker_open} ->
            %{state | last_check: DateTime.utc_now()}
        end
      else
        state
      end

    {:noreply, schedule_check(new_state)}
  end

  # Private Functions

  defp schedule_check(state) do
    if state.check_timer, do: Process.cancel_timer(state.check_timer)

    timer = Process.send_after(self(), :periodic_check, @check_interval)
    %{state | check_timer: timer}
  end

  defp fetch_all_recent_data(state) do
    # Check circuit breaker before proceeding
    if should_skip_api_call?(state) do
      Logger.warning("Skipping API call due to circuit breaker",
        circuit_state: state.circuit_breaker_state,
        failure_count: state.failure_count,
        next_retry: state.next_retry_time
      )

      {:error, :circuit_breaker_open}
    else
      Logger.info("Fetching recent data via HTTP API",
        systems_count: MapSet.size(state.tracked_systems),
        characters_count: MapSet.size(state.tracked_characters),
        circuit_state: state.circuit_breaker_state
      )

      # Fetch data for all tracked systems
      {system_results, updated_state} =
        fetch_system_data_with_circuit_breaker(state.tracked_systems, state)

      # Process results through the pipeline
      process_fetched_killmails(system_results)

      {:ok,
       %{
         systems_checked: MapSet.size(state.tracked_systems),
         killmails_processed: count_killmails(system_results)
       }, updated_state}
    end
  end

  defp update_tracked_entities(state) do
    alias WandererNotifier.Domains.Tracking.MapTrackingClient
    {:ok, systems} = MapTrackingClient.fetch_and_cache_systems()
    {:ok, characters} = MapTrackingClient.fetch_and_cache_characters()

    tracked_systems =
      systems
      |> Enum.map(&extract_system_id/1)
      |> Enum.filter(&valid_system_id?/1)
      |> MapSet.new()

    tracked_characters =
      characters
      |> Enum.map(&extract_character_id/1)
      |> Enum.filter(&valid_character_id?/1)
      |> MapSet.new()

    %{state | tracked_systems: tracked_systems, tracked_characters: tracked_characters}
  end

  defp get_error_type(%{type: type}), do: type

  # Circuit Breaker Functions

  defp should_skip_api_call?(state) do
    case state.circuit_breaker_state do
      :open ->
        # Circuit is open, check if we should attempt recovery
        current_time = System.monotonic_time(:millisecond)
        current_time < (state.next_retry_time || 0)

      _ ->
        false
    end
  end

  defp fetch_system_data_with_circuit_breaker(system_ids, state) do
    system_ids_list = MapSet.to_list(system_ids)

    # Process in chunks
    chunks = Enum.chunk_every(system_ids_list, 10)

    {results, updated_state} =
      Enum.reduce(chunks, {[], state}, fn chunk, {acc_results, current_state} ->
        case fetch_chunk_with_circuit_breaker(chunk, current_state) do
          {:ok, killmails, new_state} ->
            {[killmails | acc_results], new_state}

          {:error, new_state} ->
            {acc_results, new_state}
        end
      end)

    {List.flatten(results), updated_state}
  end

  defp fetch_chunk_with_circuit_breaker(system_ids, state) do
    case WandererKillsAPI.fetch_systems_killmails(system_ids, 1, 20) do
      {:ok, data} ->
        killmails = data |> Enum.flat_map(fn {_system_id, kills} -> kills end)
        new_state = record_success(state)
        {:ok, killmails, new_state}

      {:error, reason} ->
        Logger.error("Failed to fetch killmails for chunk - detailed error",
          systems: system_ids,
          system_count: length(system_ids),
          error_type: get_error_type(reason),
          error_details: inspect(reason, pretty: true),
          chunk_systems: Enum.join(system_ids, ", "),
          circuit_state: state.circuit_breaker_state,
          failure_count: state.failure_count
        )

        new_state = record_failure(state)
        {:error, new_state}
    end
  end

  defp record_success(state) do
    %{
      state
      | circuit_breaker_state: :closed,
        failure_count: 0,
        last_failure_time: nil,
        next_retry_time: nil
    }
  end

  defp record_failure(state) do
    current_time = System.monotonic_time(:millisecond)
    new_failure_count = state.failure_count + 1

    new_state = %{state | failure_count: new_failure_count, last_failure_time: current_time}

    if new_failure_count >= @failure_threshold do
      backoff_time = calculate_backoff_time(new_failure_count)

      Logger.warning("Circuit breaker opening due to repeated failures",
        failure_count: new_failure_count,
        threshold: @failure_threshold,
        backoff_seconds: backoff_time / 1000
      )

      %{new_state | circuit_breaker_state: :open, next_retry_time: current_time + backoff_time}
    else
      new_state
    end
  end

  defp calculate_backoff_time(failure_count) do
    # Use centralized Retry module for consistent backoff calculation
    state = %{
      attempt: failure_count - @failure_threshold + 1,
      base_backoff: @backoff_base,
      max_backoff: @recovery_time,
      jitter: 0.1,
      mode: :exponential
    }

    Retry.calculate_backoff(state)
  end

  defp process_fetched_killmails(killmails) do
    Enum.each(killmails, fn killmail ->
      # Send to pipeline worker
      case Process.whereis(WandererNotifier.Domains.Killmail.PipelineWorker) do
        nil ->
          Logger.warning("PipelineWorker not found for fallback processing")

        pid ->
          # Mark as HTTP-sourced to avoid duplicate processing
          enhanced_killmail = Map.put(killmail, "source", "http_fallback")
          send(pid, {:websocket_killmail, enhanced_killmail})
      end
    end)
  end

  defp count_killmails(system_results) do
    length(system_results)
  end

  # Helper functions (similar to WebSocket client)

  defp extract_system_id(system), do: EntityUtils.extract_system_id(system)

  defp valid_system_id?(system_id), do: EntityUtils.valid_system_id?(system_id)

  defp extract_character_id(char), do: EntityUtils.extract_character_id(char)

  defp valid_character_id?(char_id) do
    is_integer(char_id) && char_id > 90_000_000 && char_id < 100_000_000_000
  end
end
