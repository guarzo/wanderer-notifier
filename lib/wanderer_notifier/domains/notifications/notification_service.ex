defmodule WandererNotifier.Domains.Notifications.NotificationService do
  @moduledoc """
  Service module for handling notification dispatch.
  Provides a unified interface for sending notifications to Discord.
  """

  require Logger
  alias WandererNotifier.Domains.Notifications.Types.Notification
  alias WandererNotifier.Shared.Logger.ErrorLogger
  alias WandererNotifier.Shared.Logger.Logger, as: AppLogger
  alias WandererNotifier.Shared.Config
  alias WandererNotifier.Application.Services.Stats
  alias WandererNotifier.Domains.Notifications.Notifiers.Discord.Notifier, as: DiscordNotifier
  alias WandererNotifier.Domains.Notifications.Determiner.Kill, as: KillDeterminer

  @doc """
  Sends a notification.

  ## Parameters
    - notification: The notification to send

  ## Returns
    - {:ok, notification} on success
    - {:error, reason} on failure
  """
  def send(%Notification{} = notification) do
    AppLogger.info("Sending notification", %{type: notification.type})

    # Set a standardized notification type for the kill notification
    notification = %{notification | type: standardize_notification_type(notification.type)}

    # Send the notification
    case safe_send(notification) do
      {:ok, :sent} ->
        AppLogger.kill_info("Successfully sent notification", %{type: notification.type})
        {:ok, notification}

      {:error, reason} = error ->
        ErrorLogger.log_notification_error(
          "Failed to send notification",
          type: notification.type,
          reason: inspect(reason)
        )

        error

      {:exception, exception, stacktrace} ->
        ErrorLogger.log_exception(
          "Exception in NotificationService.send",
          exception,
          type: notification.type,
          stacktrace: stacktrace
        )

        {:error, :notification_service_error}
    end
  end

  def send(_), do: {:error, :invalid_notification}

  @doc """
  Sends a message using the appropriate notifier based on the current configuration.

  ## Parameters
  - message: A map containing notification data or a binary message

  ## Returns
  - {:ok, :sent} on success
  - {:error, reason} on failure
  """
  def send_message(notification) when is_map(notification) do
    # Check for string keys from JSON conversions
    if Map.has_key?(notification, "title") && Map.has_key?(notification, "description") do
      send_discord_embed(notification)
    else
      handle_notification_by_type(notification)
    end
  end

  # Send plain text messages
  def send_message(message) when is_binary(message) do
    send_text_message(message)
  end

  # Wrapper to safely send and catch exceptions
  defp safe_send(notification) do
    if Config.notifications_enabled?() do
      send_message(notification)
    else
      {:error, :notifications_disabled}
    end
  rescue
    exception ->
      {:exception, exception, __STACKTRACE__}
  end

  # Convert string notification types to atoms for consistent processing
  defp standardize_notification_type("kill"), do: :kill_notification
  defp standardize_notification_type("test"), do: :kill_notification
  defp standardize_notification_type("system"), do: :system_notification
  defp standardize_notification_type("character"), do: :character_notification
  defp standardize_notification_type(type) when is_atom(type), do: type
  defp standardize_notification_type(_), do: :unknown

  # Private function to handle different notification types
  defp handle_notification_by_type(%{type: :kill_notification} = kill) do
    handle_kill_notification(kill)
  end

  defp handle_notification_by_type(%{type: :system_notification} = system) do
    # Check if this is the first notification
    if Stats.is_first_notification?(:system) do
      # Skip notification for first run
      Stats.mark_notification_sent(:system)
      {:ok, :skipped_first_run}
    else
      # Send system notification
      send_system_notification(system)
    end
  end

  defp handle_notification_by_type(%{type: :character_notification} = character) do
    # Check if this is the first notification
    if Stats.is_first_notification?(:character) do
      # Skip notification for first run
      Stats.mark_notification_sent(:character)
      {:ok, :skipped_first_run}
    else
      # Send character activity notification
      send_character_activity_notification(character)
    end
  end

  defp handle_notification_by_type(%{type: :status_notification} = status) do
    # Handle status notifications (for startup and periodic status reports)
    AppLogger.info("Sending status notification", %{
      title: Map.get(status, :title, "Status")
    })

    send_discord_embed(status)
  end

  defp handle_notification_by_type(%{type: message_type} = notification)
       when is_atom(message_type) do
    # Convert the notification map to an embed if needed
    if Map.has_key?(notification, :title) && Map.has_key?(notification, :description) do
      send_discord_embed(notification)
    else
      Logger.warning("Unhandled notification type: #{inspect(message_type)}")
      {:error, :unknown_notification_type}
    end
  end

  defp handle_notification_by_type(other) do
    # For backwards compatibility, try to handle string messages
    if is_binary(other) do
      send_message(other)
    else
      Logger.error("Invalid notification format: #{inspect(other)}")
      {:error, :invalid_notification_format}
    end
  end

  # Handle kill notifications
  defp handle_kill_notification(kill) do
    notifier = get_notifier()

    if not Map.has_key?(kill, :data) or not Map.has_key?(kill.data, :killmail) do
      Logger.error("Invalid kill notification format: missing data.killmail field")
      {:error, :invalid_notification_format}
    else
      dispatch_kill_notification(notifier, kill)
    end
  end

  # Dispatch kill notifications to different notifiers
  defp dispatch_kill_notification(DiscordNotifier, kill) do
    killmail = kill.data.killmail
    system_id = Map.get(killmail, :system_id)
    has_tracked_system = KillDeterminer.tracked_system?(system_id)
    has_tracked_character = KillDeterminer.has_tracked_character?(killmail)

    # Get config module and retrieve settings once
    config = Config.get_config()

    character_notifications_enabled =
      case Map.fetch(config, :character_notifications_enabled) do
        {:ok, value} -> value
        :error -> Map.get(config, "character_notifications_enabled", false)
      end

    system_notifications_enabled =
      case Map.fetch(config, :system_notifications_enabled) do
        {:ok, value} -> value
        :error -> Map.get(config, "system_notifications_enabled", false)
      end

    # Determine which channel to use based on the kill type
    channel_id =
      determine_kill_channel_id(
        has_tracked_character,
        has_tracked_system,
        character_notifications_enabled,
        system_notifications_enabled
      )

    # Send to the appropriate channel
    if channel_id do
      DiscordNotifier.send_kill_notification_to_channel(killmail, channel_id)
    else
      DiscordNotifier.send_kill_notification(killmail)
    end

    {:ok, :sent}
  end

  # Use pattern matching with guards for channel determination
  defp determine_kill_channel_id(true, _has_tracked_system, true, _system_notifications_enabled) do
    Config.discord_character_kill_channel_id()
  end

  defp determine_kill_channel_id(
         _has_tracked_character,
         true,
         _character_notifications_enabled,
         true
       ) do
    Config.discord_system_kill_channel_id()
  end

  defp determine_kill_channel_id(
         _has_tracked_character,
         _has_tracked_system,
         _character_notifications_enabled,
         _system_notifications_enabled
       ) do
    Config.discord_channel_id()
  end

  # Helper functions for sending different types of notifications
  defp send_text_message(message) do
    notifier = get_notifier()
    notifier.send_notification(:send_message, [message])
  end

  defp send_discord_embed(embed) do
    notifier = get_notifier()
    notifier.send_notification(:send_discord_embed, [embed])
  end

  defp send_system_notification(embed) do
    notifier = get_notifier()
    channel_id = Config.discord_system_channel_id() || Config.discord_channel_id()

    if channel_id && channel_id != Config.discord_channel_id() do
      notifier.send_notification(:send_discord_embed_to_channel, [channel_id, embed])
    else
      notifier.send_notification(:send_discord_embed, [embed])
    end
  end

  defp send_character_activity_notification(embed) do
    notifier = get_notifier()
    channel_id = Config.discord_character_channel_id() || Config.discord_channel_id()

    if channel_id && channel_id != Config.discord_channel_id() do
      notifier.send_notification(:send_discord_embed_to_channel, [channel_id, embed])
    else
      notifier.send_notification(:send_discord_embed, [embed])
    end
  end

  @doc """
  Gets the appropriate notifier based on the current configuration.
  """
  def get_notifier do
    DiscordNotifier
  end
end
