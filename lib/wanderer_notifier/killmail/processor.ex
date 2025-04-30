defmodule WandererNotifier.Killmail.Processor do
  @moduledoc """
  Handles processing of killmail data and scheduling of killmail-related tasks.
  """

  alias WandererNotifier.Logger.Logger, as: AppLogger
  alias WandererNotifier.Killmail.Enrichment
  alias WandererNotifier.Killmail.Killmail
  alias WandererNotifier.Killmail.Cache, as: KillmailCache
  alias WandererNotifier.Notifications.KillmailNotification

  @doc """
  Initializes the killmail processor.
  """
  def init do
    AppLogger.info("Initializing killmail processor")
    :ok
  end

  @doc """
  Schedules killmail-related tasks.
  """
  def schedule_tasks do
    AppLogger.info("Scheduling killmail tasks")
    :ok
  end

  @doc """
  Processes a ZKillboard websocket message.

  ## Parameters
    - message: The message to process
    - state: The current state

  ## Returns
    - new_state
  """
  def process_zkill_message(message, state) do
    case decode_zkill_message(message) do
      {:ok, kill_data} ->
        process_kill_data(kill_data, state)

      {:error, reason} ->
        AppLogger.error("Failed to decode ZKill message", %{
          error: inspect(reason),
          message: inspect(message)
        })

        state
    end
  end

  @doc """
  Logs killmail processing statistics.
  """
  def log_stats do
    AppLogger.info("Logging killmail stats")
    :ok
  end

  @doc """
  Gets recent kills from the cache.

  ## Returns
    - {:ok, kills} on success
    - {:error, reason} on failure
  """
  def get_recent_kills do
    case KillmailCache.get_recent_kills() do
      {:ok, kills} -> {:ok, kills}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Sends a test kill notification.

  ## Returns
    - :ok on success
    - {:error, reason} on failure
  """
  def send_test_kill_notification do
    case get_test_killmail() do
      {:ok, killmail} ->
        case Enrichment.enrich_killmail_data(killmail) do
          {:ok, enriched_kill} ->
            KillmailNotification.send_kill_notification(enriched_kill)

          {:error, reason} ->
            AppLogger.error("Failed to enrich test killmail", error: inspect(reason))
            {:error, reason}
        end

      {:error, reason} ->
        AppLogger.error("Failed to get test killmail", error: inspect(reason))
        {:error, reason}
    end
  end

  # Private helper functions

  defp decode_zkill_message(message) do
    case Jason.decode(message) do
      {:ok, decoded} -> {:ok, decoded}
      error -> error
    end
  end

  defp process_kill_data(kill_data, state) do
    case Killmail.from_zkill(kill_data) do
      {:ok, killmail} ->
        case Enrichment.enrich_killmail_data(killmail) do
          {:ok, enriched_kill} ->
            KillmailNotification.send_kill_notification(enriched_kill)
            state

          {:error, reason} ->
            AppLogger.error("Failed to enrich killmail", %{
              kill_id: killmail.kill_id,
              error: inspect(reason)
            })

            state
        end

      {:error, reason} ->
        AppLogger.error("Failed to process kill data", %{
          error: inspect(reason),
          data: inspect(kill_data)
        })

        state
    end
  end

  defp get_test_killmail do
    # Create a test killmail for testing notifications
    {:ok,
     %Killmail{
       kill_id: 12345,
       killmail_hash: "abc123",
       victim_id: 98765,
       attacker_id: 54321,
       ship_type_id: 587,
       solar_system_id: 30_000_142,
       kill_time: DateTime.utc_now()
     }}
  end
end
