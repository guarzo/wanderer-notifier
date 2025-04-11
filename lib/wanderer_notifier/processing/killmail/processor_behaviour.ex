defmodule WandererNotifier.Processing.Killmail.ProcessorBehaviour do
  @moduledoc """
  @deprecated Please use WandererNotifier.Killmail.Processing.ProcessorBehaviour instead

  This module is deprecated and will be removed in a future release.
  All functionality has been moved to WandererNotifier.Killmail.Processing.ProcessorBehaviour.
  """

  @callback init() :: :ok
  @callback get_recent_kills() :: list()
end
