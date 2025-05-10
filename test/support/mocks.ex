defmodule WandererNotifier.MockESI do
  @moduledoc """
  Mock implementation of the ESI service for testing.
  """

  # Test data for ESI.ServiceTest
  @character_data %{
    "character_id" => 123_456,
    "name" => "Test Character",
    "corporation_id" => 789_012,
    "alliance_id" => 345_678,
    "security_status" => 0.5,
    "birthday" => "2020-01-01T00:00:00Z"
  }
  @corporation_data %{
    "corporation_id" => 789_012,
    "name" => "Test Corporation",
    "ticker" => "TSTC",
    "member_count" => 100,
    "alliance_id" => 345_678,
    "description" => "A test corporation",
    "date_founded" => "2020-01-01T00:00:00Z"
  }
  @alliance_data %{
    "alliance_id" => 345_678,
    "name" => "Test Alliance",
    "ticker" => "TSTA",
    "executor_corporation_id" => 789_012,
    "creator_id" => 123_456,
    "date_founded" => "2020-01-01T00:00:00Z",
    "faction_id" => 555_555
  }
  @system_data %{
    "system_id" => 30_000_142,
    "name" => "Jita",
    "constellation_id" => 20_000_020,
    "security_status" => 0.9,
    "security_class" => "B",
    "position" => %{"x" => 1.0, "y" => 2.0, "z" => 3.0},
    "star_id" => 40_000_001,
    "planets" => [%{"planet_id" => 50_000_001}],
    "region_id" => 10_000_002
  }

  def get_killmail(_kill_id, _hash), do: {:ok, %{}}
  def get_killmail(_kill_id, _hash, _opts), do: {:ok, %{}}

  def get_character_info(123_456), do: {:ok, @character_data}
  def get_character_info(_), do: {:ok, %{}}
  def get_character_info(id, _opts), do: get_character_info(id)

  def get_corporation_info(789_012), do: {:ok, @corporation_data}
  def get_corporation_info(_), do: {:ok, %{}}
  def get_corporation_info(id, _opts), do: get_corporation_info(id)

  def get_alliance_info(345_678), do: {:ok, @alliance_data}
  def get_alliance_info(_), do: {:ok, %{}}
  def get_alliance_info(id, _opts), do: get_alliance_info(id)

  def get_system_info(30_000_142), do: {:ok, @system_data}
  def get_system_info(_), do: {:ok, %{}}
  def get_system_info(id, _opts), do: get_system_info(id)

  def get_universe_type(200, _opts), do: {:ok, %{"name" => "Victim Ship"}}
  def get_universe_type(201, _opts), do: {:ok, %{"name" => "Attacker Ship"}}
  def get_universe_type(301, _opts), do: {:ok, %{"name" => "Weapon"}}
  def get_universe_type(_, _opts), do: {:ok, %{"name" => "Unknown Ship"}}

  def get_type_info(_type_id), do: {:ok, %{}}
  def get_type_info(type_id, _opts), do: get_type_info(type_id)

  def get_system(30_000_142), do: {:ok, @system_data}
  def get_system(_), do: {:ok, %{}}
  def get_system(id, _opts), do: get_system(id)

  def get_character(_character_id), do: {:ok, %{}}
  def get_character(character_id, _opts), do: get_character(character_id)

  def get_type(_type_id), do: {:ok, %{}}
  def get_type(type_id, _opts), do: get_type(type_id)

  def get_ship_type_name(_ship_type_id), do: {:ok, %{"name" => "Test Ship"}}
  def get_ship_type_name(ship_type_id, _opts), do: get_ship_type_name(ship_type_id)

  def get_system_kills(system_id, limit \\ 3)
  def get_system_kills(30_000_142, _limit), do: {:ok, []}
  def get_system_kills(_system_id, _limit), do: {:error, :service_unavailable}
  def get_system_kills(system_id, limit, _opts), do: get_system_kills(system_id, limit)

  def get_recent_kills do
    kills = Process.get({:cache, "zkill:recent_kills"}) || []

    if is_list(kills) && length(kills) > 0 do
      # Process kills into a map format expected by the controller - return directly, not in a tuple
      kills
      |> Enum.map(fn id ->
        key = "zkill:recent_kills:#{id}"
        {id, Process.get({:cache, key})}
      end)
      |> Enum.reject(fn {_, v} -> is_nil(v) end)
      |> Enum.into(%{})
    else
      # Return empty map directly
      %{}
    end
  end
end

defmodule WandererNotifier.Test.Support.Mocks do
  @moduledoc """
  Mock implementations for testing.
  """

  alias WandererNotifier.Logger.Logger, as: AppLogger

  @behaviour WandererNotifier.Cache.Behaviour

  # -- Cache Implementation --

  def get(key, _opts \\ []) do
    if key == "test_key" do
      {:ok, "test_value"}
    else
      {:error, :not_found}
    end
  end

  def set(key, value, _ttl) do
    AppLogger.cache_debug("Setting cache value with TTL",
      key: key,
      value: value
    )

    Process.put({:cache, key}, value)
    :ok
  end

  def put(key, value) do
    Process.put({:cache, key}, value)
    :ok
  end

  def delete(key) do
    Process.delete({:cache, key})
    :ok
  end

  def clear do
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
    {:ok, current_value}
  end

  @doc """
  Get a specific kill by ID. Used by the KillController.
  """
  def get_kill(kill_id) do
    key = "zkill:recent_kills:#{kill_id}"

    case Process.get({:cache, key}) do
      nil -> {:error, :not_cached}
      value -> {:ok, value}
    end
  end

  @doc """
  Get latest killmails as a list. Used by the KillController.
  """
  def get_latest_killmails do
    # Get the list of kill IDs
    kill_ids = Process.get({:cache, "zkill:recent_kills"}) || []

    # Convert to a list of killmails
    kill_ids
    |> Enum.map(fn id ->
      kill = Process.get({:cache, "zkill:recent_kills:#{id}"})
      if kill, do: Map.put(kill, "id", id), else: nil
    end)
    |> Enum.reject(&is_nil/1)
  end

  def init_batch_logging, do: :ok

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
    @callback get_character_info(String.t(), keyword()) :: {:ok, map()} | {:error, any()}
    @callback get_corporation_info(String.t()) :: {:ok, map()} | {:error, any()}
    @callback get_corporation_info(String.t(), keyword()) :: {:ok, map()} | {:error, any()}
    @callback get_alliance_info(String.t()) :: {:ok, map()} | {:error, any()}
    @callback get_alliance_info(String.t(), keyword()) :: {:ok, map()} | {:error, any()}
    @callback get_system_info(String.t()) :: {:ok, map()} | {:error, any()}
    @callback get_system_info(String.t(), keyword()) :: {:ok, map()} | {:error, any()}
    @callback get_system(String.t()) :: {:ok, map()} | {:error, any()}
    @callback get_system(String.t(), keyword()) :: {:ok, map()} | {:error, any()}
    @callback get_type_info(String.t()) :: {:ok, map()} | {:error, any()}
    @callback get_type_info(String.t(), keyword()) :: {:ok, map()} | {:error, any()}
    @callback get_ship_type_name(String.t()) :: {:ok, map()} | {:error, any()}
    @callback get_ship_type_name(String.t(), keyword()) :: {:ok, map()} | {:error, any()}
    @callback get_system_kills(String.t(), integer()) :: {:ok, list()} | {:error, any()}
    @callback get_system_kills(String.t(), integer(), keyword()) ::
                {:ok, list()} | {:error, any()}
    @callback get_killmail(String.t(), String.t()) :: {:ok, map()} | {:error, any()}
    @callback get_killmail(String.t(), String.t(), keyword()) :: {:ok, map()} | {:error, any()}
    @callback get_universe_type(type_id :: integer(), opts :: keyword()) ::
                {:ok, map()} | {:error, any()}
  end
end

# Define the mocks
Mox.defmock(WandererNotifier.Api.ZKill.ServiceMock,
  for: WandererNotifier.TestHelpers.Mocks.ZKillBehavior
)

Mox.defmock(WandererNotifier.Api.ESI.ServiceMock,
  for: WandererNotifier.TestHelpers.Mocks.ESIBehavior
)

defmodule WandererNotifier.Mocks do
  @moduledoc """
  Defines mocks for behaviors used in the application.
  """

  # Mocks for behaviors
  Mox.defmock(WandererNotifier.Notifications.KillmailNotificationMock,
    for: WandererNotifier.Notifications.KillmailNotificationBehaviour
  )

  Mox.defmock(WandererNotifier.Notifications.DispatcherMock,
    for: WandererNotifier.Notifications.DispatcherBehaviour
  )

  Mox.defmock(WandererNotifier.Logger.LoggerMock,
    for: WandererNotifier.Logger.LoggerBehaviour
  )

  Mox.defmock(WandererNotifier.Notifications.Determiner.KillMock,
    for: WandererNotifier.Notifications.Determiner.KillBehaviour
  )
end

# Replace the last line with Mox.defmock
Mox.defmock(WandererNotifier.HttpClient.HttpoisonMock, for: WandererNotifier.HttpClient.Httpoison)
