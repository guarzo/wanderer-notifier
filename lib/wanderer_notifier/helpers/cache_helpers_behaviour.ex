defmodule WandererNotifier.Helpers.CacheHelpersBehaviour do
  @moduledoc """
  Behaviour module for cache helper functions.
  """

  @callback get_cached_value(String.t()) :: {:ok, any()} | {:error, :not_found}
  @callback set_cached_value(String.t(), any(), non_neg_integer() | nil) :: :ok
  @callback delete_cached_value(String.t()) :: :ok
  @callback exists?(String.t()) :: boolean()
end
