defmodule WandererNotifier.Helpers.DeduplicationHelper do
  @moduledoc """
  Helper module for handling deduplication of notifications.
  """

  use GenServer
  alias WandererNotifier.Data.Cache.Repository, as: CacheRepo

  # Default TTL for deduplication entries (24 hours)
  @dedup_ttl 86_400

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  @impl true
  def init(_) do
    {:ok, %{}}
  end

  @doc """
  Checks if a given ID for a specific type is a duplicate.
  Returns {:ok, :new} if not seen before, {:ok, :duplicate} if already seen,
  or {:error, reason} if there's an error.
  """
  @spec duplicate?(atom(), String.t() | integer()) ::
          {:ok, :new} | {:ok, :duplicate} | {:error, String.t()}
  def duplicate?(type, id) when is_atom(type) and (is_binary(id) or is_integer(id)) do
    cache_key = "#{type}:#{id}"

    try do
      case CacheRepo.get(cache_key) do
        nil ->
          CacheRepo.set(cache_key, true, @dedup_ttl)
          {:ok, :new}

        %{status: _status, reason: _reason} ->
          {:ok, :duplicate}

        _ ->
          {:ok, :duplicate}
      end
    rescue
      e -> {:error, Exception.message(e)}
    end
  end

  @doc """
  Clears a deduplication key from the cache.
  """
  def handle_clear_key(key) do
    GenServer.cast(__MODULE__, {:clear_key, key})
  end

  @impl true
  def handle_cast({:clear_key, key}, state) do
    CacheRepo.delete(key)
    {:noreply, state}
  end

  # When marking a killmail as seen, store the status and reason
  def mark_kill_status(kill_id, status, reason \\ nil) do
    cache_key = "kill:#{kill_id}"
    CacheRepo.set(cache_key, %{status: status, reason: reason}, @dedup_ttl)
  end

  # When checking for duplicates, return the cached value if present
  def duplicate_with_status?(kill_id) do
    cache_key = "kill:#{kill_id}"

    case CacheRepo.get(cache_key) do
      nil -> {:ok, :new}
      %{status: status, reason: reason} -> {:ok, :duplicate, status, reason}
      _ -> {:ok, :duplicate, nil, nil}
    end
  end
end
