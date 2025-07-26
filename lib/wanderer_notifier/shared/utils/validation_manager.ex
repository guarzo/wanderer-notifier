defmodule WandererNotifier.Shared.Utils.ValidationManager do
  @moduledoc """
  GenServer for managing killmail validation state in production.

  Allows operators to force the next killmail to be processed as either
  a system notification or character notification for testing purposes.

  Safety features:
  - Auto-expires after 5 minutes
  - Single-use (resets after one killmail)
  - Simple enable/disable/status API
  """

  use GenServer
  require Logger

  # 5 minutes
  @validation_timeout_ms 5 * 60 * 1000

  # Client API

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  @doc """
  Enable validation mode for system notifications.
  Next killmail will be processed as a system notification.
  """
  def enable_system_validation do
    GenServer.call(__MODULE__, {:enable, :system})
  end

  @doc """
  Enable validation mode for character notifications.
  Next killmail will be processed as a character notification.
  """
  def enable_character_validation do
    GenServer.call(__MODULE__, {:enable, :character})
  end

  @doc """
  Disable validation mode.
  """
  def disable_validation do
    GenServer.call(__MODULE__, :disable)
  end

  @doc """
  Get current validation status.
  Returns %{mode: :system | :character | :disabled, expires_at: DateTime.t() | nil}
  """
  def get_status do
    GenServer.call(__MODULE__, :get_status)
  end

  @doc """
  Check and consume validation mode for killmail processing.
  Returns {:ok, :system | :character} if validation is active, {:ok, :disabled} otherwise.
  This is a single-use operation - validation mode is disabled after calling.
  """
  def check_and_consume do
    GenServer.call(__MODULE__, :check_and_consume)
  end

  # Server Callbacks

  @impl true
  def init(_args) do
    Logger.info("ValidationManager started")
    {:ok, %{mode: :disabled, expires_at: nil, timer_ref: nil}}
  end

  @impl true
  def handle_call({:enable, mode}, _from, state) when mode in [:system, :character] do
    # Cancel existing timer if any
    if state.timer_ref, do: Process.cancel_timer(state.timer_ref)

    expires_at = DateTime.add(DateTime.utc_now(), @validation_timeout_ms, :millisecond)
    timer_ref = Process.send_after(self(), :timeout, @validation_timeout_ms)

    new_state = %{
      mode: mode,
      expires_at: expires_at,
      timer_ref: timer_ref
    }

    Logger.info("Validation mode enabled: #{mode}, expires at #{expires_at}")
    {:reply, {:ok, new_state}, new_state}
  end

  @impl true
  def handle_call(:disable, _from, state) do
    # Cancel timer if any
    if state.timer_ref, do: Process.cancel_timer(state.timer_ref)

    new_state = %{mode: :disabled, expires_at: nil, timer_ref: nil}
    Logger.info("Validation mode disabled")
    {:reply, {:ok, new_state}, new_state}
  end

  @impl true
  def handle_call(:get_status, _from, state) do
    # Check if expired
    if expired?(state) do
      new_state = %{mode: :disabled, expires_at: nil, timer_ref: nil}
      {:reply, new_state, new_state}
    else
      status = %{mode: state.mode, expires_at: state.expires_at}
      {:reply, status, state}
    end
  end

  @impl true
  def handle_call(:check_and_consume, _from, state) do
    cond do
      expired?(state) ->
        new_state = %{mode: :disabled, expires_at: nil, timer_ref: nil}
        {:reply, {:ok, :disabled}, new_state}

      state.mode in [:system, :character] ->
        # Cancel timer and disable after use
        if state.timer_ref, do: Process.cancel_timer(state.timer_ref)
        new_state = %{mode: :disabled, expires_at: nil, timer_ref: nil}
        Logger.info("Validation mode consumed: #{state.mode}")
        {:reply, {:ok, state.mode}, new_state}

      true ->
        {:reply, {:ok, :disabled}, state}
    end
  end

  @impl true
  def handle_info(:timeout, _state) do
    Logger.info("Validation mode expired")
    new_state = %{mode: :disabled, expires_at: nil, timer_ref: nil}
    {:noreply, new_state}
  end

  # Private helpers

  defp expired?(%{expires_at: nil}), do: false

  defp expired?(%{expires_at: expires_at}) do
    DateTime.compare(DateTime.utc_now(), expires_at) == :gt
  end
end
