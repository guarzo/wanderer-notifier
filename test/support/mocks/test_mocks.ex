defmodule WandererNotifier.Test.Support.Mocks.TestMocks do
  @moduledoc """
  Centralized mock infrastructure for WandererNotifier tests.

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
  defmock(WandererNotifier.MockConfig, for: WandererNotifier.Shared.Config.Behaviour)

  # Infrastructure mocks
  defmock(WandererNotifier.HTTPMock, for: WandererNotifier.Infrastructure.Http.Behaviour)
  # Cache mock with proper behavior
  defmock(WandererNotifier.MockCache, for: WandererNotifier.Infrastructure.Cache.Behaviour)

  defmock(WandererNotifier.MockDeduplication,
    for: WandererNotifier.Test.MockDeduplicationBehaviour
  )

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

  defmock(WandererNotifier.Domains.Notifications.KillmailNotificationMock,
    for: WandererNotifier.Domains.Notifications.KillmailNotificationBehaviour
  )

  defmock(WandererNotifier.Domains.Tracking.StaticInfoMock,
    for: WandererNotifier.Domains.Tracking.StaticInfoBehaviour
  )

  # API Context mock
  defmock(WandererNotifier.ApiContextMock,
    for: WandererNotifier.Contexts.ApiContextBehaviour
  )

  # Discord Notifier mock
  defmock(DiscordNotifierMock,
    for: WandererNotifier.Domains.Notifications.Notifiers.Discord.NotifierBehaviour
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
    setup_deduplication_mocks()
    setup_service_mocks()
    setup_discord_mocks()
    setup_api_context_mocks()
    setup_discord_notifier_mocks()
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
    stub(WandererNotifier.HTTPMock, :request, fn method, url, _body, _headers, opts ->
      handle_http_request(method, url, opts)
    end)
  end

  defp handle_http_request(method, url, opts) do
    case {method, url, opts} do
      # License validation endpoint
      {:post, "https://lm.wanderer.ltd/validate_bot", opts} when is_list(opts) ->
        handle_license_validation(opts)

      # Default response for other requests
      _ ->
        {:ok, %{status_code: 200, body: %{}}}
    end
  end

  defp handle_license_validation(opts) do
    case Keyword.get(opts, :service) do
      :license ->
        {:ok, %{status_code: 200, body: %{"valid" => true, "bot_assigned" => true}}}

      _ ->
        {:ok, %{status_code: 200, body: %{}}}
    end
  end

  @doc """
  Sets up cache mocks with default behaviors.
  """
  def setup_cache_mocks do
    stub(WandererNotifier.MockCache, :get, fn _key -> nil end)
    stub(WandererNotifier.MockCache, :put, fn _key, _value -> :ok end)
    stub(WandererNotifier.MockCache, :put, fn _key, _value, _ttl -> :ok end)
    stub(WandererNotifier.MockCache, :delete, fn _key -> :ok end)
  end

  @doc """
  Sets up deduplication mocks with default behaviors.
  """
  def setup_deduplication_mocks do
    stub(WandererNotifier.MockDeduplication, :check, fn _type, _id -> {:ok, :new} end)
    stub(WandererNotifier.MockDeduplication, :check_and_record, fn _type, _id -> {:ok, :new} end)
  end

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

  @doc """
  Sets up external adapters mocks with default behaviors.
  """
  def setup_api_context_mocks do
    stub(WandererNotifier.ApiContextMock, :get_tracked_systems, fn ->
      {:ok, []}
    end)

    stub(WandererNotifier.ApiContextMock, :get_tracked_characters, fn ->
      {:ok, []}
    end)
  end

  @doc """
  Sets up Discord notifier mocks with default behaviors.
  """
  def setup_discord_notifier_mocks do
    stub(DiscordNotifierMock, :send_kill_notification, fn _killmail, _type, _opts ->
      :ok
    end)

    stub(DiscordNotifierMock, :send_discord_embed, fn _embed ->
      :ok
    end)
  end
end
