defmodule WandererNotifier.MockZKillClient do
  @moduledoc """
  Mock implementation of the ZKillboard client for testing.
  """

  @behaviour WandererNotifier.Api.ZKill.ClientBehaviour

  @impl true
  def get_single_killmail(_kill_id), do: {:ok, []}

  @impl true
  def get_recent_kills(_limit \\ 10), do: {:ok, []}

  @impl true
  def get_system_kills(_system_id, _limit \\ 5), do: {:ok, []}

  @impl true
  def get_character_kills(_character_id, _limit \\ 25, _page \\ 1), do: {:ok, []}
end

defmodule WandererNotifier.MockESI do
  @moduledoc """
  Mock implementation of the ESI service for testing.
  """

  @behaviour WandererNotifier.Api.ESI.ServiceBehaviour

  @impl true
  def get_killmail(_kill_id, _hash), do: {:ok, %{}}

  @impl true
  def get_character_info(_character_id), do: {:ok, %{}}

  @impl true
  def get_corporation_info(_corporation_id), do: {:ok, %{}}

  @impl true
  def get_alliance_info(_alliance_id), do: {:ok, %{}}

  @impl true
  def get_system_info(_system_id), do: {:ok, %{}}

  @impl true
  def get_type_info(_type_id), do: {:ok, %{}}

  @impl true
  def get_system(_system_id), do: {:ok, %{}}

  @impl true
  def get_character(_character_id), do: {:ok, %{}}

  @impl true
  def get_type(_type_id), do: {:ok, %{}}
end

defmodule WandererNotifier.MockCacheHelpers do
  @moduledoc """
  Mock implementation of the cache helpers for testing.
  """

  @behaviour WandererNotifier.Helpers.CacheHelpersBehaviour

  @impl true
  def get_cached_kills(_character_id), do: {:ok, []}

  @impl true
  def get_character_name(_character_id), do: {:ok, "Test Character"}

  @impl true
  def get_ship_name(_ship_id), do: {:ok, "Test Ship"}

  @impl true
  def get_tracked_characters, do: {:ok, []}
end

defmodule WandererNotifier.MockRepository do
  @moduledoc """
  Mock implementation of the repository for testing.
  """

  @behaviour WandererNotifier.Data.Cache.RepositoryBehaviour

  @impl true
  def delete(_key), do: :ok

  @impl true
  def exists?(_key), do: false

  @impl true
  def get(_key), do: nil

  @impl true
  def get_and_update(_key, _fun), do: {nil, nil}

  @impl true
  def get_tracked_characters, do: []

  @impl true
  def put(_key, _value), do: :ok

  @impl true
  def set(_key, _value, _ttl), do: :ok
end

defmodule WandererNotifier.MockKillmailPersistence do
  @moduledoc """
  Mock implementation of the killmail persistence service for testing.
  """

  @behaviour WandererNotifier.Resources.KillmailPersistenceBehaviour

  @impl true
  def maybe_persist_killmail(_killmail), do: {:ok, %{}}

  @impl true
  def persist_killmail(_killmail), do: :ok
end

defmodule WandererNotifier.MockLogger do
  @moduledoc """
  Mock implementation of the logger for testing.
  """

  def debug(_message, _metadata \\ []), do: :ok
  def info(_message, _metadata \\ []), do: :ok
  def warn(_message, _metadata \\ []), do: :ok
  def error(_message, _metadata \\ []), do: :ok
  def api_debug(_message, _metadata \\ []), do: :ok
  def api_info(_message, _metadata \\ []), do: :ok
  def api_warn(_message, _metadata \\ []), do: :ok
  def api_error(_message, _metadata \\ []), do: :ok
  def websocket_info(_message, _metadata \\ []), do: :ok
  def websocket_error(_message, _metadata \\ []), do: :ok
end

defmodule WandererNotifier.MockConfig do
  @moduledoc """
  Mock implementation of the config for testing.
  """

  @behaviour WandererNotifier.Core.ConfigBehaviour

  def start_link do
    Agent.start_link(
      fn ->
        %{
          kill_charts_enabled: true,
          map_charts_enabled: true,
          env: :test
        }
      end,
      name: __MODULE__
    )
  end

  def set_kill_charts_enabled(value) do
    Agent.update(__MODULE__, &Map.put(&1, :kill_charts_enabled, value))
  end

  @impl true
  def get_config(_key, default), do: default

  @impl true
  def get_env, do: :test

  @impl true
  def map_charts_enabled?, do: true

  @impl true
  def kill_charts_enabled? do
    Agent.get(__MODULE__, & &1.kill_charts_enabled)
  end

  @impl true
  def discord_channel_id_for_activity_charts, do: "123456789"

  @impl true
  def discord_channel_id_for(:kill_charts), do: "123456789"
  def discord_channel_id_for(_), do: nil
end
