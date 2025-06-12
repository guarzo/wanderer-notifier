defmodule WandererNotifier.Killmail.Processor do
  @moduledoc """
  Processes incoming ZKillboard messages, runs them through the killmail pipeline,
  and dispatches notifications when appropriate.
  """

  alias WandererNotifier.Logger.Logger, as: AppLogger
  alias WandererNotifier.Cache.Keys, as: CacheKeys
  alias WandererNotifier.Killmail.Context
  alias WandererNotifier.Killmail.Killmail
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

  @spec process_zkill_message(map(), state) :: {:ok, kill_id | :skipped} | {:error, term()}
  def process_zkill_message(kill_data, state) do
    # Extract killmail_id from the data
    case extract_killmail_id(kill_data) do
      {:ok, _killmail_id} ->
        case should_notify?(kill_data) do
          {:ok, %{should_notify: true}} ->
            # Process the killmail since we should notify
            process_kill_data(kill_data, state)

          {:ok, %{should_notify: false} = result} ->
            reason = Map.get(result, :reason, "unknown")
            log_skipped(kill_data, reason)
            {:ok, :skipped}

          {:error, reason} ->
            {:error, reason}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  # Extract killmail_id from the data structure
  # Handle both "killmail_id" and "killID" formats from different sources
  defp extract_killmail_id(%{"killmail_id" => id}) when is_binary(id) and id != "", do: {:ok, id}
  defp extract_killmail_id(%{"killmail_id" => id}) when is_integer(id), do: {:ok, to_string(id)}
  defp extract_killmail_id(%{"killID" => id}) when is_integer(id), do: {:ok, to_string(id)}
  defp extract_killmail_id(%{"killID" => id}) when is_binary(id) and id != "", do: {:ok, id}

  defp extract_killmail_id(data) do
    AppLogger.kill_error("Failed to extract killmail_id - expected killmail_id or killID field",
      data: inspect(data),
      module: __MODULE__
    )

    {:error, :invalid_killmail_id}
  end

  # Helper function to extract killmail_id for logging purposes
  # Handles multiple data formats from different sources
  defp get_killmail_id_for_logging(%{"killmail_id" => id}) when not is_nil(id), do: id
  defp get_killmail_id_for_logging(%{"killID" => id}) when not is_nil(id), do: id

  defp get_killmail_id_for_logging(%{"killmail" => %{"killmail_id" => id}}) when not is_nil(id),
    do: id

  defp get_killmail_id_for_logging(%{"killID" => id, "killmail" => %{"killmail_id" => nested_id}}) do
    # Prefer the nested killmail_id if available, otherwise use killID
    nested_id || id
  end

  defp get_killmail_id_for_logging(_), do: nil

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

  defp should_notify?(%Killmail{} = killmail) do
    # Get the determination from the Kill Determiner
    result = KillDeterminer.should_notify?(killmail)

    # Only log errors and inconsistencies
    case result do
      {:ok, %{should_notify: false, reason: reason}} ->
        AppLogger.error(
          "PROCESSOR: Kill notification skipped: #{reason} (killmail_id=#{killmail.killmail_id})"
        )

      {:error, reason} ->
        AppLogger.error(
          "PROCESSOR: Kill notification error: #{inspect(reason)} (killmail_id=#{killmail.killmail_id})"
        )
    end

    result
  end

  defp should_notify?(kill_data) do
    # Get the determination from the Kill Determiner
    result = KillDeterminer.should_notify?(kill_data)

    # Don't log here - let the pipeline handle the elegant logging
    # This avoids duplicate logs
    case result do
      {:error, reason} ->
        killmail_id = get_killmail_id_for_logging(kill_data)

        AppLogger.error(
          "PROCESSOR: Kill notification error: #{inspect(reason)} (killmail_id=#{killmail_id})"
        )

      _ ->
        # Pipeline will handle success/skip logging with emojis and system names
        :ok
    end

    result
  end

  defp log_skipped(_kill_data, _reason) do
    # This is now handled by the pipeline with elegant emoji logging
    # Keeping the function for compatibility but it just returns :ok
    :ok
  end

  defp get_system_name(nil), do: "unknown"

  defp get_system_name(system_id) do
    case esi_service().get_system_info(system_id) do
      {:ok, %{"name" => name}} -> name
      _ -> "System #{system_id}"
    end
  end

  defp killmail_pipeline, do: WandererNotifier.Core.Dependencies.killmail_pipeline()
  defp esi_service, do: WandererNotifier.Core.Dependencies.esi_service()
end
