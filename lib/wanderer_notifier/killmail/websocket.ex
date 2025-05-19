# lib/wanderer_notifier/killmail/websocket.ex
defmodule WandererNotifier.Killmail.Websocket do
  @moduledoc """
  Simplified zKillboard WebSocket client with automatic reconnect,
  subscription confirmation, and telemetry instrumentation.
  """

  use WebSockex
  alias WandererNotifier.Core.Stats
  alias WandererNotifier.Logger.Logger, as: AppLogger

  # Internal state struct
  defmodule State do
    @moduledoc false
    defstruct parent: nil
  end

  # Compile-time config (overridable in config/runtime.exs)
  @config Application.compile_env(:wanderer_notifier, :websocket, [])
  @url @config[:url] || "wss://zkillboard.com/websocket/"
  @ping_interval @config[:ping_interval] || 20_000
  @heartbeat_interval @config[:heartbeat_interval] || 30_000

  @doc """
  Starts the WebSocket client.

  ## Options
    * `:url` — override the WS URL
    * `:parent` — PID to which raw messages (`{:zkill_message, raw}`) are sent
    * `:name` — registered name (defaults to this module)
  """
  def start_link(opts) when is_list(opts) do
    name   = opts[:name]   || __MODULE__
    url    = opts[:url]    || @url
    parent = opts[:parent]

    WebSockex.start_link(
      url,
      __MODULE__,
      %State{parent: parent},
      name: name,
      handle_initial_conn_failure: true
    )
  end

  # Note: init/1 is invoked by WebSockex but isn't a declared WebSockex callback,
  # so we omit @impl here to avoid the warning.
  def init(state) do
    {:ok, state}
  end

  @impl true
  def handle_connect(_conn, state) do
    AppLogger.websocket_info("Connected to zKillboard WS")
    :telemetry.execute([:wanderer_notifier, :websocket, :connected], %{}, %{url: @url})

    # start heartbeat & ping loops
    schedule(:ping, @ping_interval)
    schedule(:heartbeat, @heartbeat_interval)

    # subscribe to killstream
    send(self(), :subscribe)

    {:ok, state}
  end

  @impl true
  def handle_frame({:text, raw}, state) do
    Stats.increment(:kill_processed)
    :telemetry.execute([:wanderer_notifier, :websocket, :message_received], %{count: 1}, %{})

    dispatch(raw, state)
    {:ok, state}
  end

  @impl true
  def handle_disconnect({kind, reason}, state) do
    AppLogger.websocket_warn("Disconnected (#{inspect(kind)}), reconnecting", reason: inspect(reason))
    :telemetry.execute([:wanderer_notifier, :websocket, :disconnected], %{count: 1}, %{kind: kind})
    {:reconnect, state}
  end

  @impl true
  def handle_info(:ping, state) do
    schedule(:ping, @ping_interval)
    WebSockex.cast(self(), :ping)
    {:ok, state}
  end

  @impl true
  def handle_info(:heartbeat, state) do
    schedule(:heartbeat, @heartbeat_interval)
    :telemetry.execute([:wanderer_notifier, :websocket, :heartbeat], %{timestamp: System.system_time(:millisecond)}, %{})
    {:ok, state}
  end

  @impl true
  def handle_info(:subscribe, state) do
    msg = Jason.encode!(%{"action" => "sub", "channel" => "killstream"})
    AppLogger.websocket_info("Subscribing to zKillboard killstream")
    {:reply, {:text, msg}, state}
  end

  @impl true
  def handle_cast(:ping, state) do
    {:reply, :ping, state}
  end

  # Decode and route raw messages, including subscription confirmation
  defp dispatch(raw, %State{parent: parent}) do
    case Jason.decode(raw) do
      {:ok, %{"action" => "subed", "channel" => "killstream"}} ->
        AppLogger.websocket_info("Subscription to killstream confirmed")
        :telemetry.execute([:wanderer_notifier, :websocket, :subscribed], %{}, %{})
        :ok

      {:ok, data} ->
        type = classify(data)
        AppLogger.websocket_debug("Received message", type: type)

        if parent && Process.alive?(parent) do
          send(parent, {:zkill_message, raw})
        else
          AppLogger.websocket_warn("Parent process not available, dropping message")
        end

        :ok

      {:error, reason} ->
        AppLogger.websocket_error("JSON decode failed",
          snippet: String.slice(raw, 0, 100),
          error: inspect(reason)
        )

        :error
    end
  end

  # Simple classification for logging/metrics
  defp classify(%{"action" => "tqStatus"}),  do: "tq_status"
  defp classify(%{"zkb" => _}),             do: "killmail"
  defp classify(%{"killmail_id" => _}),     do: "killmail"
  defp classify(%{"action" => "pong"}),      do: "pong"
  defp classify(%{"action" => "subed"}),     do: "subed"
  defp classify(_),                         do: "unknown"

  defp schedule(msg, interval),             do: Process.send_after(self(), msg, interval)
end
