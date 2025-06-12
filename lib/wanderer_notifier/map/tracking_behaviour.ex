defmodule WandererNotifier.Map.TrackingBehaviour do
  @moduledoc """
  Generic behaviour for tracking functionality.
  Supports both character and system tracking with consistent interface.
  """

  @type tracking_id :: String.t() | integer()
  @type tracking_result :: {:ok, boolean()} | {:error, any()}

  @doc """
  Checks if an entity (character or system) is being tracked.

  ## Parameters
  - `id`: The ID of the entity to check (string or integer)

  ## Returns
  - `{:ok, true}` if the entity is tracked
  - `{:ok, false}` if the entity is not tracked  
  - `{:error, reason}` if there was an error checking tracking status
  """
  @callback is_tracked?(id :: tracking_id()) :: tracking_result()
end
