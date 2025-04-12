defmodule WandererNotifier.Killmail.Processing.ProcessorTest do
  use ExUnit.Case, async: false

  import Mox

  alias WandererNotifier.Killmail.Core.{Context, Data}
  alias WandererNotifier.Killmail.Processing.Processor
  alias WandererNotifier.Killmail.Core.MockValidator
  alias WandererNotifier.Killmail.Processing.MockCache
  alias WandererNotifier.Killmail.Processing.MockEnrichment
  alias WandererNotifier.Killmail.Processing.MockNotificationDeterminer
  alias WandererNotifier.Killmail.Processing.MockNotification
  alias WandererNotifier.Killmail.Processing.MockPersistence
  alias WandererNotifier.Config.MockFeatures

  # Define mocks for testing
  Mox.defmock(WandererNotifier.Killmail.Core.MockValidator,
    for: WandererNotifier.Killmail.Core.ValidatorBehaviour
  )

  Mox.defmock(WandererNotifier.Killmail.Processing.MockCache,
    for: WandererNotifier.Killmail.Processing.CacheBehaviour
  )

  Mox.defmock(WandererNotifier.Killmail.Processing.MockEnrichment,
    for: WandererNotifier.Killmail.Processing.EnrichmentBehaviour
  )

  Mox.defmock(WandererNotifier.Killmail.Processing.MockNotificationDeterminer,
    for: WandererNotifier.Killmail.Processing.NotificationDeterminerBehaviour
  )

  Mox.defmock(WandererNotifier.Killmail.Processing.MockNotification,
    for: WandererNotifier.Killmail.Processing.NotificationBehaviour
  )

  Mox.defmock(WandererNotifier.Killmail.Processing.MockPersistence,
    for: WandererNotifier.Killmail.Processing.PersistenceBehaviour
  )

  # Set up test data
  @valid_killmail %Data{
    killmail_id: 12345,
    solar_system_id: 30_000_142,
    kill_time: DateTime.utc_now()
  }

  @context %Context{
    character_id: nil,
    character_name: nil,
    source: :test,
    mode: %WandererNotifier.Killmail.Core.Mode{
      mode: :test,
      options: %{persist: true, notify: true, cache: true}
    }
  }

  # Use a setup block to verify and set expectations
  setup :verify_on_exit!

  setup do
    # Apply mock expectations from extensions (only the ones we need)
    WandererNotifier.MockConfigExtensions.add_expectations()
    # Add MockFeatureExtensions expectations specifically for Features
    WandererNotifier.MockFeatureExtensions.add_expectations()
    # Don't apply ZKillClient extensions as they're causing errors and aren't needed for this test
    # WandererNotifier.MockZKillClientExtensions.add_expectations()
    WandererNotifier.MockRepositoryExtensions.add_expectations()

    # Important: Configure application to use our mocks during tests
    # This ensures the actual implementation uses our mocks
    Application.put_env(:wanderer_notifier, :validator, MockValidator)
    Application.put_env(:wanderer_notifier, :enrichment, MockEnrichment)
    Application.put_env(:wanderer_notifier, :cache, MockCache)
    Application.put_env(:wanderer_notifier, :persistence_module, MockPersistence)
    Application.put_env(:wanderer_notifier, :notification_determiner, MockNotificationDeterminer)
    Application.put_env(:wanderer_notifier, :notification, MockNotification)

    # Removed direct stubbing of MockFeatures as we're now using MockFeatureExtensions

    :ok
  end

  describe "process_killmail/2" do
    test "processes a valid killmail successfully" do
      # Set up mocks to simulate successful processing
      expect(MockValidator, :validate, fn _killmail -> :ok end)

      expect(MockEnrichment, :enrich, fn killmail ->
        enriched = %{killmail | solar_system_name: "Jita"}
        {:ok, enriched}
      end)

      expect(MockCache, :in_cache?, fn _id -> false end)
      expect(MockCache, :cache, fn killmail -> {:ok, killmail} end)

      expect(MockPersistence, :persist, fn killmail ->
        persisted = %{killmail | persisted: true}
        {:ok, persisted}
      end)

      expect(MockNotificationDeterminer, :should_notify?, fn _killmail ->
        {:ok, {true, "Test notification"}}
      end)

      expect(MockNotification, :notify, fn _killmail -> :ok end)

      # Call the function being tested
      result = Processor.process_killmail(@valid_killmail, @context)

      # Verify the result
      assert {:ok, killmail} = result
      assert killmail.persisted == true
      assert killmail.solar_system_name == "Jita"
    end

    test "skips notification when determiner returns false" do
      # Set up mocks
      expect(MockValidator, :validate, fn _killmail -> :ok end)
      expect(MockEnrichment, :enrich, fn killmail -> {:ok, killmail} end)
      expect(MockCache, :in_cache?, fn _id -> false end)
      expect(MockCache, :cache, fn killmail -> {:ok, killmail} end)
      expect(MockPersistence, :persist, fn killmail -> {:ok, killmail} end)

      expect(MockNotificationDeterminer, :should_notify?, fn _killmail ->
        {:ok, {false, "No notification needed"}}
      end)

      # Notification should not be called

      # Call the function
      result = Processor.process_killmail(@valid_killmail, @context)

      # Verify the result
      assert {:ok, _killmail} = result
    end

    test "forces notification when context has force_notification flag" do
      force_context = Map.put(@context, :force_notification, true)

      # Set up mocks - notification determiner should NOT be called
      expect(MockValidator, :validate, fn _killmail -> :ok end)
      expect(MockEnrichment, :enrich, fn killmail -> {:ok, killmail} end)
      expect(MockCache, :in_cache?, fn _id -> false end)
      expect(MockCache, :cache, fn killmail -> {:ok, killmail} end)
      expect(MockPersistence, :persist, fn killmail -> {:ok, killmail} end)

      # Notification should be called regardless of determiner
      expect(MockNotification, :notify, fn _killmail -> :ok end)

      # Call the function
      result = Processor.process_killmail(@valid_killmail, force_context)

      # Verify the result
      assert {:ok, _killmail} = result
    end

    test "returns error when validation fails" do
      # Set up validator to fail
      expect(MockValidator, :validate, fn _killmail ->
        {:error, [missing_system_id: "Solar system ID is required"]}
      end)

      expect(MockValidator, :log_validation_errors, fn _killmail, _errors -> :ok end)

      # Call the function
      result = Processor.process_killmail(@valid_killmail, @context)

      # Verify the result
      assert {:error, {stage, _reason}} = result
      assert stage == :validation
    end

    test "returns error when enrichment fails" do
      # Set up validation to pass but enrichment to fail
      expect(MockValidator, :validate, fn _killmail -> :ok end)

      expect(MockEnrichment, :enrich, fn _killmail ->
        {:error, :failed_to_enrich}
      end)

      # Call the function
      result = Processor.process_killmail(@valid_killmail, @context)

      # Verify the result
      assert {:error, :failed_to_enrich} = result
    end

    test "returns error when persistence fails" do
      # Set up mocks
      expect(MockValidator, :validate, fn _killmail -> :ok end)
      expect(MockEnrichment, :enrich, fn killmail -> {:ok, killmail} end)
      expect(MockCache, :in_cache?, fn _id -> false end)
      expect(MockCache, :cache, fn killmail -> {:ok, killmail} end)

      expect(MockPersistence, :persist, fn _killmail ->
        {:error, :database_error}
      end)

      # Call the function
      result = Processor.process_killmail(@valid_killmail, @context)

      # Verify the result
      assert {:error, :database_error} = result
    end

    test "skips processing with a skip code" do
      # Set up validation to return skip code
      expect(MockValidator, :validate, fn _killmail -> {:skip, "Not interesting"} end)

      # Call the function
      result = Processor.process_killmail(@valid_killmail, @context)

      # Verify the result
      assert {:ok, :skipped} = result
    end

    test "handles non-Data input by converting to Data struct" do
      # Raw map input
      raw_map = %{
        "killmail_id" => 12345,
        "zkb" => %{"hash" => "abc123"}
      }

      # Set up mocks for the rest of the pipeline
      expect(MockValidator, :validate, fn _killmail -> :ok end)
      expect(MockEnrichment, :enrich, fn killmail -> {:ok, killmail} end)
      expect(MockCache, :in_cache?, fn _id -> false end)
      expect(MockCache, :cache, fn killmail -> {:ok, killmail} end)
      expect(MockPersistence, :persist, fn killmail -> {:ok, killmail} end)

      expect(MockNotificationDeterminer, :should_notify?, fn _killmail ->
        {:ok, {false, "Test"}}
      end)

      # Call the function with raw map
      result = Processor.process_killmail(raw_map, @context)

      # Verify the result
      assert {:ok, killmail} = result
      assert %Data{} = killmail
      assert killmail.killmail_id == 12345
    end
  end
end
