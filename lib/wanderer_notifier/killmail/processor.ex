defmodule WandererNotifier.Killmail.Processor do
  @moduledoc """
  Processes incoming ZKillboard messages, runs them through the killmail pipeline,
  and dispatches notifications when appropriate.
  """

  alias WandererNotifier.Logger.Logger, as: AppLogger
  alias WandererNotifier.Killmail.Context

  @type state     :: term()
  @type kill_id   :: String.t()
  @type kill_data :: map()

  @spec init() :: :ok
  def init do
    AppLogger.info("Initializing killmail processor")
    :ok
  end

  @spec schedule_tasks() :: :ok
  def schedule_tasks do
    AppLogger.info("Scheduling killmail tasks")
    :ok
  end

  @spec process_zkill_message(String.t(), state) :: state | {:ok, kill_id | :skipped}
  def process_zkill_message(raw_message, state) do
    case Jason.decode(raw_message) do
      {:error, reason} ->
        AppLogger.error("Failed to decode ZKill message",
          error: inspect(reason),
          message: raw_message
        )

        state

      {:ok, kill_data} ->
        case should_notify?(kill_data) do
          {:ok, true, _reason} ->
            process_kill_data(kill_data, state)

          {:ok, false, reason} ->
            log_skipped(kill_data, reason)
            state

          unexpected ->
            AppLogger.error("Unexpected response from notification determiner", %{
              kill_data: inspect(kill_data),
              response: inspect(unexpected)
            })

            state
        end
    end
  end

  @spec log_stats() :: :ok
  def log_stats do
    AppLogger.info("Logging killmail stats")
    :ok
  end

  @spec get_recent_kills() :: {:ok, kill_data} | {:error, :no_recent_kills}
  def get_recent_kills do
    case cache_repo().get(WandererNotifier.Cache.Keys.zkill_recent_kills()) do
      {:ok, [latest | _]} -> {:ok, latest}
      _ -> {:error, :no_recent_kills}
    end
  end

  @spec process_kill_data(kill_data, state) ::
          {:ok, kill_id | :skipped} | {:error, term()}
  def process_kill_data(kill_data, state) do
    kill_id = kill_data["killmail_id"] || "unknown"
    AppLogger.kill_info("Processing kill data", kill_id: kill_id)

    context = Context.new(nil, nil, :zkill_websocket, %{original_state: state})

    killmail_pipeline()
    |> then(& &1.process_killmail(kill_data, context))
    |> handle_pipeline_result(kill_id)
    |> maybe_notify(kill_id)
  end

  @spec send_test_kill_notification() :: {:ok, kill_id} | {:error, term()}
  def send_test_kill_notification do
    with {:ok, recent}       <- get_recent_kills(),
         kill_id             <- extract_kill_id(recent),
         structured          <- ensure_structured_killmail(recent),
         {:ok, enriched}     <- killmail_pipeline().process_killmail(structured, %Context{}) do
      killmail_notification().send_kill_notification(enriched, "test", %{})
      {:ok, kill_id}
    else
      {:error, :no_recent_kills} ->
        AppLogger.kill_warn("No recent kills found in shared cache")
        {:error, :no_recent_kills}

      {:error, reason} ->
        AppLogger.kill_error("Cannot send test notification: #{inspect(reason)}")
        {:error, reason}
    end
  end

  # -- Private helpers -------------------------------------------------------

  defp should_notify?(data) do
    case WandererNotifier.Notifications.Determiner.Kill.should_notify?(data) do
      {:ok, %{should_notify: notify, reason: reason}} -> {:ok, notify, reason}
      other -> {:error, other}
    end
  end

  defp log_skipped(%{"killmail_id" => id, "solar_system_id" => sys}, reason) do
    name = get_system_name(sys)

    AppLogger.processor_info(
      "Skipping killmail: #{reason} (killmail_id=#{id}, system_id=#{sys}, system_name=#{name})"
    )
  end

  defp handle_pipeline_result({:ok, :skipped}, _kill_id), do: {:skipped, nil}
  defp handle_pipeline_result({:ok, enriched}, _kill_id), do: {:ok, enriched}

  defp handle_pipeline_result({:error, reason}, kill_id) do
    AppLogger.kill_error("Failed to process kill data",
      kill_id: kill_id,
      error: inspect(reason)
    )

    {:error, reason}
  end

  # Prefix unused arg with underscore to silence warning
  defp maybe_notify({:skipped, _}, _), do: {:ok, :skipped}

  defp maybe_notify({:ok, enriched}, kill_id) do
    AppLogger.kill_info("About to send kill notification", kill_id: kill_id)

    case killmail_notification().send_kill_notification(enriched, "kill", %{}) do
      {:ok, _} ->
        AppLogger.kill_info("Kill notification sent successfully", kill_id: kill_id)
        {:ok, kill_id}

      {:error, reason} ->
        AppLogger.kill_error("Failed to send kill notification",
          kill_id: kill_id,
          error: inspect(reason)
        )

        {:error, {:notification_failed, reason}}
    end
  end

  defp get_system_name(system_id) do
    key = {:system_name, system_id}

    Process.get(key) ||
      case WandererNotifier.ESI.Service.get_system(system_id) do
        {:ok, %{"name" => name}} ->
          Process.put(key, name)
          name

        _ ->
          "Unknown(#{system_id})"
      end
  end

  defp extract_kill_id(%{"killmail_id" => id}), do: id
  defp extract_kill_id(%{killmail_id: id}),    do: id
  defp extract_kill_id(_),                     do: "unknown"

  defp ensure_structured_killmail(%WandererNotifier.Killmail.Killmail{} = k), do: k

  defp ensure_structured_killmail(map) when is_map(map) do
    struct(WandererNotifier.Killmail.Killmail, Map.delete(map, :__struct__))
  end

  defp ensure_structured_killmail(_),
    do: %WandererNotifier.Killmail.Killmail{killmail_id: "unknown", zkb: %{}}

  defp killmail_pipeline do
    Application.get_env(:wanderer_notifier, :killmail_pipeline, WandererNotifier.Killmail.Pipeline)
  end

  defp killmail_notification do
    Application.get_env(
      :wanderer_notifier,
      :killmail_notification,
      WandererNotifier.Notifications.KillmailNotification
    )
  end

  defp cache_repo do
    Application.get_env(:wanderer_notifier, :cache_repo, WandererNotifier.Cache.CachexImpl)
    |> then(fn repo ->
      if Code.ensure_loaded?(repo), do: repo, else: WandererNotifier.Cache.SafeCache
    end)
  end
end
