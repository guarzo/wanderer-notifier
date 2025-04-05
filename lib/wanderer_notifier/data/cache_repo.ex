defmodule WandererNotifier.Data.CacheRepo do
  @moduledoc """
  In-memory cache repository for storing frequently accessed data.
  Uses :ets tables for fast access and automatic expiration.
  """

  use GenServer
  require Logger

  @table_name :wanderer_cache
  @cleanup_interval :timer.minutes(5)
  @default_ttl :timer.minutes(30)

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  @doc """
  Gets a value from the cache.
  Returns nil if the key doesn't exist or has expired.
  """
  def get(key) do
    case :ets.lookup(@table_name, key) do
      [{^key, value, expires_at}] ->
        if expires_at > System.system_time(:second) do
          value
        else
          nil
        end

      [] ->
        nil
    end
  end

  @doc """
  Puts a value in the cache with optional TTL.
  TTL defaults to 1 hour if not specified.
  """
  def put(key, value, opts \\ []) do
    ttl = Keyword.get(opts, :ttl, @default_ttl)
    expires_at = System.system_time(:second) + ttl
    :ets.insert(@table_name, {key, value, expires_at})
    {:ok, value}
  end

  @doc """
  Deletes a value from the cache.
  """
  def delete(key) do
    :ets.delete(@table_name, key)
    :ok
  end

  # GenServer callbacks

  @impl true
  def init(_) do
    # Create ETS table if it doesn't exist
    :ets.new(@table_name, [:set, :public, :named_table, read_concurrency: true])
    schedule_cleanup()
    {:ok, %{}}
  end

  @impl true
  def handle_info(:cleanup, state) do
    now = System.system_time(:second)
    # Delete expired entries
    :ets.select_delete(@table_name, [{{:_, :_, :"$1"}, [{:<, :"$1", now}], [true]}])
    schedule_cleanup()
    {:noreply, state}
  end

  defp schedule_cleanup do
    Process.send_after(self(), :cleanup, @cleanup_interval)
  end
end
