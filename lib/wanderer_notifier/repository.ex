defmodule WandererNotifier.Repository do
  @moduledoc """
  Repository for database operations.
  """

  alias WandererNotifier.Helpers.CacheHelpers

  @spec get_tracked_characters() :: [map()]
  def get_tracked_characters do
    CacheHelpers.get_tracked_characters()
  end
end
