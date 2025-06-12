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
  @callback deduplication_module() :: module()
  @callback system_track_module() :: module()
  @callback character_track_module() :: module()
  @callback notification_determiner_module() :: module()
  @callback killmail_enrichment_module() :: module()
  @callback notification_dispatcher_module() :: module()
  @callback killmail_notification_module() :: module()
  @callback config_module() :: module()
end
