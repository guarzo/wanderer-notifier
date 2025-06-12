defmodule WandererNotifier.Cache.ETSCache do
  @moduledoc """
  Lightweight ETS-based cache implementation for testing.
  
  This provides a pure Elixir cache without external dependencies,
  making tests faster and more reliable.
  """
  
  @behaviour WandererNotifier.Cache.CacheBehaviour
  
  @table_name :wanderer_test_cache_ets
  
  @doc """
  Starts the ETS cache.
  """
  def start_link(opts \\ []) do
    table_name = Keyword.get(opts, :name, @table_name)
    
    case :ets.info(table_name) do
      :undefined ->
        :ets.new(table_name, [:set, :public, :named_table, read_concurrency: true])
        {:ok, table_name}
      _ ->
        {:ok, table_name}
    end
  end
  
  @impl true
  def get(key, opts \\ []) do
    table = Keyword.get(opts, :table, @table_name)
    
    case :ets.lookup(table, key) do
      [{^key, value, expiry}] ->
        if expired?(expiry) do
          :ets.delete(table, key)
          {:ok, nil}
        else
          {:ok, value}
        end
      [] ->
        {:ok, nil}
    end
  rescue
    ArgumentError -> {:error, :table_not_found}
  end
  
  @impl true
  def set(key, value, ttl) do
    table = @table_name
    expiry = calculate_expiry(ttl)
    
    :ets.insert(table, {key, value, expiry})
    {:ok, value}
  rescue
    ArgumentError -> {:error, :table_not_found}
  end
  
  @impl true
  def put(key, value) do
    # Put with no TTL (never expires)
    set(key, value, :infinity)
  end
  
  @impl true
  def delete(key) do
    :ets.delete(@table_name, key)
    :ok
  rescue
    ArgumentError -> {:error, :table_not_found}
  end
  
  @impl true
  def clear do
    :ets.delete_all_objects(@table_name)
    :ok
  rescue
    ArgumentError -> {:error, :table_not_found}
  end
  
  @impl true
  def get_and_update(key, update_fun) do
    case get(key) do
      {:ok, current_value} ->
        case update_fun.(current_value) do
          {get_value, new_value} ->
            if new_value == :pop do
              delete(key)
            else
              put(key, new_value)
            end
            {get_value, new_value}
          :pop ->
            delete(key)
            {current_value, nil}
          other ->
            raise ArgumentError, "Invalid return value from update function: #{inspect(other)}"
        end
      {:error, reason} ->
        {nil, {:error, reason}}
    end
  end
  
  @impl true
  def get_recent_kills do
    # For testing, return empty list
    []
  end
  
  @impl true
  def get_kill(kill_id) do
    case get("kill:#{kill_id}") do
      {:ok, kill} -> {:ok, kill}
      _ -> {:ok, %{}}
    end
  end
  
  
  @impl true
  def init_batch_logging do
    :ok
  end
  
  @impl true
  def mget(keys) when is_list(keys) do
    results = Enum.map(keys, fn key ->
      case get(key) do
        {:ok, value} -> {key, value}
        _ -> {key, nil}
      end
    end)
    
    {:ok, Map.new(results)}
  end
  
  # Private helpers
  
  defp calculate_expiry(:infinity), do: :infinity
  defp calculate_expiry(ttl) when is_integer(ttl) do
    System.system_time(:second) + ttl
  end
  
  defp expired?(:infinity), do: false
  defp expired?(expiry) when is_integer(expiry) do
    System.system_time(:second) > expiry
  end
  
  @doc """
  Cleans up expired entries. Can be called periodically if needed.
  """
  def cleanup_expired do
    now = System.system_time(:second)
    
    :ets.foldl(
      fn {key, _value, expiry}, acc ->
        if expiry != :infinity and expiry < now do
          :ets.delete(@table_name, key)
        end
        acc
      end,
      :ok,
      @table_name
    )
  rescue
    ArgumentError -> {:error, :table_not_found}
  end
end