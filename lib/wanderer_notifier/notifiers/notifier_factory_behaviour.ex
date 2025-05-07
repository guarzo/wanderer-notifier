defmodule WandererNotifier.Notifiers.NotifierFactoryBehaviour do
  @moduledoc """
  Behaviour for NotifierFactory.
  """

  @callback notify(type :: atom(), args :: list()) :: any()
end
