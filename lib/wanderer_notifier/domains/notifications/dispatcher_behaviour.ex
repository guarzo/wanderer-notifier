defmodule WandererNotifier.Domains.Notifications.DispatcherBehaviour do
  @moduledoc """
  Behaviour for notification dispatching.
  Defines the contract for modules that send notifications.
  """

  @doc """
  Sends a formatted notification message.

  ## Parameters
  - notification: The formatted notification to send

  ## Returns
  - {:ok, :sent} on success
  - {:error, reason} on failure
  """
  @callback send_message(notification :: map()) :: {:ok, :sent} | {:error, term()}
end
