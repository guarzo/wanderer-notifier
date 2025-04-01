defmodule WandererNotifier.Notifiers.DiscordNotifierBehaviour do
  @moduledoc """
  Behaviour specification for Discord notification service.
  Defines the contract that any Discord notifier implementation must fulfill.
  """

  @type notification_type :: :kill | :system | :character | :activity
  @type notification_data :: map()
  @type channel_id :: String.t()
  @type response :: {:ok, term()} | {:error, term()}
  @type embed :: map()

  @doc """
  Sends a notification to a Discord channel.

  ## Parameters
    - type: The type of notification to send
    - data: The notification data to send

  ## Returns
    - {:ok, term()} on success
    - {:error, term()} on failure
  """
  @callback send_notification(type :: notification_type(), data :: notification_data()) ::
              response

  @doc """
  Sends a notification to a specific Discord channel.

  ## Parameters
    - channel_id: The ID of the channel to send the notification to
    - data: The notification data to send

  ## Returns
    - {:ok, term()} on success
    - {:error, term()} on failure
  """
  @callback send_to_channel(channel_id :: channel_id(), data :: notification_data()) :: response

  @doc """
  Sends a Discord embed message.

  ## Parameters
    - embed: The embed data to send

  ## Returns
    - {:ok, term()} on success
    - {:error, term()} on failure
  """
  @callback send_discord_embed(embed :: embed()) :: response
end
