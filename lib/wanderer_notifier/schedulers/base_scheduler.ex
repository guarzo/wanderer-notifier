defmodule WandererNotifier.Schedulers.BaseScheduler do
  @moduledoc """
  Base implementation of a scheduler, providing common functionality.

  This module implements the common functionality for all schedulers,
  serving as a foundation for both interval-based and time-based schedulers.
  """

  require Logger

  defmacro __using__(opts) do
    quote do
      use GenServer
      require Logger
      @behaviour WandererNotifier.Schedulers.Behaviour

      # The scheduler name, to be used for registration and logging
      @scheduler_name unquote(Keyword.get(opts, :name, __CALLER__.module))

      # Client API

      @doc """
      Starts the scheduler process.
      """
      def start_link(opts \\ []) do
        GenServer.start_link(__MODULE__, opts, name: __MODULE__)
      end

      @doc """
      Manually triggers the scheduled task.
      """
      def execute_now do
        GenServer.cast(__MODULE__, :execute_now)
      end

      # Server callbacks

      @impl true
      def init(opts) do
        Logger.info("Initializing #{inspect(@scheduler_name)}...")

        if enabled?() do
          # Call initialize instead of init to avoid name conflicts
          {:ok, state} = initialize(opts)
          Logger.info("#{inspect(@scheduler_name)} initialized and scheduled")
          {:ok, state}
        else
          Logger.info("#{inspect(@scheduler_name)} initialized but not scheduled (disabled)")
          {:ok, %{disabled: true}}
        end
      end

      # This function should be implemented by interval or time schedulers
      def initialize(_opts), do: {:ok, %{}}

      defoverridable initialize: 1

      @impl true
      def handle_cast(:execute_now, %{disabled: true} = state) do
        Logger.info(
          "#{inspect(@scheduler_name)}: Skipping manually triggered execution (disabled)"
        )

        {:noreply, state}
      end

      @impl true
      def handle_cast(:execute_now, state) do
        Logger.info("#{inspect(@scheduler_name)}: Manually triggered execution")

        case execute(state) do
          {:ok, _result, new_state} ->
            {:noreply, new_state}

          {:error, reason, new_state} ->
            Logger.error("#{inspect(@scheduler_name)}: Execution failed: #{inspect(reason)}")
            {:noreply, new_state}
        end
      end

      # Default handler for unexpected messages
      def handle_unexpected_message(message, state) do
        Logger.warning(
          "#{inspect(@scheduler_name)}: Received unexpected message: #{inspect(message)}"
        )

        {:noreply, state}
      end

      defoverridable handle_unexpected_message: 2

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
