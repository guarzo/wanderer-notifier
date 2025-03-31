defmodule WandererNotifier.Schedulers.BaseScheduler do
  @moduledoc """
  Base implementation of a scheduler, providing common functionality.

  This module implements the common functionality for all schedulers,
  serving as a foundation for both interval-based and time-based schedulers.

  Features:
  - Standardized initialization and execution flow
  - Automatic registration with scheduler registry
  - Robust error handling with retry capabilities
  - Consistent logging patterns
  """

  alias WandererNotifier.Logger.Logger, as: AppLogger
  alias WandererNotifier.Schedulers.Registry, as: SchedulerRegistry

  defmacro __using__(opts) do
    quote do
      use GenServer
      alias WandererNotifier.Logger.Logger, as: AppLogger
      @behaviour WandererNotifier.Schedulers.Behaviour

      # The scheduler name, to be used for registration and logging
      @scheduler_name unquote(Keyword.get(opts, :name, __CALLER__.module))

      # Retry settings
      @max_retry_attempts unquote(Keyword.get(opts, :max_retry_attempts, 3))
      @backoff_ms unquote(Keyword.get(opts, :backoff_ms, 1000))
      @max_backoff_ms unquote(Keyword.get(opts, :max_backoff_ms, 30_000))

      # Client API

      @doc """
      Starts the scheduler process.
      """
      def start_link(opts \\ []) do
        AppLogger.scheduler_debug("Starting #{inspect(@scheduler_name)}")
        GenServer.start_link(__MODULE__, opts, name: __MODULE__)
      end

      @doc """
      Manually triggers the scheduled task.
      """
      def execute_now do
        GenServer.cast(__MODULE__, :execute_now)
      end

      @doc """
      Manually triggers the scheduled task with a specific retry count.
      """
      def execute_now(retry_count) when is_integer(retry_count) and retry_count >= 0 do
        GenServer.cast(__MODULE__, {:execute_now, retry_count})
      end

      # Server callbacks

      @impl true
      def init(opts) do
        # Track initialization in process dictionary for debugging
        Process.put(:scheduler_init_time, :os.system_time(:millisecond))
        Process.put(:scheduler_name, @scheduler_name)

        # Try to register with the registry, with retry for timing issues
        register_with_retry()

        if enabled?() do
          # Call initialize instead of init to avoid name conflicts
          # We know initialize always returns {:ok, state} now
          {:ok, state} = initialize(opts)

          # Log only at debug level, will be summarized by the Registry
          AppLogger.scheduler_debug("#{inspect(@scheduler_name)} initialized and scheduled")
          {:ok, Map.merge(state, %{retry_count: 0, last_execution: nil, last_result: nil})}
        else
          # Log only at debug level, will be summarized by the Registry
          AppLogger.scheduler_debug(
            "#{inspect(@scheduler_name)} initialized but not scheduled (disabled)"
          )

          {:ok, %{disabled: true}}
        end
      end

      # Register with retry to handle race conditions where the registry might not be ready
      defp register_with_retry(attempts \\ 0) do
        if Process.whereis(SchedulerRegistry) do
          AppLogger.scheduler_debug("Registering #{inspect(@scheduler_name)} with registry")
          SchedulerRegistry.register(__MODULE__)
        else
          if attempts < 5 do
            # Retry with exponential backoff
            backoff = min(@backoff_ms * 2 ** attempts, @max_backoff_ms)

            AppLogger.scheduler_debug(
              "Registry not available, retrying in #{backoff}ms (attempt #{attempts + 1}/5)"
            )

            Process.sleep(backoff)
            register_with_retry(attempts + 1)
          else
            AppLogger.scheduler_warn(
              "Failed to register #{inspect(@scheduler_name)} after 5 attempts - registry not available"
            )
          end
        end
      end

      # This function should be implemented by interval or time schedulers
      def initialize(_opts), do: {:ok, %{}}

      defoverridable initialize: 1

      @impl true
      def handle_cast(:execute_now, %{disabled: true} = state) do
        AppLogger.scheduler_info(
          "#{inspect(@scheduler_name)}: Skipping manually triggered execution (disabled)"
        )

        {:noreply, state}
      end

      @impl true
      def handle_cast({:execute_now, retry_count}, state) do
        # Manually triggered with specific retry count
        execute_with_retry(state, retry_count)
      end

      @impl true
      def handle_cast(:execute_now, state) do
        # Manually triggered, start with retry count 0
        execute_with_retry(state, 0)
      end

      # Executes the task with retry capability
      defp execute_with_retry(state, retry_count) do
        # Update state with current execution time
        new_state =
          Map.merge(state, %{
            retry_count: retry_count,
            last_execution: :os.system_time(:millisecond)
          })

        # Log execution attempt
        log_level = if retry_count > 0, do: :warn, else: :debug

        AppLogger.scheduler_log(
          log_level,
          "#{inspect(@scheduler_name)}: Executing (attempt #{retry_count + 1}/#{@max_retry_attempts + 1})"
        )

        # Execute the task
        case safely_execute(state) do
          {:ok, result, updated_state} ->
            # Execution succeeded, reset retry count
            AppLogger.scheduler_debug("#{inspect(@scheduler_name)}: Execution successful")

            final_state =
              Map.merge(updated_state, %{
                retry_count: 0,
                last_result: {:ok, result}
              })

            {:noreply, final_state}

          {:error, reason, updated_state} ->
            # Handle execution error with potential retry
            handle_execution_error(reason, updated_state, retry_count)
        end
      end

      # Safely executes the task with exception handling
      defp safely_execute(state) do
        try do
          execute(state)
        rescue
          e ->
            stacktrace = Process.info(self(), :current_stacktrace)

            AppLogger.scheduler_error(
              "#{inspect(@scheduler_name)}: Execution raised exception: #{Exception.message(e)}",
              stacktrace: inspect(stacktrace)
            )

            {:error, {:exception, e}, state}
        catch
          kind, value ->
            AppLogger.scheduler_error(
              "#{inspect(@scheduler_name)}: Execution failed with #{kind}: #{inspect(value)}"
            )

            {:error, {kind, value}, state}
        end
      end

      # Handles execution errors with retry logic
      defp handle_execution_error(reason, state, retry_count) do
        if retry_count < @max_retry_attempts do
          # Calculate backoff time with exponential increase
          backoff = min(@backoff_ms * 2 ** retry_count, @max_backoff_ms)

          AppLogger.scheduler_warn(
            "#{inspect(@scheduler_name)}: Execution failed: #{inspect(reason)}, " <>
              "retrying in #{backoff}ms (attempt #{retry_count + 1}/#{@max_retry_attempts})"
          )

          # Schedule retry after backoff
          Process.send_after(self(), {:retry_execution, retry_count + 1}, backoff)

          # Update state with error information
          new_state =
            Map.merge(state, %{
              retry_count: retry_count + 1,
              last_result: {:error, reason},
              last_error: reason,
              last_retry_time: :os.system_time(:millisecond)
            })

          {:noreply, new_state}
        else
          # Max retries reached, give up
          AppLogger.scheduler_error(
            "#{inspect(@scheduler_name)}: Execution failed after #{@max_retry_attempts} " <>
              "retries: #{inspect(reason)}"
          )

          # Update state with final error information
          new_state =
            Map.merge(state, %{
              # Reset for next execution
              retry_count: 0,
              last_result: {:error, reason},
              last_error: reason,
              retries_exhausted: true
            })

          {:noreply, new_state}
        end
      end

      @impl true
      def handle_info({:retry_execution, retry_count}, state) do
        # Triggered by a scheduled retry
        execute_with_retry(state, retry_count)
      end

      # Default handler for unexpected messages
      def handle_unexpected_message(message, state) do
        AppLogger.scheduler_warn(
          "#{inspect(@scheduler_name)}: Received unexpected message: #{inspect(message)}"
        )

        {:noreply, state}
      end

      defoverridable handle_unexpected_message: 2

      @doc """
      Returns health information about this scheduler.
      """
      def health_check do
        GenServer.call(__MODULE__, :health_check)
      end

      @impl true
      def handle_call(:health_check, _from, state) do
        health_info = %{
          name: @scheduler_name,
          enabled: enabled?(),
          disabled: Map.get(state, :disabled, false),
          last_execution: Map.get(state, :last_execution, nil),
          last_result: Map.get(state, :last_result, nil),
          last_error: Map.get(state, :last_error, nil),
          retry_count: Map.get(state, :retry_count, 0),
          config: get_config()
        }

        {:reply, health_info, state}
      end

      # Default implementation for enabled? - can be overridden
      @impl true
      def enabled?, do: true

      # Default empty config - should be overridden
      @impl true
      def get_config, do: %{}

      defoverridable enabled?: 0, get_config: 0
    end
  end
end
