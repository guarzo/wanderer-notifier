defmodule WandererNotifier.Map.SystemBehaviour do
  @moduledoc """
  Behaviour module for system tracking functionality.
  """

  @callback is_tracked?(system_id :: String.t()) :: boolean()
end
