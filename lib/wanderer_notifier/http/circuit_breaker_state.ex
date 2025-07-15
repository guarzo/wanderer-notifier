defmodule WandererNotifier.Http.CircuitBreakerState do
  @moduledoc """
  Circuit breaker state management using ETS tables.

  This module manages the state of circuit breakers for different hosts,
  tracking failure counts, state transitions, and recovery times.

  ## Circuit Breaker States
  - `:closed` - Normal operation, requests are allowed
  - `:open` - Circuit is open, all requests are rejected immediately
  - `:half_open` - Testing state, limited requests are allowed to test recovery

  ## State Transitions
  - `closed -> open`: When failure threshold is exceeded
  - `open -> half_open`: After recovery timeout expires
  - `half_open -> closed`: When health check succeeds
  - `half_open -> open`: When health check fails
  """

  use GenServer

  alias WandererNotifier.Logger.Logger, as: AppLogger

  @type circuit_state :: :closed | :open | :half_open
  @type circuit_info :: %{
          state: circuit_state(),
          failure_count: non_neg_integer(),
          last_failure_time: integer(),
          last_success_time: integer(),
          next_attempt_time: integer()
        }

  @table_name :circuit_breaker_states
  @default_failure_threshold 5
  # 1 minute
  @default_recovery_timeout_ms 60_000

  ## Public API

  @doc """
  Starts the circuit breaker state manager.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Gets the current state for a given host.
  """
  @spec get_state(String.t()) :: circuit_info()
  def get_state(host) do
    case :ets.lookup(@table_name, host) do
      [{^host, circuit_info}] -> circuit_info
      [] -> default_circuit_info()
    end
  end

  @doc """
  Records a successful request for a host.
  """
  @spec record_success(String.t()) :: :ok
  def record_success(host) do
    GenServer.cast(__MODULE__, {:record_success, host})
  end

  @doc """
  Records a failed request for a host.
  """
  @spec record_failure(String.t()) :: :ok
  def record_failure(host) do
    GenServer.cast(__MODULE__, {:record_failure, host})
  end

  @doc """
  Checks if a request should be allowed for a host.

  This operation is atomic to prevent race conditions during state transitions.
  """
  @spec can_execute?(String.t()) :: boolean()
  def can_execute?(host) do
    GenServer.call(__MODULE__, {:can_execute, host})
  end

  @doc """
  Gets circuit breaker statistics for monitoring.
  """
  @spec get_stats() :: %{String.t() => circuit_info()}
  def get_stats do
    :ets.tab2list(@table_name)
    |> Enum.into(%{})
  end

  @doc """
  Resets the circuit breaker state for a host (for testing/management).
  """
  @spec reset_state(String.t()) :: :ok
  def reset_state(host) do
    GenServer.cast(__MODULE__, {:reset_state, host})
  end

  ## GenServer Callbacks

  @impl true
  def init(_opts) do
    # Create ETS table for storing circuit breaker states
    :ets.new(@table_name, [
      :named_table,
      :public,
      :set,
      {:read_concurrency, true},
      {:write_concurrency, true}
    ])

    AppLogger.api_info("Circuit breaker state manager started", %{
      table: @table_name,
      component: "CircuitBreakerState"
    })

    {:ok, %{}}
  end

  @impl true
  def handle_call({:can_execute, host}, _from, state) do
    current_time = :erlang.system_time(:millisecond)
    circuit_info = get_state(host)

    {can_execute, updated_info} =
      case circuit_info.state do
        :closed ->
          {true, circuit_info}

        :open ->
          # Check if recovery timeout has passed
          if current_time >= circuit_info.next_attempt_time do
            # Transition to half-open atomically
            log_state_transition(host, :open, :half_open)
            updated = %{circuit_info | state: :half_open}
            {true, updated}
          else
            {false, circuit_info}
          end

        :half_open ->
          # Allow limited requests in half-open state
          {true, circuit_info}
      end

    # Update state in ETS if it changed
    if updated_info != circuit_info do
      :ets.insert(@table_name, {host, updated_info})
    end

    {:reply, can_execute, state}
  end

  @impl true
  def handle_cast({:record_success, host}, state) do
    current_time = :erlang.system_time(:millisecond)
    circuit_info = get_state(host)

    updated_info =
      case circuit_info.state do
        :half_open ->
          # Successful request in half-open - transition to closed
          log_state_transition(host, :half_open, :closed)
          %{circuit_info | state: :closed, failure_count: 0, last_success_time: current_time}

        _ ->
          # Reset failure count on success
          %{circuit_info | failure_count: 0, last_success_time: current_time}
      end

    :ets.insert(@table_name, {host, updated_info})
    {:noreply, state}
  end

  @impl true
  def handle_cast({:record_failure, host}, state) do
    current_time = :erlang.system_time(:millisecond)
    circuit_info = get_state(host)

    new_failure_count = circuit_info.failure_count + 1

    updated_info = %{
      circuit_info
      | failure_count: new_failure_count,
        last_failure_time: current_time
    }

    # Check if we should transition to open state
    final_info =
      if new_failure_count >= @default_failure_threshold and circuit_info.state != :open do
        log_state_transition(host, circuit_info.state, :open)

        %{
          updated_info
          | state: :open,
            next_attempt_time: current_time + @default_recovery_timeout_ms
        }
      else
        updated_info
      end

    :ets.insert(@table_name, {host, final_info})
    {:noreply, state}
  end

  @impl true
  def handle_cast({:reset_state, host}, state) do
    AppLogger.api_info("Resetting circuit breaker state", %{
      host: host,
      component: "CircuitBreakerState"
    })

    :ets.insert(@table_name, {host, default_circuit_info()})
    {:noreply, state}
  end

  ## Private Functions

  defp default_circuit_info do
    current_time = :erlang.system_time(:millisecond)

    %{
      state: :closed,
      failure_count: 0,
      last_failure_time: 0,
      last_success_time: current_time,
      next_attempt_time: 0
    }
  end

  defp log_state_transition(host, from_state, to_state) do
    AppLogger.api_warn("Circuit breaker state transition", %{
      host: host,
      from_state: from_state,
      to_state: to_state,
      component: "CircuitBreakerState"
    })
  end
end
