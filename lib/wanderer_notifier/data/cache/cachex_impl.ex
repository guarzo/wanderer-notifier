defmodule WandererNotifier.Data.Cache.CachexImpl do
  @moduledoc """
  Cachex-based implementation of the cache behaviour.
  """

  @behaviour WandererNotifier.Data.Cache.CacheBehaviour

  require Logger

  @cache_name Application.compile_env(:wanderer_notifier, :cache_name, :wanderer_cache)

  @impl true
  def get(key) do
    case Cachex.get(@cache_name, key) do
      {:ok, value} when not is_nil(value) -> value
      _ -> handle_nil_result(key)
    end
  rescue
    e ->
      Logger.error("[Cache] Error getting value for key: #{key}, error: #{inspect(e)}")
      nil
  end

  @impl true
  def set(key, value, ttl) do
    Cachex.put(@cache_name, key, value, ttl: ttl * 1000)
  rescue
    e ->
      Logger.error("[Cache] Error setting value for key: #{key}, error: #{inspect(e)}")
      {:error, e}
  end

  @impl true
  def put(key, value) do
    Cachex.put(@cache_name, key, value)
  rescue
    e ->
      Logger.error("[Cache] Error putting value for key: #{key}, error: #{inspect(e)}")
      {:error, e}
  end

  @impl true
  def delete(key) do
    Cachex.del(@cache_name, key)
  rescue
    e ->
      Logger.error("[Cache] Error deleting key: #{key}, error: #{inspect(e)}")
      {:error, e}
  end

  @impl true
  def clear do
    Cachex.clear(@cache_name)
  rescue
    e ->
      Logger.error("[Cache] Error clearing cache: #{inspect(e)}")
      {:error, e}
  end

  @impl true
  def get_and_update(key, update_fun) do
    current = get(key)
    {get_value, new_value} = update_fun.(current)
    result = put(key, new_value)
    {get_value, result}
  rescue
    e ->
      Logger.error("[Cache] Error in get_and_update for key: #{key}, error: #{inspect(e)}")
      {nil, {:error, e}}
  end

  defp handle_nil_result(key) do
    if key in ["map:systems", "map:characters"], do: [], else: nil
  end
end
