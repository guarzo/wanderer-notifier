defmodule WandererNotifier.Domains.Killmail.PipelineTest do
  use ExUnit.Case, async: true
  import Mox

  alias WandererNotifier.Domains.Killmail.Pipeline
  alias WandererNotifier.Test.Support.Helpers.ESIMockHelper
  alias WandererNotifier.Infrastructure.Cache.Keys, as: CacheKeys
  alias WandererNotifier.Shared.Utils.TimeUtils

  # Define MockConfig for testing
  defmodule MockConfig do
    def notifications_enabled?, do: true
    def system_notifications_enabled?, do: true
    def character_notifications_enabled?, do: true
    def deduplication_module, do: WandererNotifier.Domains.Notifications.CacheImpl
    def system_track_module, do: WandererNotifier.MockSystem
    def character_track_module, do: WandererNotifier.MockCharacter
    def notification_determiner_module, do: WandererNotifier.Domains.Notifications.Determiner.Kill
    def killmail_enrichment_module, do: WandererNotifier.Domains.Killmail.Enrichment

    def killmail_notification_module,
      do: WandererNotifier.Domains.Notifications.KillmailNotification

    def config_module, do: __MODULE__
  end

  # Define MockCache for the tests
  defmodule MockCache do
    def get(key) do
      cond do
        key == CacheKeys.map_systems() ->
          {:ok, []}

        key == CacheKeys.map_characters() ->
          {:ok, [character_id: "100", name: "Victim"]}

        String.starts_with?(key, "tracked_character:") ->
          {:error, :not_found}

        true ->
          {:error, :not_found}
      end
    end

    def put(_key, _value), do: {:ok, :mock}
    def put(_key, _value, _ttl), do: {:ok, :mock}
    def delete(_key), do: {:ok, :mock}
    def clear(), do: {:ok, :mock}
    def get_and_update(_key, _fun), do: {:ok, :mock, :mock}
    def set(_key, _value, _opts), do: {:ok, :mock}
    def init_batch_logging(), do: :ok
    def get_recent_kills(), do: []
  end

  # Use real deduplication implementation (CacheImpl)

  # Define MockMetrics for the tests
  defmodule MockMetrics do
    def track_processing_start(_), do: :ok
    def track_processing_end(_, _), do: :ok
    def track_error(_, _), do: :ok
    def track_notification_sent(_, _), do: :ok
    def track_skipped_notification(_, _), do: :ok
    def track_zkill_webhook_received(), do: :ok
    def track_zkill_processing_status(_, _), do: :ok
  end

  # Make sure mocks are verified when the test exits
  setup :verify_on_exit!

  setup do
    # Ensure Cachex application is started
    case Application.ensure_all_started(:cachex) do
      {:ok, _apps} -> :ok
      {:error, _reason} -> :ok
    end

    # Use the correct cache name from config
    cache_name = Application.get_env(:wanderer_notifier, :cache_name, :wanderer_notifier_cache)

    # Start Cachex cache for tests - ignore if already started
    case Cachex.start_link(name: cache_name, limit: 1000) do
      {:ok, _pid} -> :ok
      {:error, {:already_started, _pid}} -> :ok
      # Ignore other errors for test simplicity
      _ -> :ok
    end

    # Set up Mox for ESI.Service
    Application.put_env(
      :wanderer_notifier,
      :esi_service,
      WandererNotifier.Infrastructure.Adapters.ESI.ServiceMock
    )

    # Set up config module
    Application.put_env(:wanderer_notifier, :config, MockConfig)

    # Set up cache module and deduplication - use real implementation
    Application.put_env(:wanderer_notifier, :cache_repo, MockCache)

    Application.put_env(
      :wanderer_notifier,
      :deduplication_module,
      WandererNotifier.Domains.Notifications.CacheImpl
    )

    # Set up metrics module
    Application.put_env(:wanderer_notifier, :metrics, MockMetrics)

    # Set up WandererNotifier.HTTPMock
    Application.put_env(
      :wanderer_notifier,
      :http_client,
      WandererNotifier.HTTPMock
    )

    # Add stub for HTTPMock.request/5
    WandererNotifier.HTTPMock
    |> stub(:request, fn method, url, _body, _headers, _opts ->
      cond do
        method == :get and String.contains?(url, "killmails/12345/test_hash") ->
          {:ok,
           %{
             status_code: 200,
             body: %{
               "killmail_id" => 12_345,
               "victim" => %{
                 "character_id" => 100,
                 "corporation_id" => 300,
                 "ship_type_id" => 200
               },
               "killmail_time" => TimeUtils.log_timestamp(),
               "solar_system_id" => 30_000_142,
               "attackers" => []
             }
           }}

        method == :get and String.contains?(url, "killmails/54321/error_hash") ->
          {:error, :timeout}

        true ->
          {:ok, %{status_code: 404, body: %{"error" => "Not found"}}}
      end
    end)

    # Set up default stubs using the helper
    ESIMockHelper.setup_esi_mocks()

    # Always stub the DiscordNotifier with a default response
    stub(WandererNotifier.Test.Mocks.Discord, :send_kill_notification, fn _killmail,
                                                                          _type,
                                                                          input_opts ->
      _formatted_opts = if is_map(input_opts), do: Map.to_list(input_opts), else: input_opts
      :ok
    end)

    :ok
  end

  describe "process_killmail/1" do
    test "process_killmail/1 successfully processes a valid killmail" do
      zkb_data = %{
        "killmail_id" => 12_345,
        "zkb" => %{"hash" => "test_hash"},
        "solar_system_id" => 30_000_142
      }

      # Set up cache data to make system tracked
      cache_name = Application.get_env(:wanderer_notifier, :cache_name, :wanderer_notifier_cache)
      Cachex.put(cache_name, "map:systems", [%{"solar_system_id" => 30_000_142}])
      Cachex.put(cache_name, "map:character_list", [])

      # Pipeline works with pre-enriched WebSocket data, no ESI calls needed

      # Execute the test - don't mock deduplication or Discord as they work in TEST MODE
      result = Pipeline.process_killmail(zkb_data)
      assert {:ok, _} = result
    end

    test "process_killmail/1 skips processing when notification is not needed" do
      zkb_data = %{
        "killmail_id" => 12_345,
        "zkb" => %{"hash" => "test_hash"},
        "solar_system_id" => 30_000_142
      }

      # Set up cache data with no tracked systems/characters
      cache_name = Application.get_env(:wanderer_notifier, :cache_name, :wanderer_notifier_cache)
      Cachex.put(cache_name, "map:systems", [])
      Cachex.put(cache_name, "map:character_list", [])

      # Execute the test - should be skipped because neither system nor character is tracked
      result = Pipeline.process_killmail(zkb_data)
      assert {:ok, :skipped} = result
    end

    test "process_killmail/1 handles enrichment errors" do
      zkb_data = %{
        "killmail_id" => 54_321,
        "zkb" => %{"hash" => "error_hash"}
        # Missing system_id to trigger error
      }

      # Don't expect deduplication check since error happens before that
      # Execute the test - should error due to missing system_id
      result = Pipeline.process_killmail(zkb_data)
      assert {:error, :missing_system_id} = result
    end

    test "process_killmail/1 handles invalid payload" do
      # Missing killmail_id
      zkb_data = %{
        "zkb" => %{"hash" => "test_hash"},
        "solar_system_id" => 30_000_142
      }

      # Execute the test - should error due to missing killmail_id
      result = Pipeline.process_killmail(zkb_data)
      assert {:error, :missing_killmail_id} = result
    end

    test "process_killmail/1 handles duplicate killmail" do
      zkb_data = %{
        "killmail_id" => 12_345,
        "zkb" => %{"hash" => "test_hash"},
        "solar_system_id" => 30_000_142
      }

      # First, prime the cache to make this killmail appear as a duplicate
      # by processing it once first
      cache_name = Application.get_env(:wanderer_notifier, :cache_name, :wanderer_notifier_cache)
      Cachex.put(cache_name, "map:systems", [%{"solar_system_id" => 30_000_142}])
      Cachex.put(cache_name, "map:character_list", [])

      # Pipeline works with pre-enriched WebSocket data, no ESI calls needed

      # Process once to create the deduplication entry
      Pipeline.process_killmail(zkb_data)

      # Now process again - this should be detected as duplicate
      result = Pipeline.process_killmail(zkb_data)
      assert {:ok, :skipped} = result
    end

    test "process_killmail/1 handles invalid system ID" do
      zkb_data = %{
        "killmail_id" => 99_999,
        "zkb" => %{"hash" => "test_hash"},
        "solar_system_id" => "invalid"
      }

      # Don't expect deduplication check since error happens before that
      # Execute the test - should error due to invalid system_id parsing to nil
      result = Pipeline.process_killmail(zkb_data)
      assert {:error, :missing_system_id} = result
    end
  end
end
