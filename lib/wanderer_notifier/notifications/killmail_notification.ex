defmodule WandererNotifier.Notifications.KillmailNotification do
  @moduledoc """
  Specialized module for processing kill notifications.
  Encapsulates all the notification handling logic for kills.
  """
  @behaviour WandererNotifier.Notifications.KillmailNotificationBehaviour

  alias WandererNotifier.Cache.Keys, as: CacheKeys
  alias WandererNotifier.Killmail.Enrichment
  alias WandererNotifier.Logger.Logger, as: AppLogger
  alias WandererNotifier.Notifications.Determiner.Kill, as: KillDeterminer
  alias WandererNotifier.Notifications.Formatters.Killmail, as: KillmailFormatter
  alias WandererNotifier.Notifications.Types.Notification
  alias WandererNotifier.Notifications.NotificationService
  alias WandererNotifier.Config

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
         _ = log_enrichment_success(kill_id, enriched_killmail),
         {:ok, should_notify} <- check_notification_requirements(enriched_killmail) do
      process_notification_decision(
        enriched_killmail,
        should_notify,
        kill_id,
        notification_type,
        notification_data
      )
    else
      {:error, reason} ->
        log_notification_error(kill_id, reason)
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

  @doc """
  Gets the latest killmails for notification.
  """
  def get_latest_killmails do
    cache_name = Config.cache_name()

    case Cachex.get(cache_name, CacheKeys.zkill_recent_kills()) do
      {:ok, kill_ids} when is_list(kill_ids) ->
        get_kills_by_ids(kill_ids)

      _ ->
        []
    end
  end

  # Private helper functions

  defp get_recent_kill do
    cache_name = Config.cache_name()

    case Cachex.get(cache_name, CacheKeys.zkill_recent_kills()) do
      {:ok, [kill | _]} -> {:ok, kill}
      _ -> {:error, :no_recent_kills}
    end
  end

  defp enrich_killmail(killmail) do
    case Enrichment.enrich_killmail_data(killmail) do
      {:ok, enriched} -> {:ok, enriched}
      error -> error
    end
  end

  # Helper function to extract kill ID from various data structures
  defp extract_kill_id(killmail) do
    extract_from_direct_keys(killmail) ||
      extract_from_esi_data(killmail) ||
      "unknown"
  end

  defp extract_from_direct_keys(killmail) when is_map(killmail) do
    killmail[:killmail_id] || killmail["killmail_id"]
  end

  defp extract_from_direct_keys(_), do: nil

  defp extract_from_esi_data(killmail) when is_map(killmail) do
    esi_data = killmail[:esi_data] || killmail["esi_data"]

    if is_map(esi_data) do
      esi_data["killmail_id"]
    end
  end

  defp extract_from_esi_data(_), do: nil

  defp check_notification_requirements(enriched_killmail) do
    # Get configuration
    config = Config.config_module().get_config()
    character_notifications_enabled = Map.get(config, :character_notifications_enabled, false)
    system_notifications_enabled = Map.get(config, :system_notifications_enabled, false)

    # Check if the killmail meets notification requirements
    system_id = KillDeterminer.get_kill_system_id(enriched_killmail)
    has_tracked_system = KillDeterminer.tracked_system?(system_id)
    has_tracked_character = KillDeterminer.has_tracked_character?(enriched_killmail)

    kill_id = extract_kill_id(enriched_killmail)

    # Evaluate character condition
    character_should_notify = has_tracked_character && character_notifications_enabled

    # Evaluate system condition
    system_should_notify = has_tracked_system && system_notifications_enabled

    # Log the decision for each condition
    if has_tracked_character do
      if character_notifications_enabled do
        AppLogger.kill_info("Character notifications enabled for tracked character", %{
          kill_id: kill_id
        })
      else
        AppLogger.kill_info("Character tracked but character notifications disabled", %{
          kill_id: kill_id
        })
      end
    end

    if has_tracked_system do
      if system_notifications_enabled do
        AppLogger.kill_info("System notifications enabled for tracked system", %{
          kill_id: kill_id,
          system_id: system_id
        })
      else
        AppLogger.kill_info("System tracked but system notifications disabled", %{
          kill_id: kill_id,
          system_id: system_id
        })
      end
    end

    # Return true if either condition is met
    if character_should_notify || system_should_notify do
      {:ok, true}
    else
      AppLogger.kill_info("Kill notification requirements not met - no enabled notifications", %{
        kill_id: kill_id,
        system_id: system_id
      })

      {:ok, false}
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
    if is_nil(killmail.esi_data) do
      {:error, "Missing ESI data"}
    else
      :ok
    end
  end

  defp log_enrichment_success(kill_id, enriched_killmail) do
    AppLogger.kill_info("Killmail enriched successfully", %{
      kill_id: kill_id,
      struct_type: inspect(enriched_killmail.__struct__)
    })
  end

  defp process_notification_decision(
         enriched_killmail,
         should_notify,
         kill_id,
         notification_type,
         notification_data
       ) do
    if should_notify do
      AppLogger.kill_info(
        "Kill notification requirements met, proceeding to send",
        %{kill_id: kill_id}
      )

      send_notification_with_retry(
        enriched_killmail,
        kill_id,
        notification_type,
        notification_data
      )
    else
      AppLogger.kill_info("Kill notification requirements not met, skipping notification", %{
        kill_id: kill_id
      })

      {:ok, :skipped}
    end
  end

  defp send_notification_with_retry(
         enriched_killmail,
         kill_id,
         notification_type,
         notification_data
       ) do
    with {:ok, notification} <-
           create_notification(enriched_killmail, notification_type, notification_data),
         _ = log_notification_created(kill_id, notification_type, notification),
         {:ok, sent_notification} <- send_notification(notification) do
      AppLogger.kill_info("Kill notification sent successfully", %{kill_id: kill_id})
      {:ok, sent_notification}
    else
      {:error, reason} ->
        log_notification_error(kill_id, reason)
        {:error, reason}
    end
  end

  defp log_notification_created(kill_id, notification_type, notification) do
    AppLogger.kill_info("Notification created", %{
      kill_id: kill_id,
      notification_type: notification_type,
      notification_data_keys: Map.keys(notification)
    })
  end

  defp log_notification_error(kill_id, reason) do
    AppLogger.kill_error("Failed to process kill notification", %{
      kill_id: kill_id,
      error: inspect(reason)
    })
  end

  defp get_kills_by_ids(kill_ids) do
    cache_name = Config.cache_name()
    keys = Enum.map(kill_ids, &CacheKeys.zkill_recent_kill/1)

    results =
      Enum.map(keys, fn key ->
        case Cachex.get(cache_name, key) do
          {:ok, value} -> {:ok, value}
          _ -> {:ok, nil}
        end
      end)

    process_kill_results(kill_ids, results)
  end

  defp process_kill_results(kill_ids, results) do
    for {id, {:ok, data}} <- Enum.zip(kill_ids, results),
        not is_nil(data) do
      Map.put(data, "id", id)
    end
  end
end
