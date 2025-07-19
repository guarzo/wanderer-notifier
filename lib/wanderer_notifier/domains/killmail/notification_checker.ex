defmodule WandererNotifier.Domains.Killmail.NotificationChecker do
  @moduledoc """
  Adapter module for checking if a killmail should trigger a notification.
  Simplifies the interface between the pipeline and the notification determiner.
  """

  alias WandererNotifier.Domains.Killmail.Killmail
  alias WandererNotifier.Domains.Notifications.Determiner.Kill

  @type killmail_data :: Killmail.t() | map()
  @type notification_result ::
          {:ok, %{should_notify: boolean, reason: String.t() | nil}} | {:error, term()}

  @doc """
  Determines if a notification should be sent for a killmail.
  Returns the full response from the Kill determiner.

  ## Parameters
  - killmail: The killmail to check

  ## Returns
  - {:ok, %{should_notify: true}} if notification should be sent
  - {:ok, %{should_notify: false, reason: reason}} if notification should not be sent
  - {:error, reason} if there was an error
  """
  @spec should_notify?(killmail_data()) :: notification_result()
  def should_notify?(%Killmail{} = killmail) do
    Kill.should_notify?(killmail)
  end

  def should_notify?(killmail) when is_map(killmail) do
    Kill.should_notify?(killmail)
  end
end
