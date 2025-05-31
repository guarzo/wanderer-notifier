defmodule WandererNotifier.Cache.KeyGenerator do
  @moduledoc """
  Provides macros for generating cache key functions.
  """

  # The _opts parameter is reserved for future options and extensibility
  defmacro defkey(name, prefix, entity, _opts \\ []) do
    quote do
      @doc "Key for #{unquote(entity)}"
      @spec unquote(name)(integer() | String.t(), String.t() | nil) :: String.t()
      def unquote(name)(id, extra \\ nil) do
        combine([unquote(prefix), unquote(entity)], [id], extra)
      end
    end
  end
end
