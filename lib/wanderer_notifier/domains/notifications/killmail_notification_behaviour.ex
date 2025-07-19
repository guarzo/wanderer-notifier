defmodule WandererNotifier.Domains.Notifications.KillmailNotificationBehaviour do
  @moduledoc """
  Behaviour for killmail notification creation.
  Defines the contract for modules that create killmail notifications.
  """

  @doc """
  Creates a notification from a killmail.

  ## Parameters
  - killmail: The killmail struct to create a notification from

  ## Returns
  - A formatted notification ready to be sent
  """
  @callback create(killmail :: struct()) :: map()
end
