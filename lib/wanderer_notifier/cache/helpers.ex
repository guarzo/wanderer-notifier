defmodule WandererNotifier.Cache.Helpers do
  @moduledoc """
  Helper functions for caching operations.
  """

  alias WandererNotifier.Helpers.CacheHelpers

  def get_cached_kills(character_id) do
    CacheHelpers.get_cached_kills(character_id)
  end
end
