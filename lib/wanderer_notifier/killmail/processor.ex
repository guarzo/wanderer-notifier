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
        # Early exit if not relevant
        case WandererNotifier.Notifications.Determiner.Kill.should_notify?(kill_data) do
          {:ok, %{should_notify: true}} ->
            process_kill_data(kill_data, state)

          {:ok, %{should_notify: false, reason: reason}} ->
            system_id = Map.get(kill_data, "solar_system_id")
            killmail_id = Map.get(kill_data, "killmail_id")
            system_name =
              case WandererNotifier.ESI.Service.get_system(system_id) do
                {:ok, %{"name" => name}} -> name
                _ -> "Unknown"
              end

            AppLogger.processor_info(
              "Skipping killmail: #{reason} (killmail_id=#{killmail_id}, system_id=#{system_id}, system_name=#{system_name})"
            )
            state

          _ ->
            AppLogger.processor_error(
              "Skipping killmail: unexpected response from determine_should_notify"
            )

            state
        end

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
    KillmailCache.get_recent_kills()
  end

  @doc """
  Sends a test kill notification.

  ## Returns
    - :ok on success
    - {:error, reason} on failure
  """
  def send_test_kill_notification do
    killmail = get_test_killmail()

    case Enrichment.enrich_killmail_data(killmail) do
      {:ok, enriched_kill} ->
        KillmailNotification.send_kill_notification(enriched_kill, :test)

      {:error, reason} ->
        AppLogger.error("Failed to enrich test killmail", error: inspect(reason))
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
    killmail = Killmail.from_map(kill_data)

    case Enrichment.enrich_killmail_data(killmail) do
      {:ok, enriched_kill} ->
        KillmailNotification.send_kill_notification(enriched_kill, :zkill)
        # Increment kill notification count
        WandererNotifier.Core.Stats.increment(:kills)
        state

      {:error, reason} ->
        AppLogger.error("Failed to enrich killmail", error: inspect(reason))
        {:error, reason}
    end
  end

  defp get_test_killmail do
    # Create a test killmail for testing notifications
    %Killmail{
      killmail_id: 12345,
      zkb: %{
        "hash" => "abc123"
      },
      esi_data: %{
        "killmail_time" => DateTime.utc_now() |> DateTime.to_iso8601(),
        "solar_system_id" => 30_000_142,
        "victim" => %{
          "character_id" => 98765,
          "ship_type_id" => 587
        },
        "attackers" => [
          %{
            "character_id" => 54321,
            "ship_type_id" => 587,
            "final_blow" => true
          }
        ]
      }
    }
  end
end
