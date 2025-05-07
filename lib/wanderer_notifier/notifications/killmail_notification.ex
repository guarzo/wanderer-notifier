defmodule WandererNotifier.Notifications.KillmailNotification do
  @moduledoc """
  Specialized module for processing kill notifications.
  Encapsulates all the notification handling logic for kills.
  """

  alias WandererNotifier.Cache.Keys, as: CacheKeys
  alias WandererNotifier.Cache.CachexImpl, as: CacheRepo
  alias WandererNotifier.Logger.Logger, as: AppLogger
  alias WandererNotifier.Notifications.Determiner.Kill, as: KillDeterminer
  alias WandererNotifier.Notifications.Dispatcher
  alias WandererNotifier.Notifications.Formatters.Common, as: CommonFormatter
  alias WandererNotifier.Notifications.Formatters.Killmail, as: KillmailFormatter

  @doc """
  Creates a notification from a killmail.

  ## Parameters
  - killmail: The killmail struct to create a notification from

  ## Returns
  - A formatted notification ready to be sent
  """
  def create(killmail) do
    # Format the kill notification using the CommonFormatter
    KillmailFormatter.format_kill_notification(killmail)
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
  def send_kill_notification(enriched_killmail, _kill_id, _bypass_dedup \\ false) do
    kill_id = enriched_killmail.killmail_id
    AppLogger.kill_info("Sending kill notification", %{kill_id: kill_id})

    # Check if the kill is relevant for system and/or character channels
    has_tracked_system = KillDeterminer.tracked_in_system?(enriched_killmail)
    tracked_characters = KillDeterminer.get_tracked_characters(enriched_killmail)
    has_tracked_characters = length(tracked_characters) > 0

    # Log what was detected
    log_notification_relevance(
      kill_id,
      has_tracked_system,
      has_tracked_characters,
      tracked_characters
    )

    # Send notifications to appropriate channels
    system_result = process_system_notification(enriched_killmail, kill_id, has_tracked_system)

    character_result =
      process_character_notification(
        enriched_killmail,
        kill_id,
        has_tracked_characters,
        tracked_characters
      )

    # Return combined result
    combine_notification_results(system_result, character_result, kill_id)
  end

  # Log relevance information for debugging
  defp log_notification_relevance(
         kill_id,
         has_tracked_system,
         has_tracked_characters,
         tracked_characters
       ) do
    AppLogger.kill_debug("Notification relevance", %{
      kill_id: kill_id,
      has_tracked_system: has_tracked_system,
      has_tracked_characters: has_tracked_characters,
      num_tracked_characters: length(tracked_characters)
    })
  end

  # Process system notification if needed
  defp process_system_notification(enriched_killmail, _kill_id, has_tracked_system) do
    kill_id = enriched_killmail.killmail_id

    if has_tracked_system do
      # Prepare system notification
      system_generic_notification =
        KillmailFormatter.format_kill_notification(enriched_killmail)

      system_discord_format = CommonFormatter.to_discord_format(system_generic_notification)

      # Send system notification
      send_system_notification(system_discord_format, kill_id)
    else
      {:ok, :skipped_system}
    end
  end

  # Process character notification if needed
  defp process_character_notification(
         enriched_killmail,
         _kill_id,
         has_tracked_characters,
         _tracked_characters
       ) do
    kill_id = enriched_killmail.killmail_id

    if has_tracked_characters do
      # For now, use the same notification format for character notifications
      character_generic_notification =
        KillmailFormatter.format_kill_notification(enriched_killmail)

      character_discord_format = CommonFormatter.to_discord_format(character_generic_notification)

      # Send character notification
      send_character_notification(character_discord_format, kill_id)
    else
      {:ok, :skipped_character}
    end
  end

  # Send system notification and handle result
  defp send_system_notification(notification, kill_id) do
    case Dispatcher.send_message(notification) do
      {:ok, :sent} ->
        AppLogger.kill_info("System kill notification sent", %{kill_id: kill_id})
        {:ok, :system_sent}

      {:error, reason} = error ->
        AppLogger.kill_error("Failed to send system kill notification", %{
          kill_id: kill_id,
          error: inspect(reason)
        })

        error
    end
  end

  # Send character notification and handle result
  defp send_character_notification(notification, kill_id) do
    case Dispatcher.send_message(notification) do
      {:ok, :sent} ->
        AppLogger.kill_info("Character kill notification sent", %{kill_id: kill_id})
        {:ok, :character_sent}

      {:error, reason} = error ->
        AppLogger.kill_error("Failed to send character kill notification", %{
          kill_id: kill_id,
          error: inspect(reason)
        })

        error
    end
  end

  # Combine results from system and character notifications
  defp combine_notification_results(system_result, character_result, kill_id) do
    case {system_result, character_result} do
      {{:ok, _}, {:ok, _}} ->
        AppLogger.kill_info("All kill notifications sent successfully", %{kill_id: kill_id})
        {:ok, :all_sent}

      {{:ok, _}, {:error, reason}} ->
        AppLogger.kill_error("Character notification failed but system notification succeeded", %{
          kill_id: kill_id,
          error: inspect(reason)
        })

        {:error, reason}

      {{:error, reason}, {:ok, _}} ->
        AppLogger.kill_error("System notification failed but character notification succeeded", %{
          kill_id: kill_id,
          error: inspect(reason)
        })

        {:error, reason}

      {{:error, reason}, {:error, _}} ->
        AppLogger.kill_error("Both notifications failed", %{
          kill_id: kill_id,
          error: inspect(reason)
        })

        {:error, reason}

      {{:ok, :skipped_system}, {:ok, :skipped_character}} ->
        AppLogger.kill_info("No notifications needed", %{kill_id: kill_id})
        {:ok, :skipped}

      {result_a, result_b} ->
        AppLogger.kill_info("Mixed notification results", %{
          kill_id: kill_id,
          system_result: inspect(result_a),
          character_result: inspect(result_b)
        })

        {:ok, :partial}
    end
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

      send_kill_notification(enriched_kill, kill_id, true)
      {:ok, kill_id}
    else
      {:error, :no_recent_kills} ->
        AppLogger.kill_warn("No recent kills found in shared cache repository")
        {:error, :no_recent_kills}

      {:error, reason} ->
        error_message = "Cannot send test notification: #{reason}"
        AppLogger.kill_error(error_message)
        Dispatcher.send_message(error_message)
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

  # Extract kill_id from various killmail formats
  defp extract_kill_id(killmail) do
    cond do
      is_map(killmail) && Map.has_key?(killmail, :killmail_id) ->
        killmail.killmail_id

      is_map(killmail) && Map.has_key?(killmail, "killmail_id") ->
        killmail["killmail_id"]

      true ->
        "unknown"
    end
  end
end
