defmodule WandererNotifier.Domains.Killmail.FallbackHandler do
  @moduledoc """
  Handles fallback scenarios when WebSocket connection is unavailable.

  This module provides resilience by using the HTTP API to fetch killmail data
  when the real-time WebSocket connection is down. It can also be used for
  bulk loading operations and data recovery.
  """

  use GenServer
  require Logger

  alias WandererNotifier.Domains.Killmail.WandererKillsAPI

  # Check every 30 seconds
  @check_interval 30_000

  defstruct [
    :websocket_pid,
    :last_check,
    :fallback_active,
    :tracked_systems,
    :tracked_characters,
    check_timer: nil
  ]

  # Client API

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Notifies the fallback handler that WebSocket is down.
  """
  def websocket_down do
    GenServer.cast(__MODULE__, :websocket_down)
  end

  @doc """
  Notifies the fallback handler that WebSocket is connected.
  """
  def websocket_connected do
    GenServer.cast(__MODULE__, :websocket_connected)
  end

  @doc """
  Manually triggers a data fetch for all tracked systems.
  """
  def fetch_recent_data do
    GenServer.call(__MODULE__, :fetch_recent_data, 30_000)
  end

  @doc """
  Performs bulk loading of historical data.
  """
  def bulk_load(hours \\ 24) do
    GenServer.call(__MODULE__, {:bulk_load, hours}, 60_000)
  end

  # Server Callbacks

  @impl true
  def init(opts) do
    websocket_pid = Keyword.get(opts, :websocket_pid)

    state = %__MODULE__{
      websocket_pid: websocket_pid,
      last_check: nil,
      fallback_active: false,
      tracked_systems: MapSet.new(),
      tracked_characters: MapSet.new()
    }

    # Schedule periodic checks
    {:ok, schedule_check(state)}
  end

  @impl true
  def handle_cast(:websocket_down, state) do
    Logger.info("WebSocket connection down, activating HTTP fallback for killmail processing")

    # Update tracked entities first
    updated_state = update_tracked_entities(state)
    new_state = %{updated_state | fallback_active: true}

    # Immediately fetch recent data in background
    Task.start(fn -> fetch_all_recent_data(new_state) end)

    {:noreply, new_state}
  end

  @impl true
  def handle_cast(:websocket_connected, state) do
    Logger.info(
      "WebSocket connection restored, deactivating HTTP fallback (returning to real-time WebSocket)"
    )

    {:noreply, %{state | fallback_active: false}}
  end

  @impl true
  def handle_call(:fetch_recent_data, _from, state) do
    # Update tracked entities first
    updated_state = update_tracked_entities(state)
    result = fetch_all_recent_data(updated_state)
    {:reply, result, %{updated_state | last_check: DateTime.utc_now()}}
  end

  @impl true
  def handle_call({:bulk_load, hours}, _from, state) do
    Logger.info("Starting bulk load for last #{hours} hours")

    # Update tracked entities
    state = update_tracked_entities(state)

    # Perform bulk load
    systems_list = MapSet.to_list(state.tracked_systems)
    result = WandererKillsAPI.bulk_load_system_kills(systems_list, hours)

    case result do
      {:ok, %{loaded: count, errors: errors}} ->
        Logger.info("Bulk load completed: #{count} killmails loaded, #{length(errors)} errors")

        if length(errors) > 0 do
          Logger.info("Bulk load errors", errors: inspect(errors))
        end
    end

    {:reply, result, state}
  end

  @impl true
  def handle_info(:periodic_check, state) do
    new_state =
      if state.fallback_active do
        # Only fetch data if WebSocket is still down
        Task.start(fn -> fetch_all_recent_data(state) end)
        %{state | last_check: DateTime.utc_now()}
      else
        state
      end

    {:noreply, schedule_check(new_state)}
  end

  # Private Functions

  defp schedule_check(state) do
    if state.check_timer, do: Process.cancel_timer(state.check_timer)

    timer = Process.send_after(self(), :periodic_check, @check_interval)
    %{state | check_timer: timer}
  end

  defp fetch_all_recent_data(state) do
    Logger.info("Fetching recent data via HTTP API",
      systems_count: MapSet.size(state.tracked_systems),
      characters_count: MapSet.size(state.tracked_characters)
    )

    # Fetch data for all tracked systems
    system_results = fetch_system_data(state.tracked_systems)

    # Process results through the pipeline
    process_fetched_killmails(system_results)

    {:ok,
     %{
       systems_checked: MapSet.size(state.tracked_systems),
       killmails_processed: count_killmails(system_results)
     }}
  end

  defp update_tracked_entities(state) do
    alias WandererNotifier.Contexts.ApiContext
    {:ok, systems} = ApiContext.get_tracked_systems()
    {:ok, characters} = ApiContext.get_tracked_characters()

    tracked_systems =
      systems
      |> Enum.map(&extract_system_id/1)
      |> Enum.filter(&valid_system_id?/1)
      |> MapSet.new()

    tracked_characters =
      characters
      |> Enum.map(&extract_character_id/1)
      |> Enum.filter(&valid_character_id?/1)
      |> MapSet.new()

    %{state | tracked_systems: tracked_systems, tracked_characters: tracked_characters}
  end

  defp fetch_system_data(system_ids) do
    system_ids
    |> MapSet.to_list()
    # Process in chunks
    |> Enum.chunk_every(10)
    |> Enum.map(&fetch_chunk/1)
    |> List.flatten()
  end

  defp fetch_chunk(system_ids) do
    case WandererKillsAPI.fetch_systems_killmails(system_ids, 1, 20) do
      {:ok, data} ->
        data
        |> Enum.flat_map(fn {_system_id, kills} -> kills end)

      {:error, reason} ->
        Logger.info("Failed to fetch killmails for chunk",
          systems: system_ids,
          error: inspect(reason)
        )

        []
    end
  end

  defp process_fetched_killmails(killmails) do
    Enum.each(killmails, fn killmail ->
      # Send to pipeline worker
      case Process.whereis(WandererNotifier.Domains.Killmail.PipelineWorker) do
        nil ->
          Logger.warning("PipelineWorker not found for fallback processing")

        pid ->
          # Mark as HTTP-sourced to avoid duplicate processing
          enhanced_killmail = Map.put(killmail, "source", "http_fallback")
          send(pid, {:websocket_killmail, enhanced_killmail})
      end
    end)
  end

  defp count_killmails(system_results) do
    length(system_results)
  end

  # Helper functions (similar to WebSocket client)

  defp extract_system_id(system) when is_struct(system) do
    system.solar_system_id || system.system_id || system.id
  end

  defp extract_system_id(system) when is_map(system) do
    system["solar_system_id"] || system[:solar_system_id] ||
      system["system_id"] || system[:system_id] ||
      system["id"] || system[:id]
  end

  defp extract_system_id(_), do: nil

  defp valid_system_id?(system_id) do
    is_integer(system_id) && system_id > 30_000_000 && system_id < 40_000_000
  end

  defp extract_character_id(char) do
    # Extract from nested character structure
    char_id = char["character"]["eve_id"]
    normalize_character_id(char_id)
  end

  defp normalize_character_id(id) when is_integer(id), do: id

  defp normalize_character_id(id) when is_binary(id) do
    case Integer.parse(id) do
      {int_id, ""} -> int_id
      _ -> nil
    end
  end

  defp normalize_character_id(_), do: nil

  defp valid_character_id?(char_id) do
    is_integer(char_id) && char_id > 90_000_000 && char_id < 100_000_000_000
  end
end
