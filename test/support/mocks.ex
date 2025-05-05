defmodule WandererNotifier.MockESI do
  @moduledoc """
  Mock implementation of the ESI service for testing.
  """

  def get_killmail(_kill_id, _hash), do: {:ok, %{}}

  def get_character_info(_character_id), do: {:ok, %{}}

  def get_corporation_info(_corporation_id), do: {:ok, %{}}

  def get_alliance_info(_alliance_id), do: {:ok, %{}}

  def get_system_info(_system_id), do: {:ok, %{}}

  def get_type_info(_type_id), do: {:ok, %{}}

  def get_system(_system_id), do: {:ok, %{}}

  def get_character(_character_id), do: {:ok, %{}}

  def get_type(_type_id), do: {:ok, %{}}

  def get_ship_type_name(_ship_type_id), do: {:ok, %{"name" => "Test Ship"}}

  def get_system_kills(_system_id, _limit), do: {:ok, []}
end

defmodule WandererNotifier.Test.Support.Mocks do
  @moduledoc """
  Mock implementations for testing.
  """

  alias WandererNotifier.Cache.Keys
  alias WandererNotifier.Logger.Logger, as: AppLogger

  @behaviour WandererNotifier.Cache.Behaviour

  # -- Cache Implementation --

  def get(key), do: {:ok, Process.get({:cache, key})}

  def set(key, value, _ttl) do
    AppLogger.cache_debug("Setting cache value with TTL",
      key: key,
      value: value
    )

    Process.put({:cache, key}, value)
    {:ok, value}
  end

  def put(key, value) do
    Process.put({:cache, key}, value)
    {:ok, value}
  end

  def delete(key) do
    Process.delete({:cache, key})
    :ok
  end

  def clear do
    # This is a simplified clear that only clears cache-related process dictionary entries
    Process.get_keys()
    |> Enum.filter(fn
      {:cache, _} -> true
      _ -> false
    end)
    |> Enum.each(&Process.delete/1)

    :ok
  end

  def get_and_update(key, update_fun) do
    current = Process.get({:cache, key})
    {current_value, new_value} = update_fun.(current)
    Process.put({:cache, key}, new_value)
    {:ok, {current_value, new_value}}
  end

  def get_recent_kills do
    case get(Keys.zkill_recent_kills()) do
      {:ok, kills} when is_list(kills) -> kills
      _ -> []
    end
  end

  # -- Other Mock Implementations --
  # Add other mock implementations here as needed
end

defmodule WandererNotifier.MockRepository do
  @moduledoc """
  Mock implementation of the repository for testing.
  """

  def delete(_key), do: :ok

  def exists?(_key), do: false

  def get(_key), do: nil

  def get_and_update(_key, _fun), do: {nil, nil}

  def get_tracked_characters, do: []

  def put(_key, _value), do: :ok

  def set(_key, _value, _ttl), do: :ok

  def clear, do: :ok
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
  Mock for the config module.
  """

  def character_tracking_enabled?, do: true

  def character_notifications_enabled?, do: true

  def system_notifications_enabled?, do: true

  def get_feature_status do
    %{
      notifications_enabled: true,
      character_notifications_enabled: true,
      system_notifications_enabled: true,
      kill_notifications_enabled: true,
      character_tracking_enabled: true,
      system_tracking_enabled: true,
      tracked_systems_notifications_enabled: true,
      tracked_characters_notifications_enabled: true,
      status_messages_disabled: true,
      track_kspace_systems: true
    }
  end

  def discord_channel_id_for(channel) do
    case channel do
      :main -> "123456789"
      :system_kill -> "123456789"
      :character_kill -> "123456789"
      :system -> "123456789"
      :character -> "123456789"
      _ -> "123456789"
    end
  end

  def get_map_config do
    %{
      url: "https://wanderer.ltd",
      name: "TestMap",
      token: "test-token",
      csrf_token: "test-csrf-token"
    }
  end

  def get_env(key, default) do
    case key do
      :webhook_url -> "https://discord.com/api/webhooks/123/abc"
      :map_url -> "https://wanderer.ltd"
      :map_name -> "TestMap"
      :map_token -> "test-token"
      :test_mode -> true
      _ -> default
    end
  end

  def static_info_cache_ttl, do: 3600

  def map_url, do: "https://wanderer.ltd"

  def map_name, do: "TestMap"

  def map_token, do: "test-token"

  def map_csrf_token, do: "test-csrf-token"

  def license_key, do: "test-license-key"

  def license_manager_api_url, do: "https://license.example.com"

  def license_manager_api_key, do: "test-api-key"

  def notifier_api_token, do: "test-api-token"

  def track_kspace_systems?, do: true
end

defmodule WandererNotifier.MockCacheHelpers do
  @moduledoc """
  Mock implementation of cache helpers for testing.
  """

  def get_cached_kills(_id), do: {:ok, []}

  def get_tracked_systems, do: []

  def get_tracked_characters, do: []

  def get_ship_name(_ship_type_id), do: {:ok, "Test Ship"}

  def get_character_name(_character_id), do: {:ok, "Test Character"}
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
