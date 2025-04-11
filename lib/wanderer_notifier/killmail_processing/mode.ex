defmodule WandererNotifier.KillmailProcessing.Mode do
  @moduledoc """
  @deprecated Please use WandererNotifier.Killmail.Core.Mode instead

  This module is deprecated and will be removed in a future release.
  All functionality has been moved to WandererNotifier.Killmail.Core.Mode.
  """

  alias WandererNotifier.Killmail.Core.Mode

  # Re-export the types for backward compatibility
  @type t :: Mode.t()
  @type options :: Mode.options()

  # Delegate all functions to the new module
  defdelegate new(mode, options \\ %{}), to: Mode
  defdelegate default_options(mode), to: Mode
end
