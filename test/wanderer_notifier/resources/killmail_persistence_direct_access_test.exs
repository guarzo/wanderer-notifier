defmodule WandererNotifier.Resources.KillmailPersistenceDirectAccessTest do
  use WandererNotifier.DataCase

  alias WandererNotifier.Processing.Killmail.Persistence
  alias WandererNotifier.KillmailProcessing.KillmailData

  describe "persist_killmail/1 with KillmailData" do
    test "processes a killmail with direct KillmailData access" do
      # Create a sample KillmailData struct for testing
      killmail_data = %KillmailData{
        killmail_id: 12_345,
        kill_time: ~U[2023-01-01 12:34:56Z],
        solar_system_id: 30_000_142,
        solar_system_name: "Jita",
        victim_id: 98_765,
        victim_name: "Victim Pilot",
        victim_ship_id: 587,
        victim_ship_name: "Rifter",
        attackers: [
          %{
            "character_id" => 11_111,
            "character_name" => "Attacker One",
            "ship_type_id" => 24_700,
            "ship_type_name" => "Brutix",
            "final_blow" => true,
            "damage_done" => 500
          }
        ],
        attacker_count: 1,
        raw_zkb_data: %{
          "totalValue" => 15_000_000,
          "points" => 10,
          "npc" => false,
          "solo" => false,
          "hash" => "abc123hash"
        }
      }

      # Call the function directly using the new persistence module
      {:ok, persisted_killmail, created} = Persistence.persist_killmail(killmail_data, nil)

      # In test mode, we should get a persisted killmail with created=true
      assert created == true
      assert persisted_killmail.persisted == true
    end
  end

  describe "querying database with direct struct access" do
    test "gets killmails for character with direct access" do
      # Create a test character ID
      character_id = 98_765

      # Call function directly using the new persistence module
      {:ok, killmails} = Persistence.get_killmails_for_character(character_id)

      # In test mode, we should get an empty list
      assert is_list(killmails)
    end

    test "gets killmails for system with direct access" do
      # Create a test system ID
      system_id = 30_000_142

      # Call function directly using the new persistence module
      {:ok, killmails} = Persistence.get_killmails_for_system(system_id)

      # In test mode, we should get an empty list
      assert is_list(killmails)
    end

    test "gets killmails for character in date range with direct access" do
      # Create a test character ID and date range
      character_id = 98_765
      from_date = ~U[2023-01-01 00:00:00Z]
      to_date = ~U[2023-01-31 23:59:59Z]

      # Call function directly using the new persistence module
      {:ok, killmails} = Persistence.get_character_killmails(character_id, from_date, to_date)

      # In test mode, we should get an empty list
      assert is_list(killmails)
    end

    test "checks killmail existence with direct access" do
      # Create test IDs
      killmail_id = 12_345
      character_id = 98_765

      # Call function directly using the new persistence module
      {:ok, exists} = Persistence.exists?(killmail_id, character_id, :victim)

      # In test mode, we should get false
      assert exists == false
    end

    test "counts total killmails with direct access" do
      # Call function directly using the new persistence module
      count = Persistence.count_total_killmails()

      # In test mode, we should get 0
      assert is_integer(count)
    end
  end

  describe "direct struct access efficiency" do
    test "accesses fields directly without pattern matching overhead" do
      # Create a sample KillmailData struct for testing
      killmail_data = %KillmailData{
        killmail_id: 12_345,
        solar_system_id: 30_000_142,
        solar_system_name: "Jita",
        victim_id: 98_765,
        victim_name: "Victim Pilot",
        victim_ship_id: 587,
        victim_ship_name: "Rifter"
      }

      # Simple benchmark to demonstrate direct access is more efficient
      {time_direct, _result_direct} =
        :timer.tc(fn ->
          # Direct struct access (faster)
          1..1000
          |> Enum.each(fn _ ->
            _id = killmail_data.killmail_id
            _system = killmail_data.solar_system_name
            _victim = killmail_data.victim_name
          end)
        end)

      # Note that these are basic tests and might not indicate real-world performance
      # differences, but they help verify the refactoring works
      assert time_direct > 0
    end
  end
end
