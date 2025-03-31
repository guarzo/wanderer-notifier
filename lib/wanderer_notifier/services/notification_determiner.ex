defmodule WandererNotifier.Services.NotificationDeterminer do
  @moduledoc """
  Central module for determining whether notifications should be sent based on tracking criteria.
  This module handles the logic for deciding if a kill, system, or character event should trigger
  a notification based on configured tracking rules.

  Note: This module is deprecated and will be removed in a future version.
  Please use WandererNotifier.Notifiers.Determiner instead.
  """
  require Logger
  alias WandererNotifier.Core.Logger, as: AppLogger
  alias WandererNotifier.Notifiers.Determiner

  @doc """
  Determines if a notification should be sent for a kill.

  ## Parameters
    - killmail: The killmail to check

  ## Returns
    - true if a notification should be sent
    - false otherwise
  """
  def should_send_kill_notification?(killmail) do
    AppLogger.processor_debug(
      "WandererNotifier.Services.NotificationDeterminer.should_send_kill_notification? is deprecated, please use WandererNotifier.Notifiers.Determiner.should_send_kill_notification?/1 instead"
    )

    Determiner.should_send_kill_notification?(killmail)
  end

  @doc """
  Determine if a kill notification should be sent.

  ## Parameters
    - killmail: The killmail data
    - system_id: Optional system ID (will extract from killmail if not provided)

  ## Returns
    - true if notification should be sent
    - false otherwise with reason logged
  """
  def should_notify_kill?(killmail, system_id \\ nil) do
    AppLogger.processor_debug(
      "WandererNotifier.Services.NotificationDeterminer.should_notify_kill? is deprecated, please use WandererNotifier.Notifiers.Determiner.should_notify_kill?/2 instead"
    )

    Determiner.should_notify_kill?(killmail, system_id)
  end

  @doc """
  Checks if a system is being tracked.

  ## Parameters
    - system_id: The ID of the system to check

  ## Returns
    - true if the system is tracked
    - false otherwise
  """
  def tracked_system?(system_id) when is_integer(system_id) or is_binary(system_id) do
    AppLogger.processor_debug(
      "WandererNotifier.Services.NotificationDeterminer.tracked_system? is deprecated, please use WandererNotifier.Notifiers.Determiner.tracked_system?/1 instead"
    )

    Determiner.tracked_system?(system_id)
  end

  def tracked_system?(_), do: false

  @doc """
  Checks if a killmail involves a tracked character (as victim or attacker).

  ## Parameters
    - killmail: The killmail data to check

  ## Returns
    - true if the killmail involves a tracked character
    - false otherwise
  """
  def has_tracked_character?(killmail) do
    AppLogger.processor_debug(
      "WandererNotifier.Services.NotificationDeterminer.has_tracked_character? is deprecated, please use WandererNotifier.Notifiers.Determiner.has_tracked_character?/1 instead"
    )

    Determiner.has_tracked_character?(killmail)
  end

  @doc """
  Checks if a notification should be sent after deduplication.
  This is used to prevent duplicate notifications for the same event.

  ## Parameters
    - notification_type: The type of notification (:kill, :system, :character, etc.)
    - identifier: Unique identifier for the notification (such as kill_id)

  ## Returns
    - {:ok, :send} if notification should be sent
    - {:ok, :skip} if notification should be skipped (duplicate)
    - {:error, reason} if an error occurs
  """
  def check_deduplication(notification_type, identifier) do
    AppLogger.processor_debug(
      "WandererNotifier.Services.NotificationDeterminer.check_deduplication is deprecated, please use WandererNotifier.Notifiers.Determiner.check_deduplication/2 instead"
    )

    Determiner.check_deduplication(notification_type, identifier)
  end

  @doc """
  Determines if a system notification should be sent.
  Checks if system notifications are enabled and applies deduplication.

  ## Parameters
    - system_id: The system ID to check

  ## Returns
    - true if notification should be sent
    - false otherwise
  """
  def should_notify_system?(system_id) do
    AppLogger.processor_debug(
      "WandererNotifier.Services.NotificationDeterminer.should_notify_system? is deprecated, please use WandererNotifier.Notifiers.Determiner.should_notify_system?/1 instead"
    )

    Determiner.should_notify_system?(system_id)
  end

  @doc """
  Determines if a character notification should be sent.
  Checks if character notifications are enabled and applies deduplication.

  ## Parameters
    - character_id: The character ID to check

  ## Returns
    - true if notification should be sent
    - false otherwise
  """
  def should_notify_character?(character_id) do
    AppLogger.processor_debug(
      "WandererNotifier.Services.NotificationDeterminer.should_notify_character? is deprecated, please use WandererNotifier.Notifiers.Determiner.should_notify_character?/1 instead"
    )

    Determiner.should_notify_character?(character_id)
  end

  @doc """
  Prints the system tracking status for debugging purposes.
  """
  def print_system_tracking_status do
    AppLogger.processor_debug(
      "WandererNotifier.Services.NotificationDeterminer.print_system_tracking_status is deprecated, please use WandererNotifier.Notifiers.Determiner.print_system_tracking_status/0 instead"
    )

    Determiner.print_system_tracking_status()
  end
end
