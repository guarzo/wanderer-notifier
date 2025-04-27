defmodule WandererNotifier.Notifications.FactoryBehaviour do
  @moduledoc """
  Behaviour for notification factory.
  """

  @type notification_type :: :send_discord_embed | atom()
  @type notification_args :: list()
  @type notification_result :: {:ok, map()} | {:error, any()}

  @callback notify(notification_type(), notification_args()) :: notification_result()
end
