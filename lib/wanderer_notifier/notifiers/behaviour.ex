defmodule WandererNotifier.Notifiers.Behaviour do
  @moduledoc """
  Defines the behaviour for notification delivery.
  This includes sending notifications through various channels (e.g., Discord).
  """

  @doc """
  Sends a notification through the specified channel.
  Takes formatted notification data and delivers it.
  """
  @callback notify(notification :: map()) :: :ok | {:error, any()}

  @doc """
  Initializes the notifier with the given configuration.
  """
  @callback init(config :: map()) :: :ok | {:error, any()}

  @doc """
  Returns the configuration for the notifier.
  """
  @callback get_config() :: map()

  @optional_callbacks [init: 1, get_config: 0]
end
