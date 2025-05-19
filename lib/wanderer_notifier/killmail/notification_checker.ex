defmodule WandererNotifier.Killmail.NotificationChecker do
  @moduledoc """
  Adapter module for checking if a killmail should trigger a notification.
  Simplifies the interface between the pipeline and the notification determiner.
  """

  alias WandererNotifier.Killmail.Killmail
  alias WandererNotifier.Notifications.Determiner.Kill

  @doc """
  Determines if a notification should be sent for a killmail.
  Returns a boolean for use in a with expression.

  ## Parameters
  - killmail: The killmail to check

  ## Returns
  - true if notification should be sent
  - false if notification should not be sent
  """
  @spec should_notify?(Killmail.t()) :: boolean()
  def should_notify?(killmail) do
    case Kill.should_notify?(killmail) do
      {:ok, %{should_notify: true}} -> true
      {:ok, %{should_notify: false}} -> false
      {:error, _reason} -> false
    end
  end
end
