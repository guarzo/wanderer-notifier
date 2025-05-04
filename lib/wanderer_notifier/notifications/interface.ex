defmodule WandererNotifier.Notifications.Interface do
  @moduledoc """
  Standardized interface for creating and sending notifications.

  This module provides a clean, consistent API for sending various types of notifications
  throughout the application, abstracting away the underlying notification mechanism.
  """

  alias WandererNotifier.Logger.Logger, as: AppLogger
  alias WandererNotifier.Notifications.Factory
  alias WandererNotifier.Notifications.Determiner.Character, as: CharacterDeterminer
  alias WandererNotifier.Notifications.Determiner.Kill, as: KillDeterminer
  alias WandererNotifier.Notifications.KillmailNotification

  @doc """
  Sends a kill notification.

  Determines if a notification should be sent and manages both system and character notifications.

  ## Parameters
  - enriched_killmail: The enriched killmail data to send notification for
  - kill_id: The ID of the kill
  - bypass_dedup: Whether to bypass deduplication checks (default: false)

  ## Returns
  - {:ok, kill_id} on success
  - {:error, reason} on failure
  """
  def send_kill_notification(enriched_killmail, kill_id, bypass_dedup \\ false) do
    KillmailNotification.send_kill_notification(enriched_killmail, kill_id, bypass_dedup)
  end

  @doc """
  Checks if a notification should be sent for a given kill.

  ## Parameters
  - killmail: The killmail to check

  ## Returns
  - true if a notification should be sent
  - false otherwise
  """
  def should_notify_kill?(killmail) do
    KillDeterminer.should_notify?(killmail)
  end

  @doc """
  Checks if a notification should be sent for a given character.

  ## Parameters
  - character_id: The character ID to check
  - character_details: Optional map with character details for performance optimization

  ## Returns
  - true if a notification should be sent
  - false otherwise
  """
  def should_notify_character?(character_id, character_details \\ nil) do
    CharacterDeterminer.should_notify?(character_id, character_details)
  end

  @doc """
  Sends a test kill notification.

  Uses recent data to send a test notification.

  ## Returns
  - {:ok, kill_id} on success
  - {:error, reason} on failure
  """
  def send_test_kill_notification do
    KillmailNotification.send_test()
  end

  @doc """
  Sends a plain text message notification.

  ## Parameters
  - message: The text message to send

  ## Returns
  - {:ok, result} on success
  - {:error, reason} on failure
  """
  def send_message(message) do
    case message do
      msg when is_binary(msg) ->
        Factory.send_message(msg)
      embed when is_map(embed) ->
        Factory.send_message(embed)

      _ ->
        AppLogger.notification_error("Unknown message type for notification", %{
          type: inspect(message)
        })

        {:error, :invalid_message_type}
    end
  end
end
