defmodule WandererNotifier.Killmail.Processing.EnrichmentTest do
  use ExUnit.Case, async: false

  alias WandererNotifier.Killmail.Core.Data, as: KillmailData
  alias WandererNotifier.Killmail.Processing.Enrichment
  alias WandererNotifier.Api.Map.Systems

  # Sample test data
  @zkb_data %{
    "killmail_id" => 12345,
    "zkb" => %{
      "hash" => "abc123",
      "totalValue" => 1_000_000.0,
      "points" => 10,
      "npc" => false,
      "solo" => true
    }
  }

  @esi_data %{
    "killmail_id" => 12345,
    "killmail_time" => "2023-01-01T12:00:00Z",
    "solar_system_id" => 30_000_142,
    "victim" => %{
      "character_id" => 9876,
      "ship_type_id" => 587,
      "corporation_id" => 123_456
    },
    "attackers" => [
      %{
        "character_id" => 1234,
        "ship_type_id" => 34562,
        "final_blow" => true
      },
      %{
        "character_id" => 5678,
        "ship_type_id" => 33824,
        "final_blow" => false
      }
    ]
  }

  # Create mock modules with direct implementations
  defmodule MockESIService do
    def get_character_info(character_id) do
      {:ok, %{"name" => "Test Character #{character_id}"}}
    end

    def get_corporation_info(corporation_id) do
      {:ok, %{"name" => "Test Corporation #{corporation_id}"}}
    end

    def get_type_info(type_id) do
      {:ok, %{"name" => "Test Ship #{type_id}"}}
    end
  end

  defmodule MockKillDeterminer do
    def should_notify?(_killmail) do
      {:ok, %{should_notify: true, reason: "Test notification"}}
    end
  end

  # Additional mock modules for specific test cases
  defmodule MockNotifyTrue do
    def should_notify?(_killmail) do
      {:ok, %{should_notify: true, reason: "Test notification"}}
    end
  end

  defmodule MockNotifyFalse do
    def should_notify?(_killmail) do
      {:ok, %{should_notify: false, reason: "No notification needed"}}
    end
  end

  defmodule MockNotifyError do
    def should_notify?(_killmail) do
      {:error, "Determination failed"}
    end
  end

  setup do
    # Backup original configuration
    original_systems_module = Application.get_env(:wanderer_notifier, :map_systems_module)
    original_esi_service = Application.get_env(:wanderer_notifier, :esi_service_module)
    original_kill_determiner = Application.get_env(:wanderer_notifier, :kill_determiner_module)

    # Replace with our mocks - using fully qualified module names
    Application.put_env(:wanderer_notifier, :map_systems_module, Systems)
    Application.put_env(:wanderer_notifier, :esi_service_module, __MODULE__.MockESIService)

    Application.put_env(
      :wanderer_notifier,
      :kill_determiner_module,
      __MODULE__.MockKillDeterminer
    )

    # Restore the original modules when tests are done
    on_exit(fn ->
      # Restore map systems module
      if original_systems_module do
        Application.put_env(:wanderer_notifier, :map_systems_module, original_systems_module)
      else
        Application.delete_env(:wanderer_notifier, :map_systems_module)
      end

      # Restore ESI service module
      if original_esi_service do
        Application.put_env(:wanderer_notifier, :esi_service_module, original_esi_service)
      else
        Application.delete_env(:wanderer_notifier, :esi_service_module)
      end

      # Restore kill determiner module
      if original_kill_determiner do
        Application.put_env(:wanderer_notifier, :kill_determiner_module, original_kill_determiner)
      else
        Application.delete_env(:wanderer_notifier, :kill_determiner_module)
      end
    end)

    :ok
  end

  describe "enrich/1" do
    test "successfully enriches a valid killmail" do
      # Create a KillmailData struct for testing
      {:ok, killmail_data} = KillmailData.from_zkb_and_esi(@zkb_data, @esi_data)

      # Call the enrichment function
      {:ok, enriched} = Enrichment.enrich(killmail_data)

      # Verify basic enrichment was done
      assert enriched.killmail_id == 12345
      assert enriched.solar_system_name == "Jita"
      assert enriched.region_name == "The Forge"
      assert enriched.victim_name == "Test Character 9876"
      assert enriched.final_blow_attacker_name == "Test Character 1234"
      assert enriched.attacker_count == 2
      assert enriched.total_value == 1_000_000.0
    end

    test "returns error for invalid input" do
      # Test with non-KillmailData input
      assert {:error, :invalid_data_type} = Enrichment.enrich("not a killmail")
      assert {:error, :invalid_data_type} = Enrichment.enrich(nil)
      assert {:error, :invalid_data_type} = Enrichment.enrich(%{})
    end

    test "gracefully handles missing system ID" do
      # Create a KillmailData struct without system ID
      esi_data = Map.delete(@esi_data, "solar_system_id")
      {:ok, killmail_data} = KillmailData.from_zkb_and_esi(@zkb_data, esi_data)

      # Should still work, just with default system name
      {:ok, enriched} = Enrichment.enrich(killmail_data)

      assert enriched.solar_system_id == nil
      # This should remain nil
      assert enriched.solar_system_name == nil
    end

    test "handles failed API calls gracefully" do
      # Override the mock to simulate API failure for system info
      defmodule FailingSystems do
        def get_system_info(_system_id), do: {:error, :api_error}
      end

      # Temporarily override the module
      Application.put_env(:wanderer_notifier, :map_systems_module, __MODULE__.FailingSystems)

      # Create a KillmailData struct for testing
      {:ok, killmail_data} = KillmailData.from_zkb_and_esi(@zkb_data, @esi_data)

      # Should still work, just with default system name
      {:ok, enriched} = Enrichment.enrich(killmail_data)

      # System name should remain as is
      assert enriched.solar_system_id == 30_000_142
      # Will remain nil as API failed
      assert enriched.solar_system_name == nil

      # Reset to our normal system module
      Application.put_env(:wanderer_notifier, :map_systems_module, Systems)
    end
  end

  describe "process_and_notify/1" do
    test "returns enriched data when notification is needed" do
      # Override the kill determiner for this test
      Application.put_env(:wanderer_notifier, :kill_determiner_module, __MODULE__.MockNotifyTrue)

      # Create a KillmailData struct for testing
      {:ok, killmail_data} = KillmailData.from_zkb_and_esi(@zkb_data, @esi_data)

      # Process with notification
      {:ok, enriched} = Enrichment.process_and_notify(killmail_data)

      # Verify it's the enriched data
      assert enriched.killmail_id == 12345
      assert enriched.solar_system_name == "Jita"
    end

    test "returns :skipped when notification is not needed" do
      # Override the kill determiner for this test
      Application.put_env(:wanderer_notifier, :kill_determiner_module, __MODULE__.MockNotifyFalse)

      # Create a KillmailData struct for testing
      {:ok, killmail_data} = KillmailData.from_zkb_and_esi(@zkb_data, @esi_data)

      # Process without notification
      assert {:ok, :skipped} = Enrichment.process_and_notify(killmail_data)
    end

    test "returns error for invalid input" do
      # Test with non-KillmailData input
      assert {:error, :invalid_data_type} = Enrichment.process_and_notify("not a killmail")
    end

    test "handles notification determination errors" do
      # Override the kill determiner for this test
      Application.put_env(:wanderer_notifier, :kill_determiner_module, __MODULE__.MockNotifyError)

      # Create a KillmailData struct for testing
      {:ok, killmail_data} = KillmailData.from_zkb_and_esi(@zkb_data, @esi_data)

      # Process with notification determination error
      assert {:error, "Determination failed"} = Enrichment.process_and_notify(killmail_data)
    end
  end
end
