defmodule WandererNotifier.Domains.Killmail.PipelineWorker do
  require Logger

  @moduledoc """
  Worker process that handles killmail processing pipeline.

  This GenServer:
  - Starts and manages the WebSocket client connection to external killmail service
  - Receives pre-enriched killmail messages from WebSocket client
  - Processes them asynchronously through the simplified killmail pipeline
  """

  use GenServer

  alias WandererNotifier.Domains.Killmail.Pipeline

  defmodule State do
    @moduledoc false
    defstruct []
  end

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    Logger.debug("Starting Pipeline Worker")
    state = %State{}
    {:ok, state}
  end

  @impl true
  def handle_info({:websocket_killmail, killmail}, state) do
    log_killmail_received(killmail)
    WandererNotifier.Shared.Metrics.increment(:killmail_received)

    _task = spawn_killmail_processing_task(killmail, state)

    {:noreply, state}
  end

  @impl true
  def handle_info({:DOWN, _ref, :process, _pid, _reason}, state) do
    # Handle DOWN messages from tasks
    {:noreply, state}
  end

  @impl true
  def handle_info(msg, state) do
    Logger.debug("Unhandled message in PipelineWorker", message: inspect(msg))
    {:noreply, state}
  end

  # Private helper functions

  defp log_killmail_received(killmail) do
    victim_info = extract_victim_info(killmail)
    system_info = extract_system_info(killmail)

    Logger.info("Received WebSocket killmail",
      killmail_id: get_killmail_value(killmail, "killmail_id"),
      system_id: get_killmail_value(killmail, "system_id"),
      system_name: system_info.name,
      victim_id: victim_info.id,
      victim_name: victim_info.name,
      data_keys: Map.keys(killmail) |> Enum.take(10)
    )
  end

  defp spawn_killmail_processing_task(killmail, state) do
    Task.Supervisor.async_nolink(WandererNotifier.TaskSupervisor, fn ->
      process_killmail_task(killmail, state)
    end)
  end

  defp process_killmail_task(killmail, _state) do
    case Pipeline.process_killmail(killmail) do
      {:ok, :skipped} = success ->
        Logger.debug("Killmail processing skipped")
        success

      {:ok, _killmail_id} = success ->
        Logger.debug("Successfully processed killmail")
        success

      {:error, reason} ->
        log_killmail_processing_error(killmail, reason)
        {:error, reason}
    end
  end

  defp log_killmail_processing_error(killmail, reason) do
    Logger.debug("Failed to process killmail",
      error: inspect(reason),
      killmail_id: Map.get(killmail, "killmail_id") || Map.get(killmail, :killmail_id),
      system_id: Map.get(killmail, "system_id") || Map.get(killmail, :system_id),
      data_keys: Map.keys(killmail)
    )
  end

  defp extract_victim_info(killmail) do
    victim_info = killmail["victim"] || killmail[:victim] || %{}
    victim_name = victim_info["character_name"] || victim_info[:character_name] || "Unknown"
    victim_id = victim_info["character_id"] || victim_info[:character_id]

    %{name: victim_name, id: victim_id}
  end

  defp extract_system_info(killmail) do
    system_name = killmail["system_name"] || killmail[:system_name] || "Unknown System"
    %{name: system_name}
  end

  defp get_killmail_value(killmail, key) do
    killmail[key] || killmail[String.to_atom(key)]
  end
end
