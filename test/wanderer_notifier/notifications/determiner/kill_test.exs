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
  import Mox
  alias WandererNotifier.Notifications.Determiner.Kill
  alias WandererNotifier.Killmail.Killmail

  # Define mocks
  Mox.defmock(WandererNotifier.Map.MapSystemMock, for: WandererNotifier.Map.SystemBehaviour)
  Mox.defmock(WandererNotifier.Map.MapCharacterMock, for: WandererNotifier.Map.CharacterBehaviour)

  # Setup mocks
  setup :verify_on_exit!

  # Test configuration modules
  defmodule MockConfig do
    def notifications_enabled?, do: true
    def system_notifications_enabled?, do: true
    def character_notifications_enabled?, do: true
    def chain_kills_mode?, do: false
  end

  defmodule DisabledNotificationsConfig do
    def notifications_enabled?, do: false
    def system_notifications_enabled?, do: false
    def character_notifications_enabled?, do: false
    def chain_kills_mode?, do: false
  end

  defmodule DisabledSystemNotificationsConfig do
    def notifications_enabled?, do: true
    def system_notifications_enabled?, do: false
    def character_notifications_enabled?, do: true
    def chain_kills_mode?, do: false
  end

  defmodule DisabledCharacterNotificationsConfig do
    def notifications_enabled?, do: true
    def system_notifications_enabled?, do: true
    def character_notifications_enabled?, do: false
    def chain_kills_mode?, do: false
  end

  defmodule ChainKillsConfig do
    def notifications_enabled?, do: true
    def system_notifications_enabled?, do: true
    def character_notifications_enabled?, do: true
    def chain_kills_mode?, do: true
  end

  setup do
    # Create ETS tables for mock caching and deduplication
    :ets.new(:mock_cache, [:named_table, :public, :set])
    :ets.new(:mock_deduplication, [:named_table, :public, :set])

    # Store original application env
    original_config = Application.get_env(:wanderer_notifier, :config)
    original_system_module = Application.get_env(:wanderer_notifier, :system_module)
    original_character_module = Application.get_env(:wanderer_notifier, :character_module)
    original_deduplication_module = Application.get_env(:wanderer_notifier, :deduplication_module)

    # Override configuration for testing
    Application.put_env(:wanderer_notifier, :config, MockConfig)
    Application.put_env(:wanderer_notifier, :system_module, WandererNotifier.Map.MapSystemMock)

    Application.put_env(
      :wanderer_notifier,
      :character_module,
      WandererNotifier.Map.MapCharacterMock
    )

    Application.put_env(
      :wanderer_notifier,
      :deduplication_module,
      WandererNotifier.MockDeduplication
    )

    # Reset deduplication state
    WandererNotifier.MockDeduplication.configure(false)

    # Set up default mock expectations
    WandererNotifier.Map.MapSystemMock
    |> stub(:is_tracked?, fn _ -> {:ok, false} end)

    WandererNotifier.Map.MapCharacterMock
    |> stub(:is_tracked?, fn _ -> {:ok, false} end)

    # Create test killmail data
    test_killmail = %Killmail{
      killmail_id: "12345",
      esi_data: %{
        "solar_system_id" => "30000142",
        "victim" => %{
          "character_id" => "1000001",
          "character_name" => "Test Character",
          "corporation_id" => "2000001",
          "corporation_name" => "Test Corp",
          "ship_type_id" => "12345",
          "ship_type_name" => "Test Ship"
        },
        "attackers" => [
          %{
            "character_id" => "1000002",
            "character_name" => "Attacker 1",
            "corporation_id" => "2000002",
            "corporation_name" => "Attacker Corp"
          }
        ]
      },
      zkb: %{
        "totalValue" => 100_000_000,
        "points" => 100
      }
    }

    on_exit(fn ->
      # Restore original application env
      Application.put_env(:wanderer_notifier, :config, original_config)
      Application.put_env(:wanderer_notifier, :system_module, original_system_module)
      Application.put_env(:wanderer_notifier, :character_module, original_character_module)

      Application.put_env(
        :wanderer_notifier,
        :deduplication_module,
        original_deduplication_module
      )

      # Clean up ETS tables
      try do
        :ets.delete(:mock_cache)
        :ets.delete(:mock_deduplication)
      catch
        :error, :badarg -> :ok
      end
    end)

    {:ok, %{killmail: test_killmail}}
  end

  describe "should_notify?/1" do
    test "returns false for duplicate kills" do
      # Configure deduplication to return duplicate
      WandererNotifier.MockDeduplication.configure(true)

      killmail = %Killmail{
        killmail_id: "123",
        zkb: %{}
      }

      assert {:ok, %{should_notify: false, reason: "Duplicate kill"}} =
               Kill.should_notify?(killmail)
    end

    test "returns false when notifications are disabled" do
      defmodule DisabledConfig do
        def notifications_enabled?, do: false
        def system_notifications_enabled?, do: true
        def character_notifications_enabled?, do: true
      end

      Application.put_env(:wanderer_notifier, :config_module, DisabledConfig)

      killmail = %Killmail{
        killmail_id: "123",
        zkb: %{}
      }

      assert {:ok, %{should_notify: false, reason: "Notifications disabled"}} =
               Kill.should_notify?(killmail)
    end

    test "returns true for tracked system kills" do
      # Configure system tracking
      WandererNotifier.Map.MapSystemMock
      |> expect(:is_tracked?, fn "12345" -> {:ok, true} end)

      killmail = %Killmail{
        killmail_id: "123",
        esi_data: %{"solar_system_id" => "12345"},
        zkb: %{}
      }

      defmodule TrackedSystemConfig do
        def notifications_enabled?, do: true
        def system_notifications_enabled?, do: true
        def character_notifications_enabled?, do: true
      end

      Application.put_env(:wanderer_notifier, :config_module, TrackedSystemConfig)
      assert {:ok, %{should_notify: true, reason: nil}} = Kill.should_notify?(killmail)
    end

    test "returns true for tracked character kills" do
      # Configure character tracking
      WandererNotifier.Map.MapCharacterMock
      |> expect(:is_tracked?, fn "12345" -> {:ok, true} end)
      |> expect(:is_tracked?, fn _ -> {:ok, false} end)

      killmail = %Killmail{
        killmail_id: "123",
        esi_data: %{
          "victim" => %{"character_id" => "12345"},
          "attackers" => []
        },
        zkb: %{}
      }

      defmodule TrackedCharacterConfig do
        def notifications_enabled?, do: true
        def system_notifications_enabled?, do: true
        def character_notifications_enabled?, do: true
      end

      Application.put_env(:wanderer_notifier, :config_module, TrackedCharacterConfig)
      assert {:ok, %{should_notify: true, reason: nil}} = Kill.should_notify?(killmail)
    end
  end

  describe "get_kill_system_id/1" do
    test "extracts system ID from Killmail struct", %{killmail: killmail} do
      result = Kill.get_kill_system_id(killmail)
      assert result == "30000142"
    end

    test "returns unknown for nil input" do
      result = Kill.get_kill_system_id(nil)
      assert result == "unknown"
    end

    test "returns unknown for Killmail with nil esi_data", %{killmail: killmail} do
      killmail = %{killmail | esi_data: nil}
      result = Kill.get_kill_system_id(killmail)
      assert result == "unknown"
    end
  end

  describe "tracked_system?/1" do
    test "returns true when system is tracked" do
      WandererNotifier.Map.MapSystemMock
      |> expect(:is_tracked?, fn "30000142" -> {:ok, true} end)

      result = Kill.tracked_system?("30000142")
      assert result == true
    end

    test "returns false when system is not tracked" do
      WandererNotifier.Map.MapSystemMock
      |> expect(:is_tracked?, fn "30000142" -> {:ok, false} end)

      result = Kill.tracked_system?("30000142")
      assert result == false
    end

    test "returns false when tracked systems list is empty" do
      WandererNotifier.Map.MapSystemMock
      |> expect(:is_tracked?, fn "30000142" -> false end)

      result = Kill.tracked_system?("30000142")
      assert result == false
    end

    test "returns false when tracked systems cache returns error" do
      WandererNotifier.Map.MapSystemMock
      |> expect(:is_tracked?, fn "30000142" -> false end)

      result = Kill.tracked_system?("30000142")
      assert result == false
    end
  end

  describe "tracked_character?/1" do
    test "returns true when victim is tracked" do
      # Set up mock expectations
      WandererNotifier.Map.MapCharacterMock
      |> expect(:is_tracked?, fn "1000001" -> {:ok, true} end)

      assert Kill.tracked_character?("1000001")
    end

    test "returns true when attacker is tracked" do
      # Set up mock expectations
      WandererNotifier.Map.MapCharacterMock
      |> expect(:is_tracked?, fn "1000002" -> {:ok, true} end)

      assert Kill.tracked_character?("1000002")
    end

    test "checks direct character tracking when not in list" do
      # Set up mock expectations
      WandererNotifier.Map.MapCharacterMock
      |> expect(:is_tracked?, fn "1000001" -> {:ok, true} end)

      assert Kill.tracked_character?("1000001")
    end

    test "returns false when no characters are tracked" do
      # Set up mock expectations
      WandererNotifier.Map.MapCharacterMock
      |> expect(:is_tracked?, fn "1000001" -> {:ok, false} end)

      refute Kill.tracked_character?("1000001")
    end

    test "returns false when tracked characters cache returns error" do
      # Set up mock expectations
      WandererNotifier.Map.MapCharacterMock
      |> expect(:is_tracked?, fn "1000001" -> {:error, :not_found} end)

      refute Kill.tracked_character?("1000001")
    end

    test "properly detects a tracked character in killmail victim", %{killmail: killmail} do
      # Configure the mock with a tracked victim character
      WandererNotifier.Map.MapCharacterMock
      |> expect(:is_tracked?, fn "1000001" -> {:ok, true} end)
      |> expect(:is_tracked?, fn "1000002" -> {:ok, false} end)

      assert Kill.has_tracked_character?(killmail.esi_data)
    end

    test "properly detects a tracked character in killmail attackers", %{killmail: killmail} do
      # Configure the mock with a tracked attacker character
      WandererNotifier.Map.MapCharacterMock
      |> expect(:is_tracked?, fn "1000001" -> {:ok, false} end)
      |> expect(:is_tracked?, fn "1000002" -> {:ok, true} end)

      assert Kill.has_tracked_character?(killmail.esi_data)
    end

    test "returns false when no tracked characters in killmail", %{killmail: killmail} do
      # Configure the mock with an unrelated character
      # Ensure tables exist
      try do
        if :ets.info(:mock_cache) == :undefined do
          :ets.new(:mock_cache, [:set, :public, :named_table])
        end

        if :ets.info(:mock_deduplication) == :undefined do
          :ets.new(:mock_deduplication, [:set, :public, :named_table])
        end
      catch
        _, _ -> :ok
      end

      WandererNotifier.MockCache.configure([], [
        %{character_id: "9999999", name: "Unrelated Character"}
      ])

      # Test with the full ESI data
      assert Kill.has_tracked_character?(killmail.esi_data) == false
    end
  end
end
