defmodule WandererNotifier.Shared.Config.ConfigBehaviour do
  @moduledoc """
  Behaviour for application configuration.
  """

  @doc """
  Returns whether notifications are enabled globally.
  """
  @callback notifications_enabled?() :: boolean()

  @doc """
  Returns whether kill notifications are enabled.
  """
  @callback kill_notifications_enabled?() :: boolean()

  @doc """
  Returns whether system notifications are enabled.
  """
  @callback system_notifications_enabled?() :: boolean()

  @doc """
  Returns whether character notifications are enabled.
  """
  @callback character_notifications_enabled?() :: boolean()

  @doc """
  Gets a specific notification setting by type and key.
  """
  @callback get_notification_setting(type :: atom(), key :: atom()) ::
              {:ok, boolean()} | {:error, term()}

  @doc """
  Returns the current configuration as a map.
  """
  @callback get_config() :: map()

  @doc """
  Returns the module responsible for notification deduplication.
  """
  @callback deduplication_module() :: module()

  @doc """
  Returns the module responsible for system tracking.
  """
  @callback system_track_module() :: module()

  @doc """
  Returns the module responsible for character tracking.
  """
  @callback character_track_module() :: module()

  @doc """
  Returns the module responsible for determining notification eligibility.
  """
  @callback notification_determiner_module() :: module()

  @doc """
  Returns the module responsible for killmail data enrichment.
  """
  @callback killmail_enrichment_module() :: module()

  @doc """
  Returns the module responsible for killmail notifications.
  """
  @callback killmail_notification_module() :: module()
end
