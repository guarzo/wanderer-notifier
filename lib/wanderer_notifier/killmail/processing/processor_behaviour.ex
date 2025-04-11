defmodule WandererNotifier.Killmail.Processing.ProcessorBehaviour do
  @moduledoc """
  Defines the behaviour for killmail processors.
  """

  @callback init() :: :ok
  @callback get_recent_kills() :: list()
end
