defmodule WandererNotifier.Killmail.Schemas.KillmailDataTest do
  use ExUnit.Case, async: true

  alias WandererNotifier.Killmail.Schemas.{KillmailData, Victim, Attacker}

  describe "changeset/2" do
    test "creates valid changeset with required fields" do
      attrs = %{
        killmail_id: 12_345_678,
        data_source: "esi",
        victim: valid_victim_attrs(),
        attackers: [valid_attacker_attrs()]
      }

      changeset = KillmailData.changeset(%KillmailData{}, attrs)

      assert changeset.valid?
      assert get_field(changeset, :killmail_id) == 12_345_678
      assert get_field(changeset, :data_source) == "esi"
    end

    test "requires killmail_id" do
      attrs = %{
        data_source: "esi",
        victim: valid_victim_attrs(),
        attackers: [valid_attacker_attrs()]
      }

      changeset = KillmailData.changeset(%KillmailData{}, attrs)

      refute changeset.valid?
      assert {:killmail_id, {"can't be blank", [validation: :required]}} in changeset.errors
    end

    test "requires data_source" do
      attrs = %{
        killmail_id: 12_345_678,
        victim: valid_victim_attrs(),
        attackers: [valid_attacker_attrs()]
      }

      changeset = KillmailData.changeset(%KillmailData{}, attrs)

      refute changeset.valid?
      assert {:data_source, {"can't be blank", [validation: :required]}} in changeset.errors
    end

    test "validates data_source inclusion" do
      attrs = %{
        killmail_id: 12_345_678,
        data_source: "invalid_source",
        victim: valid_victim_attrs(),
        attackers: [valid_attacker_attrs()]
      }

      changeset = KillmailData.changeset(%KillmailData{}, attrs)

      refute changeset.valid?

      assert {:data_source,
              {"is invalid", [validation: :inclusion, enum: ["esi", "websocket", "zkillboard"]]}} in changeset.errors
    end

    test "requires victim" do
      attrs = %{
        killmail_id: 12_345_678,
        data_source: "esi",
        attackers: [valid_attacker_attrs()]
      }

      changeset = KillmailData.changeset(%KillmailData{}, attrs)

      refute changeset.valid?
      assert {:victim, {"can't be blank", [validation: :required]}} in changeset.errors
    end

    test "requires at least one attacker" do
      attrs = %{
        killmail_id: 12_345_678,
        data_source: "esi",
        victim: valid_victim_attrs(),
        attackers: []
      }

      changeset = KillmailData.changeset(%KillmailData{}, attrs)

      refute changeset.valid?
      assert {:attackers, {"can't be blank", [validation: :required]}} in changeset.errors
    end

    test "validates killmail_id range" do
      attrs = %{
        killmail_id: -1,
        data_source: "esi",
        victim: valid_victim_attrs(),
        attackers: [valid_attacker_attrs()]
      }

      changeset = KillmailData.changeset(%KillmailData{}, attrs)

      refute changeset.valid?

      assert Enum.any?(changeset.errors, fn {field, {msg, _}} ->
               field == :killmail_id and String.contains?(msg, "Invalid killmail ID range")
             end)
    end

    test "validates solar_system_id range" do
      attrs = %{
        killmail_id: 12_345_678,
        # Too low
        solar_system_id: 10_000_000,
        data_source: "esi",
        victim: valid_victim_attrs(),
        attackers: [valid_attacker_attrs()]
      }

      changeset = KillmailData.changeset(%KillmailData{}, attrs)

      refute changeset.valid?

      assert Enum.any?(changeset.errors, fn {field, {msg, _}} ->
               field == :solar_system_id and
                 String.contains?(msg, "Invalid EVE solar system ID range")
             end)
    end

    test "validates security_status range" do
      attrs = %{
        killmail_id: 12_345_678,
        # Too high
        security_status: 2.0,
        data_source: "esi",
        victim: valid_victim_attrs(),
        attackers: [valid_attacker_attrs()]
      }

      changeset = KillmailData.changeset(%KillmailData{}, attrs)

      refute changeset.valid?

      assert Enum.any?(changeset.errors, fn {field, {msg, _}} ->
               field == :security_status and
                 String.contains?(msg, "Security status must be between -1.0 and 1.0")
             end)
    end

    test "validates killmail_time format" do
      attrs = %{
        killmail_id: 12_345_678,
        killmail_time: "invalid-date",
        data_source: "esi",
        victim: valid_victim_attrs(),
        attackers: [valid_attacker_attrs()]
      }

      changeset = KillmailData.changeset(%KillmailData{}, attrs)

      refute changeset.valid?

      assert Enum.any?(changeset.errors, fn {field, {msg, _}} ->
               field == :killmail_time and
                 String.contains?(msg, "Invalid ISO 8601 datetime format")
             end)
    end

    test "accepts valid killmail_time format" do
      attrs = %{
        killmail_id: 12_345_678,
        killmail_time: "2023-12-01T15:30:00Z",
        data_source: "esi",
        victim: valid_victim_attrs(),
        attackers: [valid_attacker_attrs()]
      }

      changeset = KillmailData.changeset(%KillmailData{}, attrs)

      assert changeset.valid?
    end

    test "validates total_value is non-negative" do
      attrs = %{
        killmail_id: 12_345_678,
        total_value: -1000.0,
        data_source: "esi",
        victim: valid_victim_attrs(),
        attackers: [valid_attacker_attrs()]
      }

      changeset = KillmailData.changeset(%KillmailData{}, attrs)

      refute changeset.valid?

      assert Enum.any?(changeset.errors, fn {field, {msg, _}} ->
               field == :total_value and String.contains?(msg, "Total value must be non-negative")
             end)
    end

    test "sets processed_at timestamp automatically" do
      attrs = %{
        killmail_id: 12_345_678,
        data_source: "esi",
        victim: valid_victim_attrs(),
        attackers: [valid_attacker_attrs()]
      }

      changeset = KillmailData.changeset(%KillmailData{}, attrs)

      assert changeset.valid?
      assert get_field(changeset, :processed_at) != nil
    end
  end

  describe "from_esi_data/2" do
    test "creates changeset from ESI killmail data" do
      esi_data = %{
        "killmail_id" => 12_345_678,
        "killmail_time" => "2023-12-01T15:30:00Z",
        "solar_system_id" => 30_000_142,
        "victim" => %{
          "character_id" => 95_538_921,
          "character_name" => "Test Victim",
          "corporation_id" => 98_000_001,
          "corporation_name" => "Test Corp",
          "ship_type_id" => 670,
          "ship_name" => "Capsule",
          "damage_taken" => 500
        },
        "attackers" => [
          %{
            "character_id" => 95_538_922,
            "character_name" => "Test Attacker",
            "corporation_id" => 98_000_002,
            "corporation_name" => "Attacker Corp",
            "ship_type_id" => 582,
            "ship_name" => "Bantam",
            "damage_done" => 500,
            "final_blow" => true
          }
        ]
      }

      zkb_data = %{
        "hash" => "abc123hash",
        "totalValue" => 1_000_000.0,
        "points" => 1
      }

      changeset = KillmailData.from_esi_data(esi_data, zkb_data)

      assert changeset.valid?
      assert get_field(changeset, :killmail_id) == 12_345_678
      assert get_field(changeset, :data_source) == "esi"
      assert get_field(changeset, :enriched) == true
      assert get_field(changeset, :hash) == "abc123hash"

      changeset
      |> get_field(:total_value)
      |> Decimal.equal?(Decimal.new("1000000.0"))
      |> assert()
    end
  end

  describe "from_websocket_data/1" do
    test "creates changeset from WebSocket enriched data" do
      ws_data = %{
        "killmail_id" => 12_345_678,
        "killmail_time" => "2023-12-01T15:30:00Z",
        "solar_system_id" => 30_000_142,
        "solar_system_name" => "Jita",
        "total_value" => 1_000_000.0,
        "victim" => %{
          "character_id" => 95_538_921,
          "character_name" => "Test Victim",
          "damage_taken" => 500
        },
        "attackers" => [
          %{
            "character_id" => 95_538_922,
            "character_name" => "Test Attacker",
            "damage_done" => 500,
            "final_blow" => true
          }
        ]
      }

      changeset = KillmailData.from_websocket_data(ws_data)

      assert changeset.valid?
      assert get_field(changeset, :killmail_id) == 12_345_678
      assert get_field(changeset, :data_source) == "websocket"
      assert get_field(changeset, :enriched) == true
      assert get_field(changeset, :solar_system_name) == "Jita"
    end
  end

  describe "from_zkillboard_data/1" do
    test "creates changeset from zKillboard data" do
      zkb_data = %{
        "killmail_id" => 12_345_678,
        "zkb" => %{
          "hash" => "abc123hash",
          "totalValue" => 1_000_000.0,
          "points" => 1
        }
      }

      changeset = KillmailData.from_zkillboard_data(zkb_data)

      # ZKillboard data is minimal and requires enrichment, so it won't be valid
      refute changeset.valid?
      assert get_field(changeset, :killmail_id) == 12_345_678
      assert get_field(changeset, :data_source) == "zkillboard"
      assert get_field(changeset, :enriched) == false
      assert get_field(changeset, :hash) == "abc123hash"
    end
  end

  describe "validation functions" do
    test "is_solo_kill?/1 returns true for single attacker" do
      killmail = %KillmailData{
        attackers: [%Attacker{character_id: 1, damage_done: 100, final_blow: true}]
      }

      assert KillmailData.is_solo_kill?(killmail)
    end

    test "is_solo_kill?/1 returns false for multiple attackers" do
      killmail = %KillmailData{
        attackers: [
          %Attacker{character_id: 1, damage_done: 100, final_blow: true},
          %Attacker{character_id: 2, damage_done: 50, final_blow: false}
        ]
      }

      refute KillmailData.is_solo_kill?(killmail)
    end

    test "npc_kill?/1 returns true for NPC victim" do
      killmail = %KillmailData{
        victim: %Victim{character_id: nil, damage_taken: 100}
      }

      assert KillmailData.npc_kill?(killmail)
    end

    test "npc_kill?/1 returns false for player victim" do
      killmail = %KillmailData{
        victim: %Victim{character_id: 95_538_921, damage_taken: 100}
      }

      refute KillmailData.npc_kill?(killmail)
    end

    test "security_category/1 correctly categorizes security levels" do
      assert KillmailData.security_category(%KillmailData{security_status: 1.0}) == :highsec
      assert KillmailData.security_category(%KillmailData{security_status: 0.5}) == :highsec
      assert KillmailData.security_category(%KillmailData{security_status: 0.4}) == :lowsec
      assert KillmailData.security_category(%KillmailData{security_status: 0.1}) == :lowsec
      assert KillmailData.security_category(%KillmailData{security_status: 0.0}) == :nullsec
      assert KillmailData.security_category(%KillmailData{security_status: -0.5}) == :nullsec
    end

    test "security_category/1 identifies wormhole systems" do
      assert KillmailData.security_category(%KillmailData{solar_system_id: 31_000_001}) ==
               :wormhole

      assert KillmailData.security_category(%KillmailData{solar_system_id: 31_999_999}) ==
               :wormhole
    end

    test "get_final_blow_attacker/1 returns the final blow attacker" do
      final_blow_attacker = %Attacker{character_id: 1, damage_done: 100, final_blow: true}
      other_attacker = %Attacker{character_id: 2, damage_done: 50, final_blow: false}

      killmail = %KillmailData{
        attackers: [other_attacker, final_blow_attacker]
      }

      result = KillmailData.get_final_blow_attacker(killmail)
      assert result == final_blow_attacker
    end

    test "total_damage_dealt/1 sums all attacker damage" do
      killmail = %KillmailData{
        attackers: [
          %Attacker{damage_done: 100, final_blow: true},
          %Attacker{damage_done: 50, final_blow: false},
          %Attacker{damage_done: 25, final_blow: false}
        ]
      }

      assert KillmailData.total_damage_dealt(killmail) == 175
    end
  end

  # Helper functions for test data

  defp valid_victim_attrs do
    %{
      character_id: 95_538_921,
      character_name: "Test Victim",
      corporation_id: 98_000_001,
      corporation_name: "Test Corp",
      ship_type_id: 670,
      ship_name: "Capsule",
      damage_taken: 500
    }
  end

  defp valid_attacker_attrs do
    %{
      character_id: 95_538_922,
      character_name: "Test Attacker",
      corporation_id: 98_000_002,
      corporation_name: "Attacker Corp",
      ship_type_id: 582,
      ship_name: "Bantam",
      damage_done: 500,
      final_blow: true
    }
  end

  defp get_field(changeset, field) do
    Ecto.Changeset.get_field(changeset, field)
  end
end
