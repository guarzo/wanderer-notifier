defmodule WandererNotifier.Killmail.Processor do
  @moduledoc """
  Processes incoming ZKillboard messages, runs them through the killmail pipeline,
  and dispatches notifications when appropriate.
  """

  alias WandererNotifier.Logger.Logger, as: AppLogger
  alias WandererNotifier.Killmail.Context
  alias WandererNotifier.Killmail.Killmail

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

  @spec process_zkill_message(String.t(), state) :: {:ok, kill_id | :skipped} | {:error, term()}
  def process_zkill_message(raw_message, state) do
    case Jason.decode(raw_message) do
      {:error, reason} ->
        AppLogger.error("Failed to decode ZKill message",
          error: inspect(reason),
          message: raw_message
        )

        {:error, {:decode_error, reason}}

      {:ok, kill_data} ->
        case should_notify?(kill_data) do
          {:ok, %{should_notify: true}} ->
            process_kill_data(kill_data, state)

          {:ok, %{should_notify: false, reason: reason}} ->
            log_skipped(kill_data, reason)
            {:ok, :skipped}

          unexpected ->
            AppLogger.error("Unexpected response from notification determiner", %{
              kill_data: inspect(kill_data),
              response: inspect(unexpected)
            })

            {:error, {:invalid_notification_response, unexpected}}
        end
    end
  end

  @spec log_stats() :: :ok
  def log_stats do
    :ok
  end

  @spec get_recent_kills() :: {:ok, kill_data} | {:error, :no_recent_kills}
  def get_recent_kills do
    case cache_repo().get(WandererNotifier.Cache.Keys.zkill_recent_kills()) do
      {:ok, [latest | _]} -> {:ok, latest}
      _ -> {:error, :no_recent_kills}
    end
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
    kill_id = Map.get(killmail, "killmail_id", "unknown")
    system_id = Map.get(killmail, "solar_system_id")
    source = Keyword.get(opts, :source, :direct)
    state = Keyword.get(opts, :state)

    # Create a context with relevant information
    system_name = get_system_name(system_id)

    context_opts = %{
      source: source,
      processing_started_at: DateTime.utc_now()
    }

    context_opts = if state, do: Map.put(context_opts, :original_state, state), else: context_opts

    context = Context.new(kill_id, system_name, context_opts)

    # Process through pipeline and let it handle notification
    case killmail_pipeline().process_killmail(killmail, context) do
      {:ok, :skipped} ->
        # Pipeline indicated this should be skipped
        {:ok, :skipped}

      {:ok, _final_killmail} ->
        # Successfully processed and notified in pipeline
        {:ok, kill_id}

      error ->
        # Handle pipeline errors
        AppLogger.kill_error("Failed to process kill data",
          kill_id: kill_id,
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
    with {:ok, kill_data} <- get_recent_kills() do
      process_killmail(kill_data, source: :test_notification)
    end
  end

  @spec process_kill_data(kill_data, state) ::
          {:ok, kill_id | :skipped} | {:error, term()}
  def process_kill_data(kill_data, state) do
    kill_id = Map.get(kill_data, "killmail_id", "unknown")
    system_id = Map.get(kill_data, "solar_system_id")

    # Create a context with relevant information
    system_name = get_system_name(system_id)

    context =
      Context.new(
        kill_id,
        system_name,
        %{
          source: :zkill_websocket,
          original_state: state,
          processing_started_at: DateTime.utc_now()
        }
      )

    # Process through pipeline and let it handle notification
    case killmail_pipeline().process_killmail(kill_data, context) do
      {:ok, :skipped} ->
        # Pipeline indicated this should be skipped
        {:ok, :skipped}

      {:ok, _final_killmail} ->
        # Successfully processed and notified in pipeline
        {:ok, kill_id}

      error ->
        # Handle pipeline errors
        AppLogger.kill_error("Failed to process kill data",
          kill_id: kill_id,
          error: inspect(error)
        )

        error
    end
  end

  # -- Private helpers -------------------------------------------------------

  defp should_notify?(%Killmail{} = killmail) do
    # Get the determination from the Kill Determiner
    result = WandererNotifier.Notifications.Determiner.Kill.should_notify?(killmail)

    # Only log errors and inconsistencies
    case result do
      {:ok, %{should_notify: false, reason: reason}} ->
        AppLogger.error(
          "PROCESSOR: Kill notification skipped: #{reason} (killmail_id=#{killmail.killmail_id})"
        )

      {:ok, %{should_notify: true}} ->
        :ok

      {:error, reason} ->
        AppLogger.error(
          "PROCESSOR: Kill notification error: #{inspect(reason)} (killmail_id=#{killmail.killmail_id})"
        )
    end

    result
  end

  defp should_notify?(kill_data) do
    # Get the determination from the Kill Determiner
    result = WandererNotifier.Notifications.Determiner.Kill.should_notify?(kill_data)

    # Only log errors and inconsistencies
    case result do
      {:ok, %{should_notify: false, reason: reason}} ->
        AppLogger.error(
          "PROCESSOR: Kill notification skipped: #{reason} (killmail_id=#{kill_data["killmail_id"]})"
        )

      {:ok, %{should_notify: true}} ->
        :ok

      {:error, reason} ->
        AppLogger.error(
          "PROCESSOR: Kill notification error: #{inspect(reason)} (killmail_id=#{kill_data["killmail_id"]})"
        )
    end

    result
  end

  defp log_skipped(kill_data, reason) do
    AppLogger.kill_info("Skipping killmail notification",
      kill_id: kill_data["killmail_id"],
      reason: reason
    )
  end

  defp get_system_name(nil), do: "unknown"
  defp get_system_name(system_id), do: "System #{system_id}"

  defp killmail_pipeline do
    Application.get_env(
      :wanderer_notifier,
      :killmail_pipeline,
      WandererNotifier.Killmail.Pipeline
    )
  end

  defp cache_repo do
    Application.get_env(:wanderer_notifier, :cache_repo, WandererNotifier.Cache)
  end
end
