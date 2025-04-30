defmodule WandererNotifier.Notifications.Factory do
  @moduledoc """
  Factory for creating and sending notifications.
  Implements the NotificationsFactoryBehaviour and provides a unified interface
  for sending notifications of various types.
  """

  require Logger
  alias WandererNotifier.Config.Features
  alias WandererNotifier.Logger.Logger, as: AppLogger
  alias WandererNotifier.Notifiers.Factory, as: NotifierFactory

  @behaviour WandererNotifier.Notifications.FactoryBehaviour

  @doc """
  Sends a notification using the appropriate notifier based on the current configuration.

  This function implements the FactoryBehaviour callback and handles all notification types.

  ## Parameters
  - type: The type of notification to send (e.g. :send_discord_embed)
  - data: The data to include in the notification (content varies based on type)

  ## Returns
  - {:ok, result} on success
  - {:error, reason} on failure
  """
  @impl WandererNotifier.Notifications.FactoryBehaviour
  def notify(type, data) do
    if Features.notifications_enabled?() do
      AppLogger.notification_debug("Sending notification", %{
        type: type,
        data_size: length(data)
      })

      # Delegate to the Notifiers.Factory for actual notification sending
      case NotifierFactory.notify(type, data) do
        :ok ->
          {:ok, :sent}

        {:ok, result} ->
          {:ok, result}

        {:error, reason} ->
          AppLogger.notification_error("Failed to send notification", %{
            type: type,
            error: inspect(reason)
          })

          {:error, reason}
      end
    else
      AppLogger.notification_debug("Notifications disabled, skipping", %{type: type})
      {:error, :notifications_disabled}
    end
  end

  @doc """
  Sends a kill notification to the system channel.

  ## Parameters
  - embed: The formatted embed to send

  ## Returns
  - {:ok, result} on success
  - {:error, reason} on failure
  """
  def send_system_kill_notification(embed) do
    notify(:send_system_kill_discord_embed, [embed])
  end

  @doc """
  Sends a kill notification to the character channel.

  ## Parameters
  - embed: The formatted embed to send

  ## Returns
  - {:ok, result} on success
  - {:error, reason} on failure
  """
  def send_character_kill_notification(embed) do
    notify(:send_character_kill_discord_embed, [embed])
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
    notify(:send_system_activity_discord_embed, [embed])
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
    notify(:send_character_activity_discord_embed, [embed])
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
    notify(:send_message, [message])
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
    notify(:send_system_discord_embed, [embed])
  end
end
