defmodule WandererNotifier.Cache do
  @moduledoc """
  Proxy module for WandererNotifier.Data.Cache.
  Delegates calls to the Data.Cache implementation.
  """

  @doc """
  Delegated to WandererNotifier.Data.Cache.Repository.get/1
  """
  def get(key) do
    WandererNotifier.Data.Cache.Repository.get(key)
  end

  @doc """
  Delegated to WandererNotifier.Data.Cache.Repository.set/3
  """
  def set(key, value, ttl) do
    WandererNotifier.Data.Cache.Repository.set(key, value, ttl)
  end

  @doc """
  Delegated to WandererNotifier.Data.Cache.Repository.put/2
  """
  def put(key, value) do
    WandererNotifier.Data.Cache.Repository.put(key, value)
  end

  @doc """
  Delegated to WandererNotifier.Data.Cache.Repository.delete/1
  """
  def delete(key) do
    WandererNotifier.Data.Cache.Repository.delete(key)
  end

  @doc """
  Delegated to WandererNotifier.Data.Cache.Repository.clear/0
  """
  def clear do
    WandererNotifier.Data.Cache.Repository.clear()
  end

  @doc """
  Delegated to WandererNotifier.Data.Cache.Repository.exists?/1
  """
  def exists?(key) do
    WandererNotifier.Data.Cache.Repository.exists?(key)
  end

  @doc """
  Delegated to WandererNotifier.Data.Cache.Repository.ttl/1
  """
  def ttl(key) do
    WandererNotifier.Data.Cache.Repository.ttl(key)
  end
end
