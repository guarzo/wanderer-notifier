defmodule WandererNotifier.Domains.Notifications.KillmailNotification do
  @moduledoc """
  Creates notifications for killmails.
  """

  alias WandererNotifier.Domains.Notifications.Notification

  @doc """
  Creates a notification from a killmail.

  ## Parameters
    - killmail: The killmail data to create a notification for

  ## Returns
    - %Notification{} with type :kill_notification and the killmail data
  """
  def create(killmail) when is_map(killmail) do
    %Notification{
      type: :kill_notification,
      data: %{killmail: killmail}
    }
  end

  def create(_killmail) do
    raise ArgumentError, "killmail must be a map"
  end
end
