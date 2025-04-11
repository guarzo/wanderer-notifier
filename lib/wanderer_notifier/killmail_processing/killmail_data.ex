defmodule WandererNotifier.KillmailProcessing.KillmailData do
  @moduledoc """
  @deprecated Please use WandererNotifier.Killmail.Core.Data instead

  This module is deprecated and will be removed in a future release.
  All functionality has been moved to WandererNotifier.Killmail.Core.Data.
  """

  alias WandererNotifier.Killmail.Core.Data

  # Re-export the type for backward compatibility
  @type t :: Data.t()

  # Delegate all functions to the new module
  defdelegate from_zkb_and_esi(zkb_data, esi_data), to: Data
  defdelegate from_resource(resource), to: Data
end
