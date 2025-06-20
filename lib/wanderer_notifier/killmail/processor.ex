defmodule WandererNotifier.Killmail.Processor do
  @moduledoc """
  Processes incoming ZKillboard messages, runs them through the killmail pipeline,
  and dispatches notifications when appropriate.
  """

  alias WandererNotifier.Logger.Logger, as: AppLogger
  alias WandererNotifier.Cache.Keys, as: CacheKeys
  alias WandererNotifier.Killmail.Context
  alias WandererNotifier.Notifications.Determiner.Kill, as: KillDeterminer
  alias WandererNotifier.Utils.TimeUtils

  @type state :: term()
  @type kill_id :: String.t()
  @type kill_data :: map()

  @spec init() :: :ok
  def init do
    AppLogger.info("Initializing killmail processor")
    :ok
  end

  @spec schedule_tasks() :: :ok
  def schedule_tasks do
    :ok
  end

  @spec process_websocket_killmail(map(), state) :: {:ok, kill_id | :skipped} | {:error, term()}
  def process_websocket_killmail(killmail, state) do
    # WebSocket killmails come pre-enriched, so we can process them directly
    killmail_id = Map.get(killmail, :killmail_id) || Map.get(killmail, "killmail_id")

    if killmail_id do
      case should_notify_websocket_killmail?(killmail) do
        {:ok, %{should_notify: true}} ->
          # Process the pre-enriched killmail
          process_websocket_kill_data(killmail, state)

        {:ok, %{should_notify: false} = result} ->
          reason = Map.get(result, :reason, "unknown")
          log_skipped_websocket(killmail, reason)
          {:ok, :skipped}

        {:error, reason} ->
          {:error, reason}
      end
    else
      AppLogger.kill_error("WebSocket killmail missing killmail_id",
        data: inspect(killmail),
        module: __MODULE__
      )

      {:error, :invalid_killmail_id}
    end
  end

  @spec log_stats() :: :ok
  def log_stats do
    :ok
  end

  @spec get_recent_kills() :: {:ok, list(kill_data())}
  def get_recent_kills do
    cache_name = Application.get_env(:wanderer_notifier, :cache_name, :wanderer_cache)

    case Cachex.get(cache_name, CacheKeys.zkill_recent_kills()) do
      {:ok, kills} when is_list(kills) -> {:ok, kills}
      _ -> {:ok, []}
    end
  end

  # Creates a context for processing a killmail
  defp create_context(kill_data, source, state) do
    kill_id = Map.get(kill_data, "killmail_id", "unknown")
    system_id = Map.get(kill_data, "solar_system_id")
    system_name = get_system_name(system_id)

    context_opts = %{
      source: source,
      processing_started_at: TimeUtils.now()
    }

    context_opts = if state, do: Map.put(context_opts, :original_state, state), else: context_opts

    Context.new(kill_id, system_name, context_opts)
  end

  @doc """
  Processes a raw killmail data map.

  ## Options
    - `:source` - The source of the killmail (e.g. :zkill_websocket, :direct, :test_notification)
    - `:state` - Optional state to include in the context (used by websocket handler)

  ## Returns
    - `{:ok, kill_id}` - Killmail was processed successfully
    - `{:ok, :skipped}` - Killmail was skipped (e.g. not relevant)
    - `{:error, reason}` - Processing failed
  """
  @spec process_killmail(map(), keyword()) :: {:ok, kill_id | :skipped} | {:error, term()}
  def process_killmail(killmail, opts \\ []) do
    source = Keyword.get(opts, :source, :direct)
    state = Keyword.get(opts, :state)
    context = create_context(killmail, source, state)

    # Process through pipeline and let it handle notification
    case killmail_pipeline().process_killmail(killmail, context) do
      {:ok, :skipped} ->
        # Pipeline indicated this should be skipped
        {:ok, :skipped}

      {:ok, _final_killmail} ->
        # Successfully processed and notified in pipeline
        {:ok, context.killmail_id}

      error ->
        # Handle pipeline errors
        AppLogger.kill_error("Failed to process kill data",
          kill_id: context.killmail_id,
          error: inspect(error)
        )

        error
    end
  end

  @doc """
  Sends a test notification using the most recent kill data.
  This is useful for verifying that the notification system is working correctly.

  ## Returns
    - `{:ok, kill_id}` - Test notification was sent successfully
    - `{:error, reason}` - Test notification failed
  """
  @spec send_test_kill_notification() :: {:ok, kill_id} | {:error, term()}
  def send_test_kill_notification do
    case get_recent_kills() do
      {:ok, [kill_data | _]} ->
        process_killmail(kill_data, source: :test_notification)

      {:ok, []} ->
        {:error, :no_recent_kills}
    end
  end

  @spec process_kill_data(kill_data, state) ::
          {:ok, kill_id | :skipped} | {:error, term()}
  def process_kill_data(kill_data, state) do
    context = create_context(kill_data, :zkill_websocket, state)

    # Process through pipeline and let it handle notification
    case killmail_pipeline().process_killmail(kill_data, context) do
      {:ok, :skipped} ->
        # Pipeline indicated this should be skipped
        {:ok, :skipped}

      {:ok, _final_killmail} ->
        # Successfully processed and notified in pipeline
        {:ok, context.killmail_id}

      error ->
        # Handle pipeline errors
        AppLogger.kill_error("Failed to process kill data",
          kill_id: context.killmail_id,
          error: inspect(error)
        )

        error
    end
  end

  # -- Private helpers -------------------------------------------------------

  defp get_system_name(nil), do: "unknown"

  defp get_system_name(system_id) do
    case esi_service().get_system(system_id, []) do
      {:ok, %{"name" => name}} -> name
      _ -> "System #{system_id}"
    end
  end

  # WebSocket killmail specific helpers

  defp should_notify_websocket_killmail?(killmail) do
    # WebSocket killmails come pre-enriched, so we can use them directly
    # Convert to format expected by KillDeterminer
    KillDeterminer.should_notify?(killmail)
  end

  defp process_websocket_kill_data(killmail, state) do
    # Create context for WebSocket killmail
    killmail_id = Map.get(killmail, :killmail_id) || Map.get(killmail, "killmail_id")
    system_id = Map.get(killmail, :system_id) || Map.get(killmail, "system_id")
    system_name = get_system_name(system_id)

    context_opts = %{
      source: :websocket,
      processing_started_at: TimeUtils.now()
    }

    context_opts = if state, do: Map.put(context_opts, :original_state, state), else: context_opts

    context =
      killmail_id
      |> to_string()
      |> Context.new(system_name, context_opts)

    # Process through pipeline - it will handle the pre-enriched data
    case killmail_pipeline().process_killmail(killmail, context) do
      {:ok, :skipped} ->
        {:ok, :skipped}

      {:ok, _final_killmail} ->
        {:ok, context.killmail_id}

      error ->
        AppLogger.kill_error("Failed to process WebSocket kill data",
          kill_id: context.killmail_id,
          error: inspect(error)
        )

        error
    end
  end

  defp log_skipped_websocket(killmail, reason) do
    killmail_id = Map.get(killmail, :killmail_id) || Map.get(killmail, "killmail_id")
    system_id = Map.get(killmail, :system_id) || Map.get(killmail, "system_id")

    AppLogger.processor_debug("WebSocket killmail skipped",
      killmail_id: killmail_id,
      system_id: system_id,
      reason: reason
    )

    :ok
  end

  defp killmail_pipeline, do: WandererNotifier.Core.Dependencies.killmail_pipeline()
  defp esi_service, do: WandererNotifier.Core.Dependencies.esi_service()
end
