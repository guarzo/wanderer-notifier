defmodule WandererNotifier.MapEvents.Supervisor do
  @moduledoc """
  Supervisor for MapEvents WebSocket client.
  Handles connection failures gracefully.
  """

  use Supervisor
  require Logger

  def start_link(opts) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(opts) do
    Logger.info("[MapEvents.Supervisor] Starting with opts: #{inspect(opts)}")

    # Validate required options are present
    map_identifier = Keyword.get(opts, :map_identifier)
    api_key = Keyword.get(opts, :api_key)

    if is_nil(map_identifier) or is_nil(api_key) do
      {:stop, {:missing_required_options, opts}}
    else
      children = [
        {WandererNotifier.MapEvents.ConnectionManager, opts}
      ]

      Supervisor.init(children, strategy: :one_for_one)
    end
  end
end

defmodule WandererNotifier.MapEvents.ConnectionManager do
  @moduledoc """
  Manages the WebSocket connection with retry logic
  """

  use GenServer
  require Logger

  @initial_retry_delay 5_000
  # 5 minutes
  @max_retry_delay 300_000

  # Suppress dialyzer warning about pattern matching in handle_info/2
  # The supervisor validates options before passing them, so the {:ok, pid} case is reachable
  @dialyzer :no_match

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(opts) do
    # Validate required options
    map_identifier = Keyword.get(opts, :map_identifier)
    api_key = Keyword.get(opts, :api_key)

    if is_nil(map_identifier) or is_nil(api_key) do
      {:stop, {:missing_required_options, opts}}
    else
      # Try to connect immediately
      send(self(), :connect)

      # Store validated options explicitly
      validated_opts =
        [
          map_identifier: map_identifier,
          api_key: api_key
        ] ++ Keyword.take(opts, [:url, :name])

      {:ok,
       %{
         opts: validated_opts,
         retry_delay: @initial_retry_delay,
         websocket_pid: nil
       }}
    end
  end

  @impl true
  def handle_info(:connect, state) do
    Logger.debug("[MapEvents.ConnectionManager] Attempting to connect WebSocket")

    case WandererNotifier.MapEvents.WebSocketClient.start_link(state.opts) do
      {:ok, pid} ->
        Logger.debug("[MapEvents.ConnectionManager] WebSocket connection established")
        Process.monitor(pid)
        {:noreply, %{state | websocket_pid: pid, retry_delay: @initial_retry_delay}}

      {:error, reason} ->
        Logger.error("[MapEvents.ConnectionManager] Failed to connect WebSocket",
          reason: inspect(reason),
          retry_in_ms: state.retry_delay
        )

        # Schedule retry
        Process.send_after(self(), :connect, state.retry_delay)

        # Exponential backoff
        new_delay = min(state.retry_delay * 2, @max_retry_delay)
        {:noreply, %{state | retry_delay: new_delay}}
    end
  end

  @impl true
  def handle_info({:DOWN, _ref, :process, pid, reason}, state) when pid == state.websocket_pid do
    Logger.error("[MapEvents.ConnectionManager] WebSocket connection lost",
      reason: inspect(reason)
    )

    # Schedule reconnection
    Process.send_after(self(), :connect, state.retry_delay)

    {:noreply, %{state | websocket_pid: nil}}
  end

  @impl true
  def handle_info(_msg, state) do
    {:noreply, state}
  end
end
