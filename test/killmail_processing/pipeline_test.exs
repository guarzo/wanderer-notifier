defmodule WandererNotifier.KillmailProcessing.PipelineTest do
  use ExUnit.Case, async: true

  alias WandererNotifier.KillmailProcessing.KillmailData

  # Mock module for ESI Service
  defmodule MockESIService do
    def get_killmail(_kill_id, _hash) do
      {:ok,
       %{
         "solar_system_id" => 30_000_142,
         "solar_system_name" => "Jita",
         "killmail_time" => "2023-01-01T12:00:00Z",
         "victim" => %{
           "character_id" => 123_456,
           "character_name" => "Test Victim",
           "ship_type_id" => 34_562,
           "ship_type_name" => "Test Ship"
         },
         "attackers" => [
           %{
             "character_id" => 789_012,
             "character_name" => "Test Attacker",
             "ship_type_id" => 34_563,
             "ship_type_name" => "Attack Ship"
           }
         ]
       }}
    end
  end

  describe "KillmailData integration" do
    test "pipeline works with KillmailData structs" do
      # Simple zkb data
      zkb_data = %{
        "killmail_id" => 12_345,
        "zkb" => %{
          "hash" => "abc123",
          "totalValue" => 1_000_000,
          "points" => 10
        }
      }

      # Simple esi data
      esi_data = %{
        "solar_system_id" => 30_000_142,
        "solar_system_name" => "Jita",
        "victim" => %{"character_id" => 678},
        "attackers" => [%{"character_id" => 456}]
      }

      # Create a KillmailData struct directly
      killmail_data = KillmailData.from_zkb_and_esi(zkb_data, esi_data)

      # Verify it's a KillmailData struct
      assert %KillmailData{} = killmail_data
      assert killmail_data.killmail_id == 12_345
      assert killmail_data.solar_system_name == "Jita"
    end
  end
end
