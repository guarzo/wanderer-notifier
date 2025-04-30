defmodule WandererNotifier.Notification.Behaviour do
  @moduledoc """
  Defines the behaviour for notification handling.
  This includes both determination of what needs to be notified and formatting of notifications.
  """

  @doc """
  Determines if a notification should be sent based on the given context.
  Returns {:ok, notification_data} if a notification should be sent, {:ok, nil} if not.
  """
  @callback determine(context :: map()) :: {:ok, map() | nil} | {:error, any()}

  @doc """
  Formats a notification for delivery.
  Takes notification data and returns a formatted notification ready for delivery.
  """
  @callback format(notification_data :: map()) :: {:ok, map()} | {:error, any()}
end
