defmodule WandererNotifier.Map.CharacterBehaviour do
  @moduledoc """
  Behaviour module for character tracking functionality.
  """

  @callback is_tracked?(character_id :: String.t()) :: boolean()
end
