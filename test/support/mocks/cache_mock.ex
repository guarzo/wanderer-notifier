defmodule WandererNotifier.Test.Support.Mocks.CacheMock do
  @moduledoc """
  Mock implementation of the cache behavior for testing.
  """

  alias WandererNotifier.Logger.Logger, as: AppLogger

  @behaviour WandererNotifier.Cache.Behaviour

  @impl true
  def get(key, _opts \\ []) do
    if key == "test_key" do
      {:ok, "test_value"}
    else
      {:ok, Process.get({:cache, key})}
    end
  end

  @impl true
  def set(key, value, _ttl) do
    AppLogger.cache_debug("Setting cache value with TTL",
      key: key,
      value: value
    )

    Process.put({:cache, key}, value)
    :ok
  end

  @impl true
  def put(key, value) do
    Process.put({:cache, key}, value)
    :ok
  end

  @impl true
  def delete(key) do
    Process.delete({:cache, key})
    :ok
  end

  @impl true
  def clear do
    Process.get_keys()
    |> Enum.filter(fn
      {:cache, _} -> true
      _ -> false
    end)
    |> Enum.each(&Process.delete/1)

    :ok
  end

  @impl true
  def get_and_update(key, update_fun) do
    current = Process.get({:cache, key})
    {current_value, new_value} = update_fun.(current)
    Process.put({:cache, key}, new_value)
    {:ok, current_value}
  end

  @impl true
  def get_recent_kills do
    kills = Process.get({:cache, "zkill:recent_kills"}) || []

    if is_list(kills) && length(kills) > 0 do
      # Process kills into a map format expected by the controller - return in a tuple
      kills_map =
        kills
        |> Enum.map(fn id ->
          key = "zkill:recent_kills:#{id}"
          {id, Process.get({:cache, key})}
        end)
        |> Enum.reject(fn {_, v} -> is_nil(v) end)
        |> Enum.into(%{})

      {:ok, kills_map}
    else
      # Return empty map in a tuple
      {:ok, %{}}
    end
  end

  @impl true
  def get_kill(kill_id) do
    key = "zkill:recent_kills:#{kill_id}"

    case Process.get({:cache, key}) do
      nil -> {:error, :not_cached}
      value -> {:ok, value}
    end
  end

  @impl true
  def get_latest_killmails do
    # Get the list of kill IDs
    kill_ids = Process.get({:cache, "zkill:recent_kills"}) || []

    # Convert to a list of killmails
    kills =
      kill_ids
      |> Enum.map(fn id ->
        kill = Process.get({:cache, "zkill:recent_kills:#{id}"})
        if kill, do: Map.put(kill, "id", id), else: nil
      end)
      |> Enum.reject(&is_nil/1)

    # Format return value to match controller expectation
    {:ok, kills}
  end

  @impl true
  def init_batch_logging, do: :ok
end
