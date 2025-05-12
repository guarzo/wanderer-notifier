defmodule WandererNotifier.Notifications.Dispatcher do
  @moduledoc """
  Dispatcher for creating and sending notifications.
  Provides a unified interface for sending notifications of various types.
  """
  @behaviour WandererNotifier.Notifications.DispatcherBehaviour

  require Logger
  alias WandererNotifier.Config
  alias WandererNotifier.Notifiers.Discord.Notifier, as: DiscordNotifier
  alias WandererNotifier.Notifiers.TestNotifier
  alias WandererNotifier.Logger.Logger, as: AppLogger

  @doc """
  Sends a notification using the appropriate notifier based on the current configuration.

  ## Parameters
  - type: The type of notification to send (e.g. :send_discord_embed)
  - data: The data to include in the notification (content varies based on type)

  ## Returns
  - {:ok, result} on success
  - {:error, reason} on failure
  """
  def run(type, data) do
    if Config.notifications_enabled?() do
      do_notify(get_notifier(), type, data)
    else
      {:error, :notifications_disabled}
    end
  end

  @doc """
  Gets the appropriate notifier based on the current configuration.
  """
  def get_notifier do
    if Config.test_mode_enabled?(), do: TestNotifier, else: DiscordNotifier
  end

  defp do_notify(notifier, :send_system_kill_discord_embed, [embed]) do
    # Get the channel ID for system kill notifications
    channel_id = Config.discord_system_kill_channel_id()

    if is_nil(channel_id) do
      # Fall back to main channel if no dedicated channel is configured
      notifier.send_notification(:send_discord_embed, [embed])
    else
      # Send to the system kill channel
      notifier.send_notification(:send_discord_embed_to_channel, [channel_id, embed])
    end
  end

  defp do_notify(notifier, :send_character_kill_discord_embed, [embed]) do
    # Get the channel ID for character kill notifications
    channel_id = Config.discord_character_kill_channel_id()

    if is_nil(channel_id) do
      # Fall back to main channel if no dedicated channel is configured
      notifier.send_notification(:send_discord_embed, [embed])
    else
      # Send to the character kill channel
      notifier.send_notification(:send_discord_embed_to_channel, [channel_id, embed])
    end
  end

  defp do_notify(notifier, type, data) do
    notifier.send_notification(type, data)
  end

  @doc """
  Implementation of DispatcherBehaviour.send_message/1
  Handles sending a notification based on its type.

  ## Parameters
  - notification: A map containing notification data with a :type field
    that determines how the notification should be processed

  ## Returns
  - {:ok, :sent} on success
  - {:error, reason} on failure
  """
  @impl true
  def send_message(notification) when is_map(notification) do
    # Check for string keys from JSON conversions (specifically for CommonFormatter.to_discord_format output)
    if Map.has_key?(notification, "title") && Map.has_key?(notification, "description") do
      # Handle status notification with string keys (from CommonFormatter.to_discord_format)
      AppLogger.info(
        "Sending notification with string keys",
        %{title: Map.get(notification, "title", "Unknown")}
      )

      send_discord_embed(notification)
    else
      # Handle notifications with atom keys
      # Route to appropriate handler based on notification type
      handle_notification_by_type(notification)
    end
  end

  # Send plain text messages
  def send_message(message) when is_binary(message) do
    run(:send_message, [message])
  end

  # Private function to handle different notification types
  defp handle_notification_by_type(%{type: :kill_notification} = kill) do
    # Handle a killmail notification
    handle_kill_notification(kill)
  end

  defp handle_notification_by_type(%{type: :system_notification} = system) do
    # Send system notification
    send_system_notification(system)
  end

  defp handle_notification_by_type(%{type: :character_notification} = character) do
    # Send character activity notification
    send_character_activity_notification(character)
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

  # Handle kill notifications, separates complex logic
  defp handle_kill_notification(kill) do
    notifier = get_notifier()

    if not Map.has_key?(kill, :data) or not Map.has_key?(kill.data, :killmail) do
      Logger.error("Invalid kill notification format: missing data.killmail field")
      {:error, :invalid_notification_format}
    else
      dispatch_kill_notification(notifier, kill)
    end
  end

  # Separate function for dispatching kill notifications to different notifiers
  defp dispatch_kill_notification(DiscordNotifier, kill) do
    # Use dynamic dispatch to avoid compiler warnings
    apply(DiscordNotifier, :send_kill_notification, [kill.data.killmail])
    {:ok, :sent}
  end

  defp dispatch_kill_notification(notifier, kill) do
    # TestNotifier or other - use generic notification
    AppLogger.kill_info(
      "Using generic notification for kill",
      %{notifier: inspect(notifier)}
    )

    run(:send_discord_embed, [kill])
  end

  @doc """
  Sends a system activity notification.

  ## Parameters
  - embed: The formatted embed to send

  ## Returns
  - {:ok, result} on success
  - {:error, reason} on failure
  """
  def send_system_activity_notification(embed) do
    run(:send_system_activity_discord_embed, [embed])
  end

  @doc """
  Sends a character activity notification.

  ## Parameters
  - embed: The formatted embed to send

  ## Returns
  - {:ok, result} on success
  - {:error, reason} on failure
  """
  def send_character_activity_notification(embed) do
    run(:send_character_activity_discord_embed, [embed])
  end

  @doc """
  Sends a Discord embed.

  ## Parameters
  - embed: The formatted embed to send

  ## Returns
  - {:ok, result} on success
  - {:error, reason} on failure
  """
  def send_discord_embed(embed) do
    run(:send_discord_embed, [embed])
  end

  @doc """
  Sends a system notification.

  ## Parameters
  - embed: The formatted embed to send

  ## Returns
  - {:ok, result} on success
  - {:error, reason} on failure
  """
  def send_system_notification(embed) do
    run(:send_system_discord_embed, [embed])
  end
end
