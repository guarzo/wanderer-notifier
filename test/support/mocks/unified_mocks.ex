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
  # Note: Cache module no longer uses behaviors - tests use direct Cachex operations

  # Service mocks
  defmock(WandererNotifier.Infrastructure.Adapters.ESI.ServiceMock,
    for: WandererNotifier.Infrastructure.Adapters.ESI.ServiceBehaviour
  )

  defmock(WandererNotifier.Infrastructure.Adapters.ESI.ClientMock,
    for: WandererNotifier.Infrastructure.Adapters.ESI.ClientBehaviour
  )

  # Note: Deduplication module uses cache directly - no mocking needed

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
    # Cache mocks removed - tests use direct Cachex operations
    setup_service_mocks()
    # Notification mocks removed - deduplication uses cache directly
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

  # Cache mocks removed - cache module now uses direct Cachex operations without behaviors

  @doc """
  Sets up ESI service mocks with default behaviors.
  """
  def setup_service_mocks do
    setup_esi_service_mocks()
    setup_esi_client_mocks()
  end

  defp setup_esi_service_mocks do
    service_mock = WandererNotifier.Infrastructure.Adapters.ESI.ServiceMock

    stub(service_mock, :get_killmail, fn _id, _hash -> {:ok, %{}} end)
    stub(service_mock, :get_character, fn _id -> {:ok, %{"name" => "Test Character"}} end)

    stub(service_mock, :get_corporation_info, fn _id ->
      {:ok, %{"name" => "Test Corporation", "ticker" => "TEST"}}
    end)

    stub(service_mock, :get_alliance_info, fn _id ->
      {:ok, %{"name" => "Test Alliance", "ticker" => "ALLY"}}
    end)

    stub(service_mock, :get_universe_type, fn _id, _opts -> {:ok, %{"name" => "Test Type"}} end)

    stub(service_mock, :get_system, fn id, _opts ->
      {:ok, %{"name" => "System-#{id}", "security_status" => 0.5}}
    end)

    stub(service_mock, :get_type_info, fn _id -> {:ok, %{"name" => "Test Ship"}} end)
    stub(service_mock, :get_system_kills, fn _id, _limit, _opts -> {:ok, []} end)
    stub(service_mock, :search, fn _query, _categories, _opts -> {:ok, %{}} end)
  end

  defp setup_esi_client_mocks do
    client_mock = WandererNotifier.Infrastructure.Adapters.ESI.ClientMock

    stub(client_mock, :get_killmail, fn _id, _hash, _opts -> {:ok, %{}} end)

    stub(client_mock, :get_character_info, fn _id, _opts ->
      {:ok, %{"name" => "Test Character"}}
    end)

    stub(client_mock, :get_corporation_info, fn _id, _opts ->
      {:ok, %{"name" => "Test Corporation", "ticker" => "TEST"}}
    end)

    stub(client_mock, :get_alliance_info, fn _id, _opts ->
      {:ok, %{"name" => "Test Alliance", "ticker" => "ALLY"}}
    end)

    stub(client_mock, :get_universe_type, fn _id, _opts -> {:ok, %{"name" => "Test Type"}} end)
    stub(client_mock, :get_system, fn _id, _opts -> {:ok, %{"name" => "Test System"}} end)
    stub(client_mock, :get_system_kills, fn _id, _limit, _opts -> {:ok, []} end)
    stub(client_mock, :search_inventory_type, fn _query, _strict -> {:ok, %{}} end)
  end

  # Notification mocks removed - deduplication uses cache directly without behaviors

  @doc """
  Sets up Discord-related mocks with default behaviors.
  """
  def setup_discord_mocks do
    # Stub Discord behavior callbacks with correct signatures
    stub(WandererNotifier.Test.Mocks.Discord, :notify, fn _notification -> :ok end)
    stub(WandererNotifier.Test.Mocks.Discord, :send_message, fn _message, _channel -> :ok end)

    stub(WandererNotifier.Test.Mocks.Discord, :send_embed, fn _title,
                                                              _description,
                                                              _color,
                                                              _fields,
                                                              _channel ->
      :ok
    end)

    stub(WandererNotifier.Test.Mocks.Discord, :send_file, fn _filename,
                                                             _file_data,
                                                             _title,
                                                             _description,
                                                             _channel ->
      :ok
    end)

    stub(WandererNotifier.Test.Mocks.Discord, :send_image_embed, fn _title,
                                                                    _description,
                                                                    _image_url,
                                                                    _color,
                                                                    _channel ->
      :ok
    end)

    stub(WandererNotifier.Test.Mocks.Discord, :send_enriched_kill_embed, fn _killmail, _kill_id ->
      :ok
    end)

    stub(WandererNotifier.Test.Mocks.Discord, :send_new_system_notification, fn _system -> :ok end)

    stub(
      WandererNotifier.Test.Mocks.Discord,
      :send_new_tracked_character_notification,
      fn _character -> :ok end
    )

    # Using 3-arity version as it's more commonly used in tests
    # Individual tests can override with expect/allow for single-arity if needed
    stub(WandererNotifier.Test.Mocks.Discord, :send_kill_notification, fn _killmail,
                                                                          _type,
                                                                          _opts ->
      :ok
    end)

    stub(WandererNotifier.Test.Mocks.Discord, :send_discord_embed, fn _embed -> {:ok, %{}} end)

    stub(WandererNotifier.Test.Mocks.Discord, :send_notification, fn _type, _data ->
      {:ok, %{}}
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

  # Cache response helpers removed - use direct Cachex operations in tests

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
