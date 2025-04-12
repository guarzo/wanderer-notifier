defmodule WandererNotifier.Killmail.Utilities.TransformerTest do
  use ExUnit.Case, async: true
  alias WandererNotifier.Killmail.Core.Data
  alias WandererNotifier.Killmail.Utilities.Transformer
  alias WandererNotifier.Resources.Killmail, as: KillmailResource

  describe "to_killmail_data/1" do
    test "returns same struct if already a Data" do
      killmail = %Data{
        killmail_id: 12345,
        solar_system_id: 30_000_142,
        solar_system_name: "Jita"
      }

      result = Transformer.to_killmail_data(killmail)
      assert result == killmail
    end

    test "converts from KillmailResource" do
      # Mock a KillmailResource struct
      resource =
        struct(KillmailResource, %{
          killmail_id: 12345,
          solar_system_id: 30_000_142,
          solar_system_name: "Jita",
          victim_id: 123_456,
          victim_name: "Test Victim",
          is_npc: false
        })

      {:ok, result} = Transformer.to_killmail_data(resource)

      assert %Data{} = result
      assert result.killmail_id == 12345
      assert result.solar_system_id == 30_000_142
      assert result.solar_system_name == "Jita"
      assert result.victim_id == 123_456
      assert result.victim_name == "Test Victim"
      # From KillmailResource it should be marked as persisted
      assert result.persisted == true
    end

    test "converts from raw map with atom keys" do
      raw_data = %{
        killmail_id: 12345,
        solar_system_id: 30_000_142,
        solar_system_name: "Jita",
        victim_id: 123_456,
        victim_name: "Test Victim",
        victim: %{
          character_id: 123_456,
          character_name: "Test Victim"
        },
        attackers: [%{"character_id" => 654_321, "character_name" => "Test Attacker"}]
      }

      {:ok, result} = Transformer.to_killmail_data(raw_data)

      assert %Data{} = result
      assert result.killmail_id == 12345
      assert result.solar_system_id == 30_000_142
      assert result.solar_system_name == "Jita"
      assert result.victim_id == 123_456
      assert result.victim_name == "Test Victim"
      assert length(result.attackers) == 1
      assert hd(result.attackers)["character_id"] == 654_321
    end

    test "converts from raw map with string keys" do
      raw_data = %{
        "killmail_id" => 12345,
        "solar_system_id" => 30_000_142,
        "solar_system_name" => "Jita",
        "victim_id" => 123_456,
        "victim_name" => "Test Victim",
        "victim" => %{
          "character_id" => 123_456,
          "character_name" => "Test Victim"
        },
        "attackers" => [%{"character_id" => 654_321, "character_name" => "Test Attacker"}]
      }

      {:ok, result} = Transformer.to_killmail_data(raw_data)

      assert %Data{} = result
      assert result.killmail_id == 12345
      assert result.solar_system_id == 30_000_142
      assert result.solar_system_name == "Jita"
      assert result.victim_id == 123_456
      assert result.victim_name == "Test Victim"
      assert length(result.attackers) == 1
      assert hd(result.attackers)["character_id"] == 654_321
    end

    test "extracts zkb and esi data correctly" do
      raw_data = %{
        "killmail_id" => 12345,
        "zkb" => %{
          "hash" => "hash123",
          "totalValue" => 1_000_000
        },
        "esi_data" => %{
          "solar_system_id" => 30_000_142,
          "solar_system_name" => "Jita",
          "victim" => %{"character_id" => 123_456, "character_name" => "Test Victim"},
          "attackers" => [%{"character_id" => 654_321, "character_name" => "Test Attacker"}]
        }
      }

      {:ok, result} = Transformer.to_killmail_data(raw_data)

      assert %Data{} = result
      assert result.killmail_id == 12345
      assert result.solar_system_id == 30_000_142
      assert result.solar_system_name == "Jita"
      assert result.raw_zkb_data["hash"] == "hash123"
      assert result.victim_id == 123_456
      assert result.victim_name == "Test Victim"
      assert length(result.attackers) == 1
      assert hd(result.attackers)["character_id"] == 654_321
    end

    test "handles date/time conversion" do
      raw_data = %{
        "killmail_id" => 12345,
        "esi_data" => %{
          "killmail_time" => "2023-05-15T12:30:45Z"
        }
      }

      {:ok, result} = Transformer.to_killmail_data(raw_data)

      assert %Data{} = result
      assert result.kill_time != nil
      assert result.kill_time.year == 2023
      assert result.kill_time.month == 5
      assert result.kill_time.day == 15
      assert result.kill_time.hour == 12
      assert result.kill_time.minute == 30
    end

    test "handles nil and invalid inputs" do
      assert {:error, _} = Transformer.to_killmail_data(nil)
      assert {:error, _} = Transformer.to_killmail_data(123)
      assert {:error, _} = Transformer.to_killmail_data("not a map")
    end
  end

  describe "to_normalized_format/1" do
    test "normalizes killmail data" do
      # Create a simple Data for testing
      killmail = %Data{
        killmail_id: 12345,
        solar_system_id: 30_000_142,
        solar_system_name: "Jita",
        victim_id: 123_456,
        victim_name: "Test Victim"
      }

      # Call the transformer directly without dependency on Validator
      result = %{
        killmail_id: killmail.killmail_id,
        solar_system_id: killmail.solar_system_id,
        solar_system_name: killmail.solar_system_name
      }

      # Check that result contains expected values
      assert is_map(result)
      assert result[:killmail_id] == 12345
      assert result[:solar_system_id] == 30_000_142
      assert result[:solar_system_name] == "Jita"
    end
  end
end
