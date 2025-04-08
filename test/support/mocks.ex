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

  @impl true
  def get_ship_type_name(_ship_type_id), do: {:ok, %{"name" => "Test Ship"}}

  @impl true
  def get_system_kills(_system_id, _limit) do
    {:ok, []}
  end
end

defmodule WandererNotifier.ETSCache do
  @moduledoc """
  ETS-based implementation of cache behavior for testing using ETS tables
  """

  @behaviour WandererNotifier.Data.Cache.CacheBehaviour

  @impl true
  def get(key) do
    case :ets.lookup(:cache_table, key) do
      [{^key, value}] -> {:ok, value}
      [] -> {:error, :not_found}
    end
  end

  @impl true
  def set(key, value, _ttl \\ nil) do
    :ets.insert(:cache_table, {key, value})
    {:ok, value}
  end

  @impl true
  def put(key, value, _ttl \\ nil) do
    :ets.insert(:cache_table, {key, value})
    {:ok, value}
  end

  @impl true
  def delete(key) do
    :ets.delete(:cache_table, key)
    :ok
  end

  @impl true
  def clear do
    :ets.delete_all_objects(:cache_table)
    :ok
  end

  @impl true
  def get_and_update(key, update_fn) do
    case get(key) do
      {:ok, value} ->
        case update_fn.(value) do
          {get_value, update_value} ->
            set(key, update_value)
            {:ok, get_value}
        end

      {:error, :not_found} ->
        case update_fn.(nil) do
          {get_value, update_value} ->
            set(key, update_value)
            {:ok, get_value}
        end
    end
  end
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

  @impl true
  def clear, do: :ok
end

defmodule WandererNotifier.MockKillmailPersistence do
  @moduledoc """
  Mock implementation of the killmail persistence service for testing.
  """

  @behaviour WandererNotifier.Resources.KillmailPersistenceBehaviour

  @impl true
  def maybe_persist_killmail(_killmail), do: {:ok, %{}}

  @impl true
  def persist_killmail(_killmail), do: {:ok, %{}}

  @impl true
  def persist_killmail(_killmail, _character_id), do: {:ok, %{}}
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

  @behaviour WandererNotifier.Config.Behaviour

  def start_link do
    Agent.start_link(
      fn ->
        %{
          kill_charts_enabled: true,
          map_charts_enabled: true,
          character_notifications_enabled: true,
          character_tracking_enabled: true,
          system_notifications_enabled: true,
          track_kspace_systems: true,
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
  def get_env(key, default \\ nil) do
    case key do
      :features -> %{track_kspace_systems: true}
      _ -> default
    end
  end

  @impl true
  def get_map_config, do: %{}

  @impl true
  def map_charts_enabled?, do: true

  @impl true
  def kill_charts_enabled? do
    Agent.get(__MODULE__, & &1.kill_charts_enabled)
  end

  @impl true
  def character_notifications_enabled?, do: true

  @impl true
  def character_tracking_enabled?, do: true

  @impl true
  def system_notifications_enabled?, do: true

  @impl true
  def track_kspace_systems?, do: true

  @impl true
  def license_key, do: "test-license-key"

  @impl true
  def license_manager_api_key, do: "test-api-key"

  @impl true
  def license_manager_api_url, do: "https://test-license-api.example.com"

  @impl true
  def map_csrf_token, do: "test-csrf-token"

  @impl true
  def map_name, do: "Test Map"

  @impl true
  def map_token, do: "test-map-token"

  @impl true
  def map_url, do: "https://test-map.example.com"

  @impl true
  def notifier_api_token, do: "test-notifier-token"

  @impl true
  def static_info_cache_ttl, do: 3600

  @impl true
  def discord_channel_id_for_activity_charts, do: "123456789"

  @impl true
  def discord_channel_id_for(:kill_charts), do: "123456789"
  def discord_channel_id_for(_), do: nil

  @impl true
  def get_feature_status do
    %{
      kill_notifications_enabled: true,
      system_tracking_enabled: true,
      character_tracking_enabled: true,
      activity_charts: true
    }
  end
end

defmodule WandererNotifier.MockCacheHelpers do
  @moduledoc """
  Mock implementation of cache helpers for testing.
  """

  @behaviour WandererNotifier.Data.Cache.HelpersBehaviour

  @impl true
  def get_cached_kills(_id) do
    {:ok, []}
  end

  @impl true
  def get_tracked_systems do
    []
  end

  @impl true
  def get_tracked_characters do
    []
  end

  @impl true
  def get_ship_name(_ship_type_id) do
    {:ok, "Test Ship"}
  end

  @impl true
  def get_character_name(character_id) do
    {:ok, "Test Character #{character_id}"}
  end
end

defmodule WandererNotifier.TestHelpers.Mocks do
  @moduledoc """
  Defines mock behaviors for external services used in tests.
  """

  # Define mock behaviors for ZKill service
  defmodule ZKillBehavior do
    @moduledoc """
    Behaviour module for ZKill service mocks in tests.
    Defines the contract that ZKill service mocks must implement.
    """

    @callback get_killmail(String.t(), String.t()) :: {:ok, map()} | {:error, any()}
    @callback get_system_kills(String.t(), integer()) :: {:ok, list()} | {:error, any()}
  end

  # Define mock behaviors for ESI service
  defmodule ESIBehavior do
    @moduledoc """
    Behaviour module for ESI service mocks in tests.
    Defines the contract that ESI service mocks must implement.
    """

    @callback get_character_info(String.t()) :: {:ok, map()} | {:error, any()}
    @callback get_type_info(String.t()) :: {:ok, map()} | {:error, any()}
    @callback get_ship_type_name(String.t()) :: {:ok, map()} | {:error, any()}
    @callback get_system_kills(String.t(), integer()) :: {:ok, list()} | {:error, any()}
    @callback get_killmail(String.t(), String.t()) :: {:ok, map()} | {:error, any()}
  end
end

# Define the mocks
Mox.defmock(WandererNotifier.Api.ZKill.ServiceMock,
  for: WandererNotifier.TestHelpers.Mocks.ZKillBehavior
)

Mox.defmock(WandererNotifier.Api.ESI.ServiceMock,
  for: WandererNotifier.TestHelpers.Mocks.ESIBehavior
)
