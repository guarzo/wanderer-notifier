defmodule WandererNotifier.KillmailProcessing.KillmailDataTest do
  use ExUnit.Case

  alias WandererNotifier.KillmailProcessing.KillmailData
  alias WandererNotifier.Resources.Killmail, as: KillmailResource

  describe "from_zkb_and_esi/2" do
    test "creates KillmailData from zkb and esi data" do
      # Setup test data
      zkb_data = %{
        "killmail_id" => 12345,
        "zkb" => %{
          "hash" => "abc123",
          "totalValue" => 1_000_000,
          "points" => 10
        }
      }

      esi_data = %{
        "solar_system_id" => 30_000_142,
        "solar_system_name" => "Jita",
        "killmail_time" => "2023-01-01T12:00:00Z",
        "victim" => %{
          "character_id" => 123_456,
          "character_name" => "Test Victim"
        },
        "attackers" => [
          %{
            "character_id" => 789_012,
            "character_name" => "Test Attacker"
          }
        ]
      }

      # Create KillmailData
      killmail_data = KillmailData.from_zkb_and_esi(zkb_data, esi_data)

      # Verify it has the correct structure
      assert %KillmailData{} = killmail_data

      # Verify it extracted the correct data
      assert killmail_data.killmail_id == 12345
      assert killmail_data.zkb_data == zkb_data
      assert killmail_data.esi_data == esi_data
      assert killmail_data.solar_system_id == 30_000_142
      assert killmail_data.solar_system_name == "Jita"

      assert killmail_data.victim == %{
               "character_id" => 123_456,
               "character_name" => "Test Victim"
             }

      assert killmail_data.attackers == [
               %{
                 "character_id" => 789_012,
                 "character_name" => "Test Attacker"
               }
             ]

      refute killmail_data.persisted
    end

    test "handles atom keys in zkb_data" do
      zkb_data = %{
        killmail_id: 12345
      }

      esi_data = %{
        "solar_system_id" => 30_000_142
      }

      killmail_data = KillmailData.from_zkb_and_esi(zkb_data, esi_data)

      assert killmail_data.killmail_id == 12345
    end

    test "handles missing/nil values gracefully" do
      zkb_data = %{}
      esi_data = %{}

      killmail_data = KillmailData.from_zkb_and_esi(zkb_data, esi_data)

      assert %KillmailData{} = killmail_data
      assert killmail_data.killmail_id == nil
      assert killmail_data.solar_system_id == nil
      assert killmail_data.solar_system_name == nil
      assert killmail_data.victim == nil
      assert killmail_data.attackers == nil
    end
  end

  describe "from_resource/1" do
    test "creates KillmailData from a resource" do
      # Create a mock Resource (we're not actually interacting with the database)
      resource = %KillmailResource{
        killmail_id: 12345,
        solar_system_id: 30_000_142,
        solar_system_name: "Jita",
        kill_time: ~U[2023-01-01 12:00:00Z],
        full_victim_data: %{"character_id" => 123_456},
        full_attacker_data: [%{"character_id" => 789_012}]
      }

      # Create KillmailData from resource
      killmail_data = KillmailData.from_resource(resource)

      # Verify it has the correct structure
      assert %KillmailData{} = killmail_data

      # Verify it extracted the correct data
      assert killmail_data.killmail_id == 12345
      assert killmail_data.solar_system_id == 30_000_142
      assert killmail_data.solar_system_name == "Jita"
      assert killmail_data.kill_time == ~U[2023-01-01 12:00:00Z]
      assert killmail_data.victim == %{"character_id" => 123_456}
      assert killmail_data.attackers == [%{"character_id" => 789_012}]
      assert killmail_data.persisted
    end
  end

  describe "extract_system_id/1" do
    test "extracts integer system_id" do
      esi_data = %{"solar_system_id" => 30_000_142}
      result = invoke_private_function(:extract_system_id, [esi_data])
      assert result == 30_000_142
    end

    test "extracts and converts string system_id" do
      esi_data = %{"solar_system_id" => "30000142"}
      result = invoke_private_function(:extract_system_id, [esi_data])
      assert result == 30_000_142
    end

    test "returns nil for missing system_id" do
      esi_data = %{}
      result = invoke_private_function(:extract_system_id, [esi_data])
      assert result == nil
    end
  end

  describe "extract_kill_time/1" do
    test "extracts DateTime kill_time" do
      datetime = DateTime.utc_now()
      esi_data = %{"killmail_time" => datetime}
      result = invoke_private_function(:extract_kill_time, [esi_data])
      assert result == datetime
    end

    test "extracts and converts string kill_time" do
      esi_data = %{"killmail_time" => "2023-01-01T12:00:00Z"}
      result = invoke_private_function(:extract_kill_time, [esi_data])
      assert %DateTime{} = result
      assert DateTime.to_iso8601(result) == "2023-01-01T12:00:00Z"
    end

    test "returns current time for missing kill_time" do
      esi_data = %{}
      result = invoke_private_function(:extract_kill_time, [esi_data])
      assert %DateTime{} = result
    end
  end

  # Helper to invoke private functions for testing
  defp invoke_private_function(function_name, args) do
    apply(KillmailData, function_name, args)
  rescue
    # For truly private functions, use :erlang.apply/3 to bypass access restriction
    _ ->
      :erlang.apply(KillmailData, function_name, args)
  end
end
