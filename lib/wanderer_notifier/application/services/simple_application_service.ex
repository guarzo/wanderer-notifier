defmodule WandererNotifier.Application.Services.SimpleApplicationService do
  @moduledoc """
  Simplified application service that acts as a startup coordinator.

  This lightweight service ensures proper initialization order and
  provides basic health checking without complex state management.
  """

  use GenServer
  require Logger

  # ──────────────────────────────────────────────────────────────────────────────
  # Client API
  # ──────────────────────────────────────────────────────────────────────────────

  @doc """
  Starts the simplified application service.
  """
  def start_link(opts \\ []) do
    Logger.debug("Starting SimpleApplicationService...", category: :startup)
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Simple health check - just verifies the service is running.
  """
  def health_check do
    case Process.whereis(__MODULE__) do
      nil ->
        {:error, :not_running}

      pid when is_pid(pid) ->
        if Process.alive?(pid), do: :ok, else: {:error, :not_alive}
    end
  end

  # ──────────────────────────────────────────────────────────────────────────────
  # GenServer Callbacks
  # ──────────────────────────────────────────────────────────────────────────────

  @impl true
  def init(_opts) do
    Logger.info("SimpleApplicationService initialized successfully", category: :startup)
    {:ok, %{started_at: DateTime.utc_now()}}
  end

  @impl true
  def handle_call(:ping, _from, state) do
    {:reply, :pong, state}
  end

  @impl true
  def handle_info(msg, state) do
    Logger.debug("SimpleApplicationService received unexpected message: #{inspect(msg)}")
    {:noreply, state}
  end
end
