# First, define the mock modules at the root level
defmodule WandererNotifier.MockCache do
  @behaviour WandererNotifier.Cache.Behaviour

  # Mock state that can be configured per test
  def configure(systems, characters) do
    # Create the ETS table if it doesn't exist
    if :ets.info(:mock_cache) == :undefined do
      :ets.new(:mock_cache, [:set, :public, :named_table])
    end

    :ets.insert(:mock_cache, {:systems, systems})
    :ets.insert(:mock_cache, {:characters, characters})
  end

  def configure_direct_character(character_id, character_data) do
    # Create the ETS table if it doesn't exist
    if :ets.info(:mock_cache) == :undefined do
      :ets.new(:mock_cache, [:set, :public, :named_table])
    end

    :ets.insert(:mock_cache, {{:direct_character, character_id}, character_data})
  end

  def get(key) do
    # Ensure table exists
    if :ets.info(:mock_cache) == :undefined do
      :ets.new(:mock_cache, [:set, :public, :named_table])
      {:error, :not_found}
    else
      get_by_key_type(key)
    end
  end

  defp get_by_key_type("map:systems") do
    case :ets.lookup(:mock_cache, :systems) do
      [{:systems, systems}] -> {:ok, systems}
      _ -> {:ok, []}
    end
  end

  defp get_by_key_type(key) when key in ["character:list", "map:characters"] do
    case :ets.lookup(:mock_cache, :characters) do
      [{:characters, characters}] -> {:ok, characters}
      _ -> {:ok, []}
    end
  end

  defp get_by_key_type("tracked:character:" <> character_id) do
    case :ets.lookup(:mock_cache, {:direct_character, character_id}) do
      [{{:direct_character, ^character_id}, data}] -> {:ok, data}
      _ -> {:error, :not_found}
    end
  end

  defp get_by_key_type(_key), do: {:error, :not_found}

  # Implement required interface methods
  def put(_key, _value), do: {:ok, :mock}
  def put(_key, _value, _ttl), do: {:ok, :mock}
  def delete(_key), do: {:ok, :mock}
  def clear(), do: {:ok, :mock}
  def get_and_update(_key, _fun), do: {:ok, :mock, :mock}
  def set(_key, _value, _opts), do: {:ok, :mock}
  def init_batch_logging(), do: :ok
  def get_recent_kills(), do: []
end

defmodule WandererNotifier.MockDeduplication do
  @behaviour WandererNotifier.Notifications.Helpers.DeduplicationBehaviour

  # Make sure the ETS table exists
  def ensure_table_exists do
    if :ets.info(:mock_deduplication) == :undefined do
      :ets.new(:mock_deduplication, [:set, :public, :named_table])
    end

    # Initialize the default state if it doesn't exist
    if :ets.lookup(:mock_deduplication, :is_duplicate) == [] do
      :ets.insert(:mock_deduplication, {:is_duplicate, false})
    end
  end

  # Configurable deduplication state
  def configure(is_duplicate \\ false) do
    ensure_table_exists()
    :ets.insert(:mock_deduplication, {:is_duplicate, is_duplicate})
    :ok
  end

  # Check if a kill ID is a duplicate
  def check(:kill, _id) do
    ensure_table_exists()

    case :ets.lookup(:mock_deduplication, :is_duplicate) do
      [{:is_duplicate, true}] ->
        {:ok, :duplicate}

      _ ->
        {:ok, :new}
    end
  end

  def clear_key(_type, _id), do: {:ok, :cleared}
end

# Now define the test module
defmodule WandererNotifier.Notifications.Determiner.KillTest do
  use ExUnit.Case, async: false

  alias WandererNotifier.Notifications.Determiner.Kill
  alias WandererNotifier.Killmail.Killmail
  alias WandererNotifier.MockCache
  alias WandererNotifier.MockDeduplication

  # Define MockConfig that will be consistent across all tests
  defmodule MockConfig do
    def notifications_enabled?, do: true
    def system_notifications_enabled?, do: true
    def character_notifications_enabled?, do: true
  end

  # Disabled notifications config for specific tests
  defmodule DisabledNotificationsConfig do
    def notifications_enabled?, do: false
    def system_notifications_enabled?, do: true
    def character_notifications_enabled?, do: true
  end

  # Disabled system notifications config for specific tests
  defmodule DisabledSystemNotificationsConfig do
    def notifications_enabled?, do: true
    def system_notifications_enabled?, do: false
    def character_notifications_enabled?, do: true
  end

  setup do
    # Create ETS table for mock cache - delete first if it exists
    if :ets.info(:mock_cache) != :undefined do
      :ets.delete(:mock_cache)
    end

    :ets.new(:mock_cache, [:set, :public, :named_table])

    # Create ETS table for mock deduplication - delete first if it exists
    if :ets.info(:mock_deduplication) != :undefined do
      :ets.delete(:mock_deduplication)
    end

    :ets.new(:mock_deduplication, [:set, :public, :named_table])
    :ets.insert(:mock_deduplication, {:is_duplicate, false})

    # Store original app environment settings to restore later
    original_config = Application.get_env(:wanderer_notifier, :config)
    original_cache_repo = Application.get_env(:wanderer_notifier, :cache_repo)
    original_deduplication = Application.get_env(:wanderer_notifier, :deduplication_module)

    # Override the config module for testing
    Application.put_env(:wanderer_notifier, :config, MockConfig)

    # Use our simple mock modules
    Application.put_env(:wanderer_notifier, :cache_repo, MockCache)
    Application.put_env(:wanderer_notifier, :deduplication_module, MockDeduplication)

    # Set up basic test data
    test_killmail = %Killmail{
      killmail_id: "12345",
      zkb: %{"totalValue" => 1_000_000, "points" => 10},
      esi_data: %{
        "solar_system_id" => "30000142",
        "victim" => %{
          "character_id" => "1000001",
          "corporation_id" => "2000001",
          "ship_type_id" => "3000001"
        },
        "attackers" => [
          %{
            "character_id" => "1000002",
            "corporation_id" => "2000002",
            "ship_type_id" => "3000002"
          }
        ]
      }
    }

    raw_killmail = %{
      "killmail_id" => "12345",
      "solar_system_id" => "30000142",
      "victim" => %{
        "character_id" => "1000001",
        "corporation_id" => "2000001",
        "ship_type_id" => "3000001"
      },
      "attackers" => [
        %{
          "character_id" => "1000002",
          "corporation_id" => "2000002",
          "ship_type_id" => "3000002"
        }
      ],
      "zkb" => %{"totalValue" => 1_000_000, "points" => 10}
    }

    # Default configuration
    MockCache.configure([], [])
    MockDeduplication.configure(false)

    on_exit(fn ->
      # Clean up ETS tables if they still exist
      if :ets.info(:mock_cache) != :undefined do
        :ets.delete(:mock_cache)
      end

      if :ets.info(:mock_deduplication) != :undefined do
        :ets.delete(:mock_deduplication)
      end

      # Restore original settings, or delete if they were not set
      if original_config,
        do: Application.put_env(:wanderer_notifier, :config, original_config),
        else: Application.delete_env(:wanderer_notifier, :config)

      if original_cache_repo,
        do: Application.put_env(:wanderer_notifier, :cache_repo, original_cache_repo),
        else: Application.delete_env(:wanderer_notifier, :cache_repo)

      if original_deduplication,
        do:
          Application.put_env(:wanderer_notifier, :deduplication_module, original_deduplication),
        else: Application.delete_env(:wanderer_notifier, :deduplication_module)
    end)

    {:ok, %{killmail_struct: test_killmail, killmail_map: raw_killmail}}
  end

  describe "should_notify?/1" do
    setup do
      # Delete and recreate the deduplication table for each test to ensure complete isolation
      if :ets.info(:mock_deduplication) != :undefined do
        :ets.delete(:mock_deduplication)
      end

      :ets.new(:mock_deduplication, [:set, :public, :named_table])
      :ets.insert(:mock_deduplication, {:is_duplicate, false})

      # Reset the MockCache table to ensure clean state
      if :ets.info(:mock_cache) != :undefined do
        :ets.delete(:mock_cache)
      end

      :ets.new(:mock_cache, [:set, :public, :named_table])
      MockCache.configure([], [])

      # Reset MockDeduplication for each test
      MockDeduplication.configure(false)
      :ok
    end

    test "returns false when notifications are disabled", %{killmail_struct: killmail} do
      # Configure the mock to make the system tracked and not duplicated
      MockCache.configure([%{solar_system_id: "30000142", name: "Test System"}], [])

      # Override the config module
      Application.put_env(:wanderer_notifier, :config, DisabledNotificationsConfig)

      # Execute
      result = Kill.should_notify?(killmail)

      # Verify
      assert {:ok, %{should_notify: false, reason: "Notifications disabled"}} = result
    end

    test "returns false when system notifications are disabled", %{killmail_struct: killmail} do
      # Configure the mock to make the system tracked and not duplicated
      MockCache.configure([%{solar_system_id: "30000142", name: "Test System"}], [])

      # Override the config module
      Application.put_env(:wanderer_notifier, :config, DisabledSystemNotificationsConfig)

      # Execute
      result = Kill.should_notify?(killmail)

      # Verify
      assert {:ok, %{should_notify: false, reason: "Notifications disabled"}} = result
    end

    test "returns false when not tracked by any system or character", %{killmail_struct: killmail} do
      # Configure the mock with empty tracking lists
      MockCache.configure([], [])

      # Make sure we're using the default config
      Application.put_env(:wanderer_notifier, :config, MockConfig)

      # Execute
      result = Kill.should_notify?(killmail)

      # Verify
      expected_reason = "Not tracked by any character or system"
      assert {:ok, %{should_notify: false, reason: ^expected_reason}} = result
    end

    test "returns true when tracked system and not duplicated", %{killmail_struct: killmail} do
      # Configure the mock with tracked system
      MockCache.configure([%{solar_system_id: "30000142", name: "Test System"}], [])

      # Explicitly set deduplication to false for this test
      MockDeduplication.configure(false)

      # Make sure we're using the default config
      Application.put_env(:wanderer_notifier, :config, MockConfig)

      # Execute
      result = Kill.should_notify?(killmail)

      # Verify
      assert {:ok, %{should_notify: true, reason: nil}} = result
    end

    test "returns true when tracked character and not duplicated", %{killmail_struct: killmail} do
      # Configure the mock with tracked character
      MockCache.configure([], [%{character_id: "1000001", name: "Test Character"}])

      # Explicitly set deduplication to false for this test
      MockDeduplication.configure(false)

      # Make sure we're using the default config
      Application.put_env(:wanderer_notifier, :config, MockConfig)

      # Execute
      result = Kill.should_notify?(killmail)

      # Verify
      assert {:ok, %{should_notify: true, reason: nil}} = result
    end

    test "returns false for duplicate kill", %{killmail_struct: killmail} do
      # Make a completely fresh state for this test
      if :ets.info(:mock_deduplication) != :undefined do
        :ets.delete(:mock_deduplication)
      end

      :ets.new(:mock_deduplication, [:set, :public, :named_table])
      :ets.insert(:mock_deduplication, {:is_duplicate, true})

      # Configure the mock with tracked system
      MockCache.configure([%{solar_system_id: "30000142", name: "Test System"}], [])

      # Make sure we're using the default config
      Application.put_env(:wanderer_notifier, :config, MockConfig)

      # Execute
      result = Kill.should_notify?(killmail)

      # Verify
      assert {:ok, %{should_notify: false, reason: "Duplicate kill"}} = result
    end
  end

  describe "get_kill_system_id/1" do
    test "extracts system ID from Killmail struct", %{killmail_struct: killmail} do
      result = Kill.get_kill_system_id(killmail)
      assert result == "30000142"
    end

    test "extracts system ID from map", %{killmail_map: killmail} do
      result = Kill.get_kill_system_id(killmail)
      assert result == "30000142"
    end

    test "returns unknown for nil input" do
      result = Kill.get_kill_system_id(nil)
      assert result == "unknown"
    end

    test "returns unknown for Killmail with nil esi_data", %{killmail_struct: killmail} do
      killmail = %{killmail | esi_data: nil}
      result = Kill.get_kill_system_id(killmail)
      assert result == "unknown"
    end
  end

  describe "tracked_system?/1" do
    test "returns false for nil system ID" do
      # Configure the mock with empty tracking lists
      MockCache.configure([], [])

      result = Kill.tracked_system?(nil)
      assert result == false
    end

    test "returns true when system is tracked" do
      # Configure the mock with a tracked system
      MockCache.configure([%{solar_system_id: "30000142", name: "Test System"}], [])

      # Test with string ID
      result = Kill.tracked_system?("30000142")
      assert result == true
    end

    test "returns false when system is not tracked" do
      # Configure the mock with a different tracked system
      MockCache.configure([%{solar_system_id: "10000001", name: "Other System"}], [])

      result = Kill.tracked_system?("30000142")
      assert result == false
    end

    test "returns false when tracked systems list is empty" do
      # Configure the mock with empty tracking lists
      MockCache.configure([], [])

      result = Kill.tracked_system?("30000142")
      assert result == false
    end

    test "returns false when tracked systems cache returns error" do
      # Force an error by using a nil key (which will return an error)
      # This is a hack but it works for testing
      MockCache.configure(nil, [])

      # Run the test
      result = Kill.tracked_system?("30000142")
      assert result == false
    end
  end

  describe "has_tracked_character?/1" do
    test "returns true when victim is tracked", %{killmail_struct: killmail} do
      # Configure the mock with a tracked victim character
      MockCache.configure([], [%{character_id: "1000001", name: "Test Victim"}])

      result = Kill.has_tracked_character?(killmail)
      assert result == true
    end

    test "returns true when attacker is tracked", %{killmail_struct: killmail} do
      # Configure the mock with a tracked attacker character
      MockCache.configure([], [%{character_id: "1000002", name: "Test Attacker"}])

      result = Kill.has_tracked_character?(killmail)
      assert result == true
    end

    test "returns false when no characters are tracked", %{killmail_struct: killmail} do
      # Configure the mock with empty tracking lists
      MockCache.configure([], [])

      result = Kill.has_tracked_character?(killmail)
      assert result == false
    end

    test "returns false when tracked characters cache returns error", %{killmail_struct: killmail} do
      # Force an error by using a nil key
      MockCache.configure([], nil)

      # Run the test
      result = Kill.has_tracked_character?(killmail)
      assert result == false
    end

    test "checks direct character tracking when not in list", %{killmail_struct: killmail} do
      # Configure the mock with empty character list but a direct character lookup
      MockCache.configure([], [])

      # Configure direct character tracking for victim
      MockCache.configure_direct_character("1000001", %{
        character_id: "1000001",
        name: "Test Victim"
      })

      # Execute
      result = Kill.has_tracked_character?(killmail)

      assert result == true
    end
  end
end
