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
  @behaviour WandererNotifier.Notifications.Deduplication.Behaviour

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

# Define config modules at the root level
defmodule WandererNotifier.TestConfig.DefaultConfig do
  def get_config do
    %{
      notifications_enabled: true,
      kill_notifications_enabled: true,
      system_notifications_enabled: true,
      character_notifications_enabled: true,
      chain_kills_mode: false
    }
  end
end

defmodule WandererNotifier.TestConfig.DisabledNotificationsConfig do
  def get_config do
    %{
      notifications_enabled: false,
      kill_notifications_enabled: false,
      system_notifications_enabled: false,
      character_notifications_enabled: false,
      chain_kills_mode: false
    }
  end
end

# Now define the test module
defmodule WandererNotifier.Notifications.Determiner.KillTest do
  use ExUnit.Case, async: true
  import Mox

  alias WandererNotifier.Notifications.Determiner.Kill
  alias WandererNotifier.Map.MapSystemMock
  alias WandererNotifier.Map.MapCharacterMock
  alias WandererNotifier.Notifications.MockConfig
  alias WandererNotifier.Notifications.MockDeduplication

  # Make sure mocks are verified when the test exits
  setup :verify_on_exit!

  setup do
    # Store original application environment
    original_config = Application.get_env(:wanderer_notifier, :config_module)
    original_system = Application.get_env(:wanderer_notifier, :system_module)
    original_character = Application.get_env(:wanderer_notifier, :character_module)
    original_deduplication = Application.get_env(:wanderer_notifier, :deduplication_module)

    # Override with test mocks
    Application.put_env(
      :wanderer_notifier,
      :config_module,
      WandererNotifier.Notifications.MockConfig
    )

    Application.put_env(:wanderer_notifier, :system_module, WandererNotifier.Map.MapSystemMock)

    Application.put_env(
      :wanderer_notifier,
      :character_module,
      WandererNotifier.Map.MapCharacterMock
    )

    Application.put_env(
      :wanderer_notifier,
      :deduplication_module,
      WandererNotifier.Notifications.MockDeduplication
    )

    # Set up default stubs
    MockConfig
    |> stub(:get_config, fn ->
      %{
        notifications_enabled: true,
        kill_notifications_enabled: true,
        system_notifications_enabled: true,
        character_notifications_enabled: true
      }
    end)

    Mox.stub(MockDeduplication, :check, fn _, _ -> {:ok, :new} end)
    Mox.stub(MapSystemMock, :is_tracked?, fn _id -> false end)
    Mox.stub(MapCharacterMock, :is_tracked?, fn _id -> false end)

    on_exit(fn ->
      # Restore original environment
      Application.put_env(:wanderer_notifier, :config_module, original_config)
      Application.put_env(:wanderer_notifier, :system_module, original_system)
      Application.put_env(:wanderer_notifier, :character_module, original_character)
      Application.put_env(:wanderer_notifier, :deduplication_module, original_deduplication)
    end)

    :ok
  end

  describe "should_notify?/1" do
    test "returns true for tracked character kills" do
      kill_data = %{
        "killmail_id" => 123,
        "solar_system_id" => 30_000_142,
        "victim" => %{
          "character_id" => 123,
          "corporation_id" => 456,
          "ship_type_id" => 789
        },
        "attackers" => [],
        "zkb" => %{"hash" => "test_hash"}
      }

      Mox.expect(MapCharacterMock, :is_tracked?, fn id -> id == 123 end)

      Mox.stub(MockConfig, :get_config, fn ->
        %{
          notifications_enabled: true,
          kill_notifications_enabled: true,
          system_notifications_enabled: true,
          character_notifications_enabled: true
        }
      end)

      assert {:ok, %{should_notify: true}} = Kill.should_notify?(kill_data)
    end

    test "returns true for tracked system kills" do
      kill_data = %{
        "killmail_id" => 123,
        "solar_system_id" => 30_000_142,
        "victim" => %{
          "character_id" => 123,
          "corporation_id" => 456,
          "ship_type_id" => 789
        },
        "attackers" => [],
        "zkb" => %{"hash" => "test_hash"}
      }

      Mox.expect(MapSystemMock, :is_tracked?, fn id -> id == 30_000_142 end)

      Mox.stub(MockConfig, :get_config, fn ->
        %{
          notifications_enabled: true,
          kill_notifications_enabled: true,
          system_notifications_enabled: true,
          character_notifications_enabled: true
        }
      end)

      assert {:ok, %{should_notify: true}} = Kill.should_notify?(kill_data)
    end

    test "returns false for duplicate kills" do
      kill_data = %{
        "killmail_id" => 123,
        "solar_system_id" => 30_000_142,
        "victim" => %{
          "character_id" => 123,
          "corporation_id" => 456,
          "ship_type_id" => 789
        },
        "attackers" => [],
        "zkb" => %{"hash" => "test_hash"}
      }

      Mox.stub(MockDeduplication, :check, fn _, _ -> {:ok, :duplicate} end)

      assert {:ok, %{should_notify: false, reason: "Duplicate kill"}} =
               Kill.should_notify?(kill_data)
    end

    test "returns false when no tracked systems or characters" do
      kill_data = %{
        "killmail_id" => 123,
        "solar_system_id" => 30_000_142,
        "victim" => %{
          "character_id" => 123,
          "corporation_id" => 456,
          "ship_type_id" => 789
        },
        "attackers" => [],
        "zkb" => %{"hash" => "test_hash"}
      }

      Mox.stub(MapSystemMock, :is_tracked?, fn _id -> false end)
      Mox.stub(MapCharacterMock, :is_tracked?, fn _id -> false end)

      assert {:ok, %{should_notify: false, reason: "No tracked systems or characters involved"}} =
               Kill.should_notify?(kill_data)
    end

    test "returns false when notifications are disabled" do
      kill_data = %{
        "killmail_id" => 123,
        "solar_system_id" => 30_000_142,
        "victim" => %{
          "character_id" => 123,
          "corporation_id" => 456,
          "ship_type_id" => 789
        },
        "attackers" => [],
        "zkb" => %{"hash" => "test_hash"}
      }

      Mox.stub(MockConfig, :get_config, fn ->
        %{
          notifications_enabled: false,
          kill_notifications_enabled: false,
          system_notifications_enabled: false,
          character_notifications_enabled: false
        }
      end)

      assert {:ok, %{should_notify: false, reason: "Notifications disabled"}} =
               Kill.should_notify?(kill_data)
    end
  end
end
