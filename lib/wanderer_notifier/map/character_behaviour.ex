defmodule WandererNotifier.Map.CharacterBehaviour do
  @moduledoc """
  Behaviour for character tracking functionality.
  """

  @callback is_tracked?(character_id :: String.t()) :: {:ok, boolean()} | {:error, any()}
end
