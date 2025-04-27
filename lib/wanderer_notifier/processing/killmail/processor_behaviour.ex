defmodule WandererNotifier.Processing.Killmail.ProcessorBehaviour do
  @moduledoc """
  Defines the behavior for killmail processors
  """

  @callback init() :: :ok
  @callback get_recent_kills() :: {:ok, list()} | {:error, any()}
end
