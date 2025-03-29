defmodule WandererNotifier.Notifiers.Factory do
  @moduledoc """
  Factory module for creating and managing notifiers.
  """

  alias WandererNotifier.Core.Features
  alias WandererNotifier.Discord.Notifier, as: DiscordNotifier
  alias WandererNotifier.Notifiers.TestNotifier

  @doc """
  Sends a notification using the appropriate notifier based on the current configuration.
  """
  def notify(type, data) do
    if Features.notifications_enabled?() do
      do_notify(get_notifier(), type, data)
    else
      {:error, :notifications_disabled}
    end
  end

  @doc """
  Gets the appropriate notifier based on the current configuration.
  """
  def get_notifier do
    if Features.test_mode_enabled?() do
      TestNotifier
    else
      DiscordNotifier
    end
  end

  defp do_notify(notifier, type, data) do
    notifier.send_notification(type, data)
  end
end
