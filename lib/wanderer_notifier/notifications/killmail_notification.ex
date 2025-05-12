defmodule WandererNotifier.Notifications.KillmailNotification do
  @moduledoc """
  Specialized module for processing kill notifications.
  Encapsulates all the notification handling logic for kills.
  """
  @behaviour WandererNotifier.Notifications.KillmailNotificationBehaviour

  alias WandererNotifier.Cache.Keys, as: CacheKeys
  alias WandererNotifier.Cache.CachexImpl, as: CacheRepo
  alias WandererNotifier.Logger.Logger, as: AppLogger
  alias WandererNotifier.Notifications.Determiner.Kill, as: KillDeterminer
  alias WandererNotifier.Notifications.Formatters.Killmail, as: KillmailFormatter
  alias WandererNotifier.Notifications.Types.Notification
  alias WandererNotifier.Notifications.NotificationService

  @doc """
  Creates a notification from a killmail.

  ## Parameters
  - killmail: The killmail struct to create a notification from

  ## Returns
  - A formatted notification ready to be sent
  """
  def create(killmail) do
    # Format the kill notification using the CommonFormatter
    formatted = KillmailFormatter.format_kill_notification(killmail)

    # Add the required data structure with killmail field expected by the Dispatcher
    Map.put(formatted, :data, %{killmail: killmail})
  end

  @doc """
  Determines if a kill notification should be sent and sends it.

  ## Parameters
  - killmail: The killmail struct to process
  - system_id: Optional system ID (will extract from killmail if not provided)

  ## Returns
  - true if a notification was sent
  - false if notification was skipped
  """
  def should_notify_kill?(killmail, _system_id \\ nil) do
    # Delegate to the KillDeterminer module for notification logic
    KillDeterminer.should_notify?(killmail)
  end

  @doc """
  Sends a kill notification.
  """
  def send_kill_notification(killmail, notification_type, notification_data) do
    kill_id = extract_kill_id(killmail)

    AppLogger.kill_info("Starting kill notification process", %{
      kill_id: kill_id,
      type: notification_type
    })

    with {:ok, enriched_killmail} <- enrich_killmail(killmail),
         # Get system_id first for better logging
         system_id = KillDeterminer.get_kill_system_id(enriched_killmail),
         # Check if this is a tracked system
         tracked_system_result = KillDeterminer.tracked_system?(system_id),
         # Check if any tracked characters are involved
         tracked_character_result = KillDeterminer.has_tracked_character?(enriched_killmail),
         _ =
           AppLogger.kill_info("Tracking check results", %{
             kill_id: kill_id,
             system_id: system_id,
             system_tracked: tracked_system_result,
             character_tracked: tracked_character_result
           }) do
      if tracked_system_result || tracked_character_result do
        # Notification requirements met, proceed with sending
        AppLogger.kill_info("Kill notification requirements met", %{
          kill_id: kill_id,
          system_id: system_id
        })

        with {:ok, notification} <-
               create_notification(enriched_killmail, notification_type, notification_data),
             {:ok, sent_notification} <- send_notification(notification) do
          AppLogger.kill_info("Kill notification sent successfully", %{kill_id: kill_id})
          {:ok, sent_notification}
        else
          {:error, reason} ->
            AppLogger.kill_error("Failed to send kill notification", %{
              kill_id: kill_id,
              error: inspect(reason)
            })

            {:error, reason}
        end
      else
        # Log this as info since it's an expected condition
        AppLogger.kill_info("Kill notification requirements not met", %{
          kill_id: kill_id,
          system_id: system_id
        })

        {:error, "No tracked systems or characters involved"}
      end
    else
      {:error, reason} ->
        AppLogger.kill_error("Failed to process kill notification", %{
          kill_id: kill_id,
          error: inspect(reason)
        })

        {:error, reason}
    end
  end

  @doc """
  Sends a test kill notification using recent data.
  """
  def send_test do
    AppLogger.kill_info("Sending test kill notification...")

    with {:ok, recent_kill} <- get_recent_kill(),
         kill_id = extract_kill_id(recent_kill),
         killmail = ensure_data_killmail(recent_kill),
         {:ok, enriched_kill} <- enrich_killmail(killmail),
         :ok <- validate_killmail_data(enriched_kill) do
      AppLogger.kill_info(
        "TEST NOTIFICATION: Using normal notification flow for test kill notification"
      )

      send_kill_notification(enriched_kill, "test", %{})
      {:ok, kill_id}
    else
      {:error, :no_recent_kills} ->
        AppLogger.kill_warn("No recent kills found in shared cache repository")
        {:error, :no_recent_kills}

      {:error, reason} ->
        error_message = "Cannot send test notification: #{reason}"
        AppLogger.kill_error(error_message)
        {:error, error_message}
    end
  end

  # Private helper functions

  defp get_recent_kill do
    case CacheRepo.get(CacheKeys.zkill_recent_kills()) do
      {:ok, [kill | _]} -> {:ok, kill}
      _ -> {:error, :no_recent_kills}
    end
  end

  defp enrich_killmail(killmail) do
    case WandererNotifier.Killmail.Enrichment.enrich_killmail_data(killmail) do
      {:ok, enriched} -> {:ok, enriched}
      error -> error
    end
  end

  # Helper function to extract kill ID from various data structures
  defp extract_kill_id(killmail) do
    cond do
      is_map(killmail) && Map.has_key?(killmail, :killmail_id) ->
        killmail.killmail_id

      is_map(killmail) && Map.has_key?(killmail, "killmail_id") ->
        killmail["killmail_id"]

      # Check ESI data structure
      is_map(killmail) && is_map(Map.get(killmail, :esi_data)) ->
        Map.get(killmail.esi_data, "killmail_id", "unknown")

      is_map(killmail) && is_map(Map.get(killmail, "esi_data")) ->
        Map.get(killmail["esi_data"], "killmail_id", "unknown")

      true ->
        "unknown"
    end
  end

  defp check_notification_requirements(enriched_killmail) do
    # Check if the killmail meets notification requirements
    system_id = KillDeterminer.get_kill_system_id(enriched_killmail)
    has_tracked_system = KillDeterminer.tracked_system?(system_id)
    has_tracked_character = KillDeterminer.has_tracked_character?(enriched_killmail)

    kill_id = extract_kill_id(enriched_killmail)

    AppLogger.kill_info("Checking notification requirements", %{
      kill_id: kill_id,
      system_id: system_id,
      has_tracked_system: has_tracked_system,
      has_tracked_character: has_tracked_character
    })

    if has_tracked_system || has_tracked_character do
      {:ok, true}
    else
      AppLogger.kill_info("Kill notification requirements not met", %{
        kill_id: kill_id,
        system_id: system_id
      })

      {:error, "No tracked systems or characters involved"}
    end
  end

  defp create_notification(killmail, notification_type, notification_data) do
    notification = %Notification{
      type: notification_type,
      data:
        Map.merge(notification_data, %{
          killmail: killmail,
          system_id: KillDeterminer.get_kill_system_id(killmail)
        })
    }

    {:ok, notification}
  end

  defp send_notification(notification) do
    NotificationService.send(notification)
  end

  # Ensure we have a proper Data.Killmail struct
  defp ensure_data_killmail(killmail) do
    if is_struct(killmail, WandererNotifier.Killmail.Killmail) do
      killmail
    else
      # Try to convert map to struct
      if is_map(killmail) do
        struct(WandererNotifier.Killmail.Killmail, Map.delete(killmail, :__struct__))
      else
        # Fallback empty struct with required fields
        %WandererNotifier.Killmail.Killmail{
          killmail_id: "unknown",
          zkb: %{}
        }
      end
    end
  end

  # Validate killmail has essential data
  defp validate_killmail_data(killmail) do
    cond do
      is_nil(killmail.esi_data) ->
        {:error, "Missing ESI data"}

      is_nil(killmail.killmail_id) ->
        {:error, "Missing killmail ID"}

      true ->
        :ok
    end
  end
end
