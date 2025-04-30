defmodule WandererNotifier.Notifications.FactoryBehaviour do
  @moduledoc """
  Defines the behaviour for notification factories in the WandererNotifier application.
  """

  @callback notify(type :: atom(), data :: map()) :: :ok | {:error, term()}
end
