defmodule WandererNotifier.Domains.Notifications.DiscordNotifier do
  @moduledoc """
  Handles sending notifications to Discord.
  """

  @behaviour WandererNotifier.Domains.Notifications.DiscordNotifierBehaviour

  @doc """
  Sends a kill notification to Discord.

  ## Parameters
    - killmail: The enriched killmail data
    - type: The type of notification (e.g., "kill", "test")
    - options: Additional options for the notification

  ## Returns
    - :ok on success
    - {:error, reason} on failure
  """
  @impl true
  def send_kill_notification(_killmail, _type, _options) do
    # Implementation will be added later
    :ok
  end

  @doc """
  Sends a test notification to Discord.

  ## Returns
    - :ok on success
    - {:error, reason} on failure
  """
  @impl true
  def send_test_notification do
    # Implementation will be added later
    :ok
  end

  @doc """
  Sends a Discord embed message.

  ## Parameters
    - embed: The embed data to send

  ## Returns
    - :ok on success
    - {:error, reason} on failure
  """
  @impl true
  def send_discord_embed(_embed) do
    # Implementation will be added later
    :ok
  end
end
