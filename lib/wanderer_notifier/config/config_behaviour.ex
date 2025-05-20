defmodule WandererNotifier.Config.ConfigBehaviour do
  @moduledoc """
  Behaviour for application configuration.
  """

  @callback notifications_enabled?() :: boolean()
  @callback kill_notifications_enabled?() :: boolean()
  @callback system_notifications_enabled?() :: boolean()
  @callback character_notifications_enabled?() :: boolean()
  @callback get_notification_setting(type :: atom(), key :: atom()) ::
              {:ok, boolean()} | {:error, term()}
  @callback get_config() :: map()
end
