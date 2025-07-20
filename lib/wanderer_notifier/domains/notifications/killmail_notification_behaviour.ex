defmodule WandererNotifier.Domains.Notifications.KillmailNotificationBehaviour do
  @moduledoc """
  Behaviour for creating killmail notifications.
  """

  @doc """
  Creates a notification from a killmail.
  """
  @callback create(killmail :: map()) :: term()
end
