defmodule WandererNotifier.Test.Support.Mocks.UnifiedMocks do
  @moduledoc """
  Unified mock infrastructure for WandererNotifier tests.

  This module consolidates all mock definitions and provides a single source
  of truth for test mocking across the entire test suite.

  Replaces scattered mock files:
  - test/support/consolidated_mocks.ex (backup)
  - test/support/mocks/mock_discord_notifier.ex
  - test/support/stubs/discord_notifier.ex
  - Various inline mock definitions in test files
  """

  import Mox

  # ══════════════════════════════════════════════════════════════════════════════
  # Core Mock Definitions
  # ══════════════════════════════════════════════════════════════════════════════

  # Tracking mocks
  defmock(WandererNotifier.MockSystem, for: WandererNotifier.Map.TrackingBehaviour)
  defmock(WandererNotifier.MockCharacter, for: WandererNotifier.Map.TrackingBehaviour)

  # Configuration mock
  defmock(WandererNotifier.MockConfig, for: WandererNotifier.Shared.Config.ConfigBehaviour)

  # Infrastructure mocks
  defmock(WandererNotifier.HTTPMock, for: WandererNotifier.Infrastructure.Http.HttpBehaviour)
  # Simple mock without behavior
  defmock(WandererNotifier.MockCache, for: [])

  # Service mocks
  defmock(WandererNotifier.Infrastructure.Adapters.ESI.ServiceMock,
    for: WandererNotifier.Infrastructure.Adapters.ESI.ServiceBehaviour
  )

  defmock(WandererNotifier.Infrastructure.Adapters.ESI.ClientMock,
    for: WandererNotifier.Infrastructure.Adapters.ESI.ClientBehaviour
  )

  # Notification mocks - using concrete module since no behaviour is defined
  defmock(WandererNotifier.MockDeduplication, for: [])

  defmock(WandererNotifier.Test.Mocks.Discord,
    for: WandererNotifier.Domains.Notifications.Notifiers.Discord.DiscordBehaviour
  )

  # ══════════════════════════════════════════════════════════════════════════════
  # Default Mock Setup Functions
  # ══════════════════════════════════════════════════════════════════════════════

  @doc """
  Sets up all mocks with sensible defaults for most test scenarios.
  Call this in your test setup to get consistent mock behavior.
  """
  def setup_all_mocks do
    setup_tracking_mocks()
    setup_config_mocks()
    setup_http_mocks()
    setup_cache_mocks()
    setup_service_mocks()
    setup_notification_mocks()
    setup_discord_mocks()
  end

  @doc """
  Sets up tracking mocks with default behaviors.
  """
  def setup_tracking_mocks do
    stub(WandererNotifier.MockSystem, :is_tracked?, fn _id -> {:ok, false} end)
    stub(WandererNotifier.MockCharacter, :is_tracked?, fn _id -> {:ok, false} end)
  end

  @doc """
  Sets up configuration mocks with default behaviors.
  """
  def setup_config_mocks do
    stub(WandererNotifier.MockConfig, :notifications_enabled?, fn -> true end)
    stub(WandererNotifier.MockConfig, :kill_notifications_enabled?, fn -> true end)
    stub(WandererNotifier.MockConfig, :system_notifications_enabled?, fn -> true end)
    stub(WandererNotifier.MockConfig, :character_notifications_enabled?, fn -> true end)

    stub(WandererNotifier.MockConfig, :get_notification_setting, fn _type, _key -> {:ok, true} end)

    stub(WandererNotifier.MockConfig, :get_config, fn ->
      %{
        notifications_enabled: true,
        kill_notifications_enabled: true,
        system_notifications_enabled: true,
        character_notifications_enabled: true
      }
    end)

    # Module reference stubs
    stub(WandererNotifier.MockConfig, :deduplication_module, fn ->
      WandererNotifier.MockDeduplication
    end)

    stub(WandererNotifier.MockConfig, :system_track_module, fn -> WandererNotifier.MockSystem end)

    stub(WandererNotifier.MockConfig, :character_track_module, fn ->
      WandererNotifier.MockCharacter
    end)
  end

  @doc """
  Sets up HTTP client mocks with default behaviors.
  """
  def setup_http_mocks do
    stub(WandererNotifier.HTTPMock, :request, fn _method, _url, _body, _headers, _opts ->
      {:ok, %{status_code: 200, body: "{}"}}
    end)

    stub(WandererNotifier.HTTPMock, :get_killmail, fn _id, _hash ->
      {:ok, %{status_code: 200, body: "{}"}}
    end)
  end

  @doc """
  Sets up cache mocks with default behaviors.
  """
  def setup_cache_mocks do
    stub(WandererNotifier.MockCache, :get, fn _key -> {:ok, nil} end)
    stub(WandererNotifier.MockCache, :get, fn _key, _opts -> {:ok, nil} end)
    stub(WandererNotifier.MockCache, :put, fn _key, _value -> {:ok, true} end)
    stub(WandererNotifier.MockCache, :put, fn _key, _value, _ttl -> {:ok, true} end)
    stub(WandererNotifier.MockCache, :set, fn _key, _value, _ttl -> {:ok, true} end)
    stub(WandererNotifier.MockCache, :delete, fn _key -> :ok end)
    stub(WandererNotifier.MockCache, :clear, fn -> :ok end)
    stub(WandererNotifier.MockCache, :mget, fn _keys -> {:ok, %{}} end)
    stub(WandererNotifier.MockCache, :get_and_update, fn _key, _fun -> {:ok, nil} end)
    stub(WandererNotifier.MockCache, :get_recent_kills, fn -> [] end)
  end

  @doc """
  Sets up ESI service mocks with default behaviors.
  """
  def setup_service_mocks do
    # ESI Service Mock
    stub(WandererNotifier.Infrastructure.Adapters.ESI.ServiceMock, :get_killmail, fn _id, _hash ->
      {:ok, %{}}
    end)

    stub(WandererNotifier.Infrastructure.Adapters.ESI.ServiceMock, :get_character, fn _id ->
      {:ok, %{"name" => "Test Character"}}
    end)

    stub(
      WandererNotifier.Infrastructure.Adapters.ESI.ServiceMock,
      :get_corporation_info,
      fn _id ->
        {:ok, %{"name" => "Test Corporation", "ticker" => "TEST"}}
      end
    )

    stub(WandererNotifier.Infrastructure.Adapters.ESI.ServiceMock, :get_alliance_info, fn _id ->
      {:ok, %{"name" => "Test Alliance", "ticker" => "ALLY"}}
    end)

    stub(WandererNotifier.Infrastructure.Adapters.ESI.ServiceMock, :get_universe_type, fn _id,
                                                                                          _opts ->
      {:ok, %{"name" => "Test Type"}}
    end)

    stub(WandererNotifier.Infrastructure.Adapters.ESI.ServiceMock, :get_system, fn id, _opts ->
      {:ok, %{"name" => "System-#{id}", "security_status" => 0.5}}
    end)

    stub(WandererNotifier.Infrastructure.Adapters.ESI.ServiceMock, :get_type_info, fn _id ->
      {:ok, %{"name" => "Test Ship"}}
    end)

    stub(WandererNotifier.Infrastructure.Adapters.ESI.ServiceMock, :get_system_kills, fn _id,
                                                                                         _limit,
                                                                                         _opts ->
      {:ok, []}
    end)

    stub(WandererNotifier.Infrastructure.Adapters.ESI.ServiceMock, :search, fn _query,
                                                                               _categories,
                                                                               _opts ->
      {:ok, %{}}
    end)

    # ESI Client Mock
    stub(WandererNotifier.Infrastructure.Adapters.ESI.ClientMock, :get_killmail, fn _id,
                                                                                    _hash,
                                                                                    _opts ->
      {:ok, %{}}
    end)

    stub(WandererNotifier.Infrastructure.Adapters.ESI.ClientMock, :get_character_info, fn _id,
                                                                                          _opts ->
      {:ok, %{"name" => "Test Character"}}
    end)

    stub(WandererNotifier.Infrastructure.Adapters.ESI.ClientMock, :get_corporation_info, fn _id,
                                                                                            _opts ->
      {:ok, %{"name" => "Test Corporation", "ticker" => "TEST"}}
    end)

    stub(WandererNotifier.Infrastructure.Adapters.ESI.ClientMock, :get_alliance_info, fn _id,
                                                                                         _opts ->
      {:ok, %{"name" => "Test Alliance", "ticker" => "ALLY"}}
    end)

    stub(WandererNotifier.Infrastructure.Adapters.ESI.ClientMock, :get_universe_type, fn _id,
                                                                                         _opts ->
      {:ok, %{"name" => "Test Type"}}
    end)

    stub(WandererNotifier.Infrastructure.Adapters.ESI.ClientMock, :get_system, fn _id, _opts ->
      {:ok, %{"name" => "Test System"}}
    end)

    stub(WandererNotifier.Infrastructure.Adapters.ESI.ClientMock, :get_system_kills, fn _id,
                                                                                        _limit,
                                                                                        _opts ->
      {:ok, []}
    end)

    stub(
      WandererNotifier.Infrastructure.Adapters.ESI.ClientMock,
      :search_inventory_type,
      fn _query, _strict ->
        {:ok, %{}}
      end
    )
  end

  @doc """
  Sets up notification-related mocks with default behaviors.
  """
  def setup_notification_mocks do
    stub(WandererNotifier.MockDeduplication, :check, fn _type, _id -> {:ok, :new} end)
    stub(WandererNotifier.MockDeduplication, :clear_key, fn _type, _id -> :ok end)
  end

  @doc """
  Sets up Discord-related mocks with default behaviors.
  """
  def setup_discord_mocks do
    stub(WandererNotifier.Test.Mocks.Discord, :send_message, fn _channel_id, _message ->
      {:ok, %{id: "123456", content: "Test message"}}
    end)

    stub(WandererNotifier.Test.Mocks.Discord, :send_embed, fn _channel_id, _embed ->
      {:ok, %{id: "123456", embeds: [%{}]}}
    end)

    stub(WandererNotifier.Test.Mocks.Discord, :send_notification, fn _channel_id, _notification ->
      {:ok, %{id: "123456"}}
    end)
  end

  @doc """
  Allows selective mock tracking configuration for specific tests.

  Options:
  - tracked_systems: list of system IDs that should return true for is_tracked?
  - tracked_characters: list of character IDs that should return true for is_tracked?
  """
  def setup_selective_tracking(opts \\ []) do
    tracked_systems = Keyword.get(opts, :tracked_systems, [])
    tracked_characters = Keyword.get(opts, :tracked_characters, [])

    stub(WandererNotifier.MockSystem, :is_tracked?, fn id ->
      {:ok, id in tracked_systems}
    end)

    stub(WandererNotifier.MockCharacter, :is_tracked?, fn id ->
      {:ok, id in tracked_characters}
    end)
  end

  @doc """
  Sets up cache responses for specific keys.
  Useful for tests that need specific cached data.

  Example:
      setup_cache_responses(%{
        "character:123" => {:ok, %{name: "Test Character"}},
        "system:456" => {:ok, %{name: "Test System"}}
      })
  """
  def setup_cache_responses(key_responses) when is_map(key_responses) do
    stub(WandererNotifier.MockCache, :get, fn key ->
      Map.get(key_responses, key, {:ok, nil})
    end)

    stub(WandererNotifier.MockCache, :get, fn key, _opts ->
      Map.get(key_responses, key, {:ok, nil})
    end)
  end

  @doc """
  Sets up HTTP responses for specific URLs.
  Useful for tests that need specific HTTP responses.

  Example:
      setup_http_responses(%{
        "https://api.example.com/test" => {:ok, %{status_code: 200, body: "success"}},
        "https://api.example.com/error" => {:error, :timeout}
      })
  """
  def setup_http_responses(url_responses) when is_map(url_responses) do
    stub(WandererNotifier.HTTPMock, :request, fn _method, url, _body, _headers, _opts ->
      Map.get(url_responses, url, {:ok, %{status_code: 404, body: "Not Found"}})
    end)
  end
end
