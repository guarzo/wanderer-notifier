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

  def processor_info(_message, _metadata \\ []), do: :ok
  def processor_error(_message, _metadata \\ []), do: :ok
  def processor_debug(_message, _metadata \\ []), do: :ok
  def processor_warn(_message, _metadata \\ []), do: :ok

  def scheduler_info(_message, _metadata \\ []), do: :ok
  def scheduler_error(_message, _metadata \\ []), do: :ok
  def scheduler_debug(_message, _metadata \\ []), do: :ok
  def scheduler_warn(_message, _metadata \\ []), do: :ok

  def config_info(_message, _metadata \\ []), do: :ok
  def config_error(_message, _metadata \\ []), do: :ok
  def config_debug(_message, _metadata \\ []), do: :ok
  def config_warn(_message, _metadata \\ []), do: :ok

  def startup_info(_message, _metadata \\ []), do: :ok
  def startup_error(_message, _metadata \\ []), do: :ok
  def startup_debug(_message, _metadata \\ []), do: :ok
  def startup_warn(_message, _metadata \\ []), do: :ok

  def kill_info(_message, _metadata \\ []), do: :ok
  def kill_error(_message, _metadata \\ []), do: :ok
  def kill_debug(_message, _metadata \\ []), do: :ok
  def kill_warn(_message, _metadata \\ []), do: :ok

  def character_info(_message, _metadata \\ []), do: :ok
  def character_error(_message, _metadata \\ []), do: :ok
  def character_debug(_message, _metadata \\ []), do: :ok
  def character_warn(_message, _metadata \\ []), do: :ok

  def system_info(_message, _metadata \\ []), do: :ok
  def system_error(_message, _metadata \\ []), do: :ok
  def system_debug(_message, _metadata \\ []), do: :ok
  def system_warn(_message, _metadata \\ []), do: :ok

  def notification_info(_message, _metadata \\ []), do: :ok
  def notification_error(_message, _metadata \\ []), do: :ok
  def notification_debug(_message, _metadata \\ []), do: :ok
  def notification_warn(_message, _metadata \\ []), do: :ok

  def api_info(_message, _metadata \\ []), do: :ok
  def api_error(_message, _metadata \\ []), do: :ok
  def api_debug(_message, _metadata \\ []), do: :ok
  def api_warn(_message, _metadata \\ []), do: :ok

  def cache_info(_message, _metadata \\ []), do: :ok
  def cache_error(_message, _metadata \\ []), do: :ok
  def cache_debug(_message, _metadata \\ []), do: :ok
  def cache_warn(_message, _metadata \\ []), do: :ok

  def license_info(_message, _metadata \\ []), do: :ok
  def license_error(_message, _metadata \\ []), do: :ok
  def license_debug(_message, _metadata \\ []), do: :ok
  def license_warn(_message, _metadata \\ []), do: :ok

  def feature_info(_message, _metadata \\ []), do: :ok
  def feature_error(_message, _metadata \\ []), do: :ok
  def feature_debug(_message, _metadata \\ []), do: :ok
  def feature_warn(_message, _metadata \\ []), do: :ok

  def test_info(_message, _metadata \\ []), do: :ok
  def test_error(_message, _metadata \\ []), do: :ok
  def test_debug(_message, _metadata \\ []), do: :ok
  def test_warn(_message, _metadata \\ []), do: :ok

  def redisq_info(_message, _metadata \\ []), do: :ok
  def redisq_error(_message, _metadata \\ []), do: :ok
  def redisq_debug(_message, _metadata \\ []), do: :ok
  def redisq_warn(_message, _metadata \\ []), do: :ok
end

defmodule WandererNotifier.Test.Support.Mocks do
  @moduledoc """
  Mock implementations for testing.
  """

  alias WandererNotifier.Test.Support.Mocks.CacheMock

  defdelegate get(key, opts \\ []), to: CacheMock
  defdelegate set(key, value, ttl), to: CacheMock
  defdelegate put(key, value), to: CacheMock
  defdelegate delete(key), to: CacheMock
  defdelegate clear, to: CacheMock
  defdelegate get_and_update(key, update_fun), to: CacheMock
  defdelegate get_recent_kills, to: CacheMock
  defdelegate get_kill(kill_id), to: CacheMock
  defdelegate get_latest_killmails, to: CacheMock
  defdelegate init_batch_logging, to: CacheMock
  defdelegate mget(keys), to: CacheMock
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

  def notifications_enabled?, do: true

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

  def deduplication_module, do: WandererNotifier.MockDeduplication

  def get_config do
    %{
      notifications: %{
        enabled: true,
        kill: %{
          enabled: true,
          system: %{enabled: true},
          character: %{enabled: true},
          min_value: 100_000_000,
          min_isk_per_character: 50_000_000,
          min_isk_per_corporation: 50_000_000,
          min_isk_per_alliance: 50_000_000,
          min_isk_per_ship: 50_000_000,
          min_isk_per_system: 50_000_000
        }
      }
    }
  end
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

  Mox.defmock(WandererNotifier.Domains.Notifications.Determiner.KillMock,
    for: WandererNotifier.Domains.Notifications.Determiner.KillBehaviour
  )

  Mox.defmock(WandererNotifier.Shared.Config.EnvProviderMock,
    for: WandererNotifier.Shared.Config.EnvProvider
  )
end

defmodule WandererNotifier.Map.MapSystemMock do
  @moduledoc """
  Mock module for system tracking functionality.
  """
  @behaviour WandererNotifier.Map.TrackingBehaviour

  @impl true
  def is_tracked?(_system_id), do: {:ok, false}
end

defmodule WandererNotifier.Domains.CharacterTracking.CharacterMock do
  @moduledoc """
  Mock module for character tracking functionality.
  """
  @behaviour WandererNotifier.Map.TrackingBehaviour

  @impl true
  def is_tracked?(_character_id), do: {:ok, false}
end

defmodule WandererNotifier.Test.Mocks do
  @moduledoc """
  Mock modules for testing.
  """

  defmodule MockHttpClient do
    @moduledoc """
    Mock implementation of HTTP client for testing purposes.
    Allows simulation of HTTP requests and responses in tests.
    """
    def get(_url, _headers), do: {:ok, %{status_code: 200, body: %{}}}
    def get(_url, _headers, _opts), do: {:ok, %{status_code: 200, body: %{}}}
    def post(_url, _body, _headers), do: {:ok, %{status_code: 200, body: %{}}}
    def post_json(_url, _body, _headers, _opts), do: {:ok, %{status_code: 200, body: %{}}}
    def request(_method, _url, _headers, _body, _opts), do: {:ok, %{status_code: 200, body: %{}}}
    def handle_response(response), do: response
  end

  defmodule MockESIService do
    @moduledoc """
    Mock implementation of the ESI service for testing purposes.
    Simulates EVE Online ESI API responses for testing scenarios.
    """
    def get_character_info(100, _opts), do: {:ok, %{"name" => "Victim"}}
    def get_character_info(_, _), do: {:error, :not_found}
    def get_character_info(id), do: get_character_info(id, [])

    def get_corporation_info(200, _opts), do: {:ok, %{"name" => "Corp", "ticker" => "CORP"}}
    def get_corporation_info(_, _), do: {:error, :not_found}
    def get_corporation_info(id), do: get_corporation_info(id, [])

    def get_type_info(300, _opts), do: {:ok, %{"name" => "Ship"}}
    def get_type_info(_, _), do: {:error, :not_found}
    def get_type_info(id), do: get_type_info(id, [])

    def get_system(400, _opts), do: {:ok, %{"name" => "System"}}
    def get_system(_, _), do: {:error, :not_found}
    def get_system(id), do: get_system(id, [])

    def get_alliance_info(_, _), do: {:ok, %{"name" => "Alliance"}}
    def get_alliance_info(id), do: get_alliance_info(id, [])

    def get_killmail(_, _), do: {:ok, %{}}
    def get_killmail(id, hash, _opts), do: get_killmail(id, hash)
  end

  defmodule MockDiscordClient do
    @moduledoc """
    Mock implementation of Discord client for testing purposes.
    Simulates Discord API interactions and message sending.
    """
    def send_message(channel_id, message) do
      {:ok, %{id: channel_id, content: message}}
    end

    def send_embed(channel_id, embed) do
      {:ok, %{id: channel_id, embed: embed}}
    end
  end

  defmodule MockRedis do
    @moduledoc """
    Mock implementation of Redis for testing purposes.
    Provides a simplified in-memory implementation of Redis functionality.
    """
    def get(key) do
      case key do
        "map:system:12345" -> {:ok, "Jita"}
        "map:system:54321" -> {:ok, "Amarr"}
        "map:system:98765" -> {:ok, "Dodixie"}
        "map:system:123456" -> {:ok, "Hek"}
        "map:system:1234567" -> {:ok, "Rens"}
        "map:system:12345678" -> {:ok, "Sobaseki"}
        "map:system:123456789" -> {:ok, "Tama"}
        _ -> {:error, :not_found}
      end
    end

    def set(_key, _value) do
      :ok
    end

    def set(_key, _value, _ttl) do
      :ok
    end

    def del(_key) do
      :ok
    end

    def exists(key) do
      case key do
        "map:system:12345" -> {:ok, 1}
        "map:system:54321" -> {:ok, 1}
        "map:system:98765" -> {:ok, 1}
        "map:system:123456" -> {:ok, 1}
        "map:system:1234567" -> {:ok, 1}
        "map:system:12345678" -> {:ok, 1}
        "map:system:123456789" -> {:ok, 1}
        _ -> {:ok, 0}
      end
    end

    def keys(pattern) do
      case pattern do
        "map:system:*" ->
          {:ok,
           [
             "map:system:12345",
             "map:system:54321",
             "map:system:98765",
             "map:system:123456",
             "map:system:1234567",
             "map:system:12345678",
             "map:system:123456789"
           ]}

        _ ->
          {:ok, []}
      end
    end
  end

  defmodule MockLogger do
    @moduledoc """
    Mock implementation of logger for testing purposes.
    Captures and verifies logging calls in tests.
    """
    def count_batch_event(event, metadata) do
      {:ok, %{event: event, metadata: metadata}}
    end
  end

  defmodule MockDiscordChannel do
    @moduledoc """
    Mock implementation of Discord channel for testing purposes.
    Simulates Discord channel interactions and message sending.
    """
    def get_channel_id(type) do
      case type do
        :main -> "123_456_789"
        :system_kill -> "123_456_789"
        :character_kill -> "123_456_789"
        :system -> "123_456_789"
        :character -> "123_456_789"
        _ -> "123_456_789"
      end
    end
  end
end

defmodule WandererNotifier.Domains.Notifications.MockDeduplication do
  @moduledoc """
  Mock implementation of the deduplication service for testing.
  """

  def check(_type, _id), do: {:ok, :new}
  def clear_key(_type, _id), do: :ok
end

# Define behavior for ExternalAdapters
defmodule WandererNotifier.Contexts.ExternalAdaptersBehaviour do
  @moduledoc """
  Behaviour for ExternalAdapters to enable mocking.
  """

  @callback get_tracked_systems() :: {:ok, list()} | {:error, any()}
  @callback get_tracked_characters() :: {:ok, list()} | {:error, any()}
end

# Define mock for ExternalAdapters
Mox.defmock(WandererNotifier.ExternalAdaptersMock,
  for: WandererNotifier.Contexts.ExternalAdaptersBehaviour
)
