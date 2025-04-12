defmodule WandererNotifier.MockConfigExtensions do
  @moduledoc """
  Extensions to add required behavior functions to MockConfig that aren't directly
  defined in the test_helper.exs file but are needed by various tests.
  """

  # Add the MockConfig extensions
  def add_expectations do
    Mox.stub(WandererNotifier.MockConfig, :get_feature_status, fn ->
      %{
        activity_charts: true,
        kill_charts: true,
        map_charts: true,
        character_notifications_enabled: true,
        system_notifications_enabled: true,
        character_tracking_enabled: true,
        system_tracking_enabled: true,
        tracked_systems_notifications_enabled: true,
        tracked_characters_notifications_enabled: true,
        kill_notifications_enabled: true,
        notifications_enabled: true
      }
    end)

    Mox.stub(WandererNotifier.MockConfig, :kill_charts_enabled?, fn -> true end)
    Mox.stub(WandererNotifier.MockConfig, :map_charts_enabled?, fn -> true end)
    Mox.stub(WandererNotifier.MockConfig, :character_tracking_enabled?, fn -> true end)
    Mox.stub(WandererNotifier.MockConfig, :character_notifications_enabled?, fn -> true end)
    Mox.stub(WandererNotifier.MockConfig, :system_notifications_enabled?, fn -> true end)
    Mox.stub(WandererNotifier.MockConfig, :kill_notifications_enabled?, fn -> true end)
    Mox.stub(WandererNotifier.MockConfig, :track_kspace_systems?, fn -> true end)
    Mox.stub(WandererNotifier.MockConfig, :get, fn _key -> nil end)
    Mox.stub(WandererNotifier.MockConfig, :get_env, fn _app, _key, default -> default end)
    Mox.stub(WandererNotifier.MockConfig, :static_info_cache_ttl, fn -> 3600 end)
    Mox.stub(WandererNotifier.MockConfig, :get_map_config, fn -> %{} end)
    Mox.stub(WandererNotifier.MockConfig, :map_url, fn -> "https://example.com" end)
    Mox.stub(WandererNotifier.MockConfig, :map_token, fn -> "token" end)
    Mox.stub(WandererNotifier.MockConfig, :map_csrf_token, fn -> "csrf_token" end)
    Mox.stub(WandererNotifier.MockConfig, :map_name, fn -> "Test Map" end)
    Mox.stub(WandererNotifier.MockConfig, :notifier_api_token, fn -> "api_token" end)
    Mox.stub(WandererNotifier.MockConfig, :license_key, fn -> "license_key" end)

    Mox.stub(WandererNotifier.MockConfig, :license_manager_api_url, fn ->
      "https://license-api.example.com"
    end)

    Mox.stub(WandererNotifier.MockConfig, :license_manager_api_key, fn -> "license_api_key" end)

    Mox.stub(WandererNotifier.MockConfig, :discord_channel_id_for, fn feature ->
      case feature do
        :kill_charts -> "123456789"
        :activity_charts -> "123456789"
        :system_notifications -> "123456789"
        :character_notifications -> "123456789"
        _other -> "123456789"
      end
    end)

    Mox.stub(WandererNotifier.MockConfig, :discord_channel_id_for_activity_charts, fn ->
      "123456789"
    end)
  end
end

defmodule WandererNotifier.MockZKillClientExtensions do
  @moduledoc """
  Extensions to add required behavior functions to MockZKillClient.
  """

  def add_expectations do
    Mox.stub(WandererNotifier.MockZKillClient, :get_single_killmail, fn _kill_id ->
      {:ok, %{"killmail_id" => 12345, "zkb" => %{"hash" => "abc123"}}}
    end)

    Mox.stub(WandererNotifier.MockZKillClient, :get_system_kills, fn _system_id, _limit ->
      {:ok, [%{"killmail_id" => 12345, "zkb" => %{"hash" => "abc123"}}]}
    end)

    Mox.stub(WandererNotifier.MockZKillClient, :get_character_kills, fn _character_id,
                                                                        _date_range,
                                                                        _limit ->
      {:ok, [%{"killmail_id" => 12345, "zkb" => %{"hash" => "abc123"}}]}
    end)

    Mox.stub(WandererNotifier.MockZKillClient, :get_recent_kills, fn _limit ->
      {:ok, [%{"killmail_id" => 12345, "zkb" => %{"hash" => "abc123"}}]}
    end)
  end
end

# Add MockRepositoryApi for the tests failing with "could not load module WandererNotifier.Resources.MockApi"
# Convert to a proper Mox mock
Mox.defmock(WandererNotifier.Resources.MockApi, for: WandererNotifier.Resources.ApiBehaviour)

# Setup MockRepository extensions
defmodule WandererNotifier.MockRepositoryExtensions do
  @moduledoc """
  Extensions for the MockRepository module.
  """

  def add_expectations do
    # Add query stub to the MockRepository
    Mox.stub(WandererNotifier.MockRepository, :query, fn _query -> {:ok, []} end)
    # Add read stub to the Resources.MockApi
    Mox.stub(WandererNotifier.Resources.MockApi, :read, fn _query -> {:ok, []} end)
  end
end

# Setup the mock for WandererNotifier.Api.Map.Systems that is referenced in some tests
defmodule WandererNotifier.Api.Map.Systems do
  @moduledoc """
  Mock for the Map Systems API that is referenced in tests.
  """

  def get_system_info(system_id) do
    {:ok,
     %{
       "system_id" => system_id,
       "name" => "Test System",
       "region_id" => "10000001",
       "region_name" => "Test Region",
       "security_status" => 0.5,
       "security_class" => "C1"
     }}
  end
end

# Update Data.Cache.RepositoryMock to use the correct behavior
Mox.defmock(WandererNotifier.Data.Cache.RepositoryMock,
  for: WandererNotifier.Data.Cache.RepositoryBehaviour
)

# Add missing MockKillmailChartAdapter
defmodule WandererNotifier.Charts.KillmailChartAdapterBehaviour do
  @callback generate_charts() :: any()
  @callback send_charts(any()) :: any()
  @callback generate_weekly_kills_chart() :: {:ok, String.t()} | {:error, any()}
end

Mox.defmock(WandererNotifier.MockKillmailChartAdapter,
  for: WandererNotifier.Charts.KillmailChartAdapterBehaviour
)

# Add MockStructuredFormatter
Mox.defmock(WandererNotifier.MockStructuredFormatter,
  for: WandererNotifier.Notifiers.StructuredFormatterBehaviour
)
