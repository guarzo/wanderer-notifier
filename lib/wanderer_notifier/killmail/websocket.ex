# lib/wanderer_notifier/killmail/websocket.ex
defmodule WandererNotifier.Killmail.Websocket do
  @moduledoc """
  WebSocket client for zKillboard's killstream.
  Handles subscription, heartbeat monitoring, and circuit-breaker reconnect logic.
  """

  use WebSockex

  alias WandererNotifier.Core.Stats
  alias WandererNotifier.Logger.Logger, as: AppLogger

  @heartbeat_interval :timer.minutes(1)
  @subscribe_delay 100

  defstruct parent: nil,
            url: nil,
            connected: false,
            reconnects: 0,
            history: [],
            circuit_open: false,
            startup_time: 0

  @type state :: %__MODULE__{
          parent: pid(),
          url: String.t(),
          connected: boolean(),
          reconnects: non_neg_integer(),
          history: [integer()],
          circuit_open: boolean(),
          startup_time: integer()
        }

  @spec start_link(pid(), keyword()) :: {:ok, pid()} | {:error, term()}
  def start_link(parent, opts \\ []) do
    url = opts[:url] || default_url()
    initial = %__MODULE__{parent: parent, url: url, startup_time: System.system_time(:second)}

    AppLogger.websocket_info("Connecting to zKillboard WS", url: url)
    WebSockex.start_link(url, __MODULE__, initial, retry_initial_connection: true)
  end

  def init(state) do
    schedule_heartbeat()
    {:ok, state}
  end

  @impl true
  def handle_connect(_conn, state) do
    AppLogger.websocket_info("WebSocket connected")

    Stats.update_websocket(%{
      connected: true,
      connecting: false,
      last_message: DateTime.utc_now(),
      startup_time: DateTime.from_unix!(state.startup_time),
      reconnects: state.reconnects,
      url: state.url
    })

    Process.send_after(self(), :subscribe, @subscribe_delay)
    {:ok, %{state | connected: true}}
  end

  @impl true
  def handle_info(:subscribe, state) do
    msg = Jason.encode!(%{"action" => "sub", "channel" => "killstream"})
    AppLogger.websocket_info("Subscribing to killstream")
    {:reply, {:text, msg}, state}
  end

  @impl true
  def handle_info(:heartbeat, state) do
    schedule_heartbeat()

    last_msg = Stats.get_stats().websocket.last_message

    cond do
      last_msg == nil ->
        force_reconnect(state)

      DateTime.diff(DateTime.utc_now(), last_msg, :second) > 300 ->
        AppLogger.websocket_warn("Stale connection (>5m), pinging")
        {:reply, :ping, state}

      true ->
        {:ok, state}
    end
  end

  defp schedule_heartbeat do
    Process.send_after(self(), :heartbeat, @heartbeat_interval)
  end

  @impl true
  def handle_frame({:text, raw}, state) do
    state = update_stats_on_message(state)
    dispatch(raw, state)
    {:ok, state}
  rescue
    e ->
      AppLogger.websocket_error("Frame processing failed", error: Exception.message(e))
      {:ok, state}
  end

  @impl true
  def handle_frame({:ping, _}, state) do
    AppLogger.websocket_info("Received ping → sending pong")
    {:reply, {:text, Jason.encode!(%{"action" => "pong"})}, state}
  end

  @impl true
  def handle_frame(other, state) do
    AppLogger.websocket_debug("Unexpected frame", frame: inspect(other))
    {:ok, state}
  end

  defp update_stats_on_message(state) do
    Stats.update_websocket(%{
      connected: true,
      connecting: false,
      last_message: DateTime.utc_now()
    })

    state
  end

  defp dispatch(raw, %__MODULE__{parent: parent}) do
    with {:ok, data} <- Jason.decode(raw),
         _type <- classify(data),
         true <- Process.alive?(parent) do
      send(parent, {:zkill_message, raw})
    else
      {:error, _} ->
        AppLogger.websocket_error("JSON decode failed", snippet: String.slice(raw, 0, 100))

      false ->
        AppLogger.websocket_warn("Parent down, dropping message")

      _ ->
        :noop
    end
  end

  defp classify(%{"action" => "tqStatus"}), do: "tq_status"
  defp classify(%{"zkb" => _}), do: "killmail"
  defp classify(%{"killmail_id" => _}), do: "killmail"
  defp classify(_), do: "unknown"

  @impl true
  def handle_disconnect(reason, state) do
    now = System.system_time(:second)
    window = reconnect_window()
    history = [now | state.history] |> Enum.filter(&(&1 >= now - window))
    reconnects = state.reconnects + 1
    new_state = %{state | history: history, reconnects: reconnects}

    if length(history) >= max_reconnects() do
      AppLogger.websocket_error("Circuit open, halting reconnects", reason: inspect(reason))
      {:error, %{new_state | circuit_open: true}}
    else
      delay = calc_delay(reconnects)

      AppLogger.websocket_warn("Disconnected, will reconnect",
        reason: inspect(reason),
        attempt: reconnects,
        delay: delay
      )

      {:reconnect, %{new_state | connected: false}, delay}
    end
  end

  defp calc_delay(count) do
    base = 500
    jitter = :rand.uniform() - 0.5
    delay = :math.pow(1.5, min(count, 10)) * base * (1 + jitter)
    trunc(min(delay, 120_000))
  end

  defp force_reconnect(state) do
    AppLogger.websocket_warn("Forcing reconnect due to inactivity")
    {:close, state}
  end

  @impl true
  def terminate(reason, state) do
    AppLogger.websocket_info("WebSocket terminating",
      reason: inspect(reason),
      connected: state.connected
    )

    :ok
  end

  # Configuration helpers

  defp get_config do
    Application.get_env(:wanderer_notifier, :websocket, [])
  end

  defp default_url do
    get_config()[:url] || "wss://zkillboard.com/websocket/"
  end

  defp max_reconnects do
    get_config()[:max_reconnects] || 20
  end

  defp reconnect_window do
    get_config()[:reconnect_window] || 3_600
  end
end
