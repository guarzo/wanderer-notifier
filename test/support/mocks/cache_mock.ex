defmodule WandererNotifier.Test.Support.Mocks.CacheMock do
  @moduledoc """
  Mock implementation of the cache behavior for testing.
  """

  alias WandererNotifier.Logger.Logger, as: AppLogger
  alias WandererNotifier.Cache.Keys, as: CacheKeys

  @behaviour WandererNotifier.Cache.CacheBehaviour

  # Mock state that can be configured per test
  def configure(systems, characters) do
    # Create the ETS table if it doesn't exist
    if :ets.info(:mock_cache) == :undefined do
      :ets.new(:mock_cache, [:set, :public, :named_table])
    end

    :ets.insert(:mock_cache, {:systems, systems})
    :ets.insert(:mock_cache, {:characters, characters})
  end

  def configure_direct_character(character_id, character_data) do
    # Create the ETS table if it doesn't exist
    if :ets.info(:mock_cache) == :undefined do
      :ets.new(:mock_cache, [:set, :public, :named_table])
    end

    :ets.insert(:mock_cache, {{:direct_character, character_id}, character_data})
  end

  @impl true
  def get(key, _opts \\ []) do
    case get_by_key_type(key) do
      {:ok, value} -> {:ok, value}
      {:error, _} = error -> error
    end
  end

  defp get_by_key_type(key) do
    cond do
      key == CacheKeys.map_systems() ->
        get_systems()

      key == CacheKeys.character_list() ->
        get_characters()

      is_binary(key) ->
        get_tracked_character(key)

      true ->
        {:error, :not_found}
    end
  end

  defp get_systems do
    case :ets.lookup(:mock_cache, :systems) do
      [{:systems, systems}] -> {:ok, systems}
      _ -> {:ok, []}
    end
  end

  defp get_characters do
    case :ets.lookup(:mock_cache, :characters) do
      [{:characters, characters}] -> {:ok, characters}
      _ -> {:ok, []}
    end
  end

  defp get_tracked_character(key) do
    case String.split(key, ":") do
      ["tracked", "character", character_id] ->
        get_direct_character(character_id)

      _ ->
        {:error, :not_found}
    end
  end

  defp get_direct_character(character_id) do
    case :ets.lookup(:mock_cache, {:direct_character, character_id}) do
      [{{:direct_character, ^character_id}, data}] -> {:ok, data}
      _ -> {:error, :not_found}
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
    [
      %{
        "killmail_id" => 12_345,
        "killmail_time" => "2023-01-01T12:00:00Z",
        "solar_system_id" => 30_000_142,
        "victim" => %{
          "character_id" => 93_345_033,
          "corporation_id" => 98_553_333,
          "ship_type_id" => 602
        },
        "zkb" => %{"hash" => "hash12345"}
      }
    ]
  end

  @impl true
  def get_kill(kill_id) do
    get(CacheKeys.kill(kill_id))
  end

  def get_latest_killmails do
    get(CacheKeys.recent_killmails_list())
  end

  @impl true
  def init_batch_logging, do: :ok

  @impl true
  def mget(_keys), do: {:error, :not_implemented}
end
