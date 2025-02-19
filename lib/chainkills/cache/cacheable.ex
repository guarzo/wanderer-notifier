defmodule ChainKills.Cache.Cacheable do
  @moduledoc """
  Provides a macro to wrap code with caching logic.
  """
  defmacro cacheable(key, ttl, do: block) do
    quote do
      case ChainKills.Cache.Repository.get(unquote(key)) do
        nil ->
          result = unquote(block)
          # Only cache successful responses (assumed to be in the form {:ok, _})
          case result do
            {:ok, _value} ->
              :ok = ChainKills.Cache.Repository.set(unquote(key), result, unquote(ttl))
              result

            _ ->
              result
          end

        cached ->
          cached
      end
    end
  end
end
