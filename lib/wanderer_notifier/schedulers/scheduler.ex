defmodule WandererNotifier.Schedulers.Scheduler do
  @moduledoc """
  Defines the base behaviour and shared functionality for all schedulers.
  """

  defmacro __using__(opts) do
    quote do
      use GenServer

      @scheduler_name unquote(Keyword.get(opts, :name, __CALLER__.module))

      def start_link(opts \\ []) do
        GenServer.start_link(__MODULE__, opts, name: __MODULE__)
      end

      @impl true
      def init(opts) do
        case initialize(opts) do
          {:ok, state} -> {:ok, state}
          {:error, reason} -> {:stop, reason}
        end
      end

      @impl true
      def handle_info(message, state) do
        handle_unexpected_message(message, state)
      end

      # Default implementation for handling unexpected messages
      defp handle_unexpected_message(message, state) do
        require Logger

        Logger.warning(
          "#{inspect(@scheduler_name)} received unexpected message: #{inspect(message)}"
        )

        {:noreply, state}
      end

      # Default implementation for enabled? - can be overridden
      def enabled?, do: true

      # Default implementation for get_config - should be overridden
      def get_config, do: %{type: :unknown}

      # Execute now - useful for manual triggering
      def execute_now do
        if enabled?() do
          GenServer.cast(__MODULE__, :execute_now)
        end
      end

      @impl true
      def handle_cast(:execute_now, state) do
        case execute(state) do
          {:ok, _result, new_state} -> {:noreply, new_state}
          {:error, _reason, new_state} -> {:noreply, new_state}
        end
      end

      # Allow overriding of the callbacks
      defoverridable enabled?: 0,
                     get_config: 0,
                     handle_info: 2,
                     handle_cast: 2
    end
  end

  @doc """
  Callback invoked when the scheduler is initialized.
  """
  @callback initialize(opts :: Keyword.t()) ::
              {:ok, state :: term()}
              | {:error, reason :: term()}

  @doc """
  Callback invoked to execute the scheduled task.
  """
  @callback execute(state :: term()) ::
              {:ok, result :: term(), new_state :: term()}
              | {:error, reason :: term(), new_state :: term()}

  @doc """
  Callback that determines if the scheduler is enabled.
  """
  @callback enabled?() :: boolean()

  @doc """
  Callback that returns the scheduler's configuration.
  """
  @callback get_config() :: map()
end
