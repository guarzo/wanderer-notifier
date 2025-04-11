defmodule WandererNotifier.KillmailProcessing.Context do
  @moduledoc """
  @deprecated Please use WandererNotifier.Killmail.Core.Context instead

  This module is deprecated and will be removed in a future release.
  All functionality has been moved to WandererNotifier.Killmail.Core.Context.
  """

  alias WandererNotifier.Killmail.Core.Context

  # Re-export the type for backward compatibility
  @type t :: Context.t()
  @type source :: Context.source()

  # Delegate all functions to the new module
  defdelegate new_historical(character_id, character_name, source, batch_id, options \\ %{}),
    to: Context

  defdelegate new_realtime(character_id, character_name, source, options \\ %{}), to: Context
  defdelegate historical?(context), to: Context
  defdelegate realtime?(context), to: Context
end
