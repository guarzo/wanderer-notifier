defmodule WandererNotifier.KillmailProcessing.ExtractorTest do
  use ExUnit.Case

  alias WandererNotifier.KillmailProcessing.{Extractor, KillmailData}
  alias WandererNotifier.Resources.Killmail, as: KillmailResource

  describe "get_killmail_id/1" do
    test "extracts killmail_id from KillmailData" do
      killmail = %KillmailData{killmail_id: 12345}
      assert Extractor.get_killmail_id(killmail) == 12345
    end

    test "extracts killmail_id from plain map with atom key" do
      killmail = %{killmail_id: 12345}
      assert Extractor.get_killmail_id(killmail) == 12345
    end

    test "extracts killmail_id from plain map with string key" do
      killmail = %{"killmail_id" => 12345}
      assert Extractor.get_killmail_id(killmail) == 12345
    end

    test "returns nil for missing killmail_id" do
      killmail = %{other_field: "value"}
      assert Extractor.get_killmail_id(killmail) == nil
    end
  end

  describe "get_system_id/1" do
    test "extracts system_id from KillmailData" do
      killmail = %KillmailData{solar_system_id: 12345}
      assert Extractor.get_system_id(killmail) == 12345
    end

    test "extracts system_id from esi_data" do
      killmail = %{esi_data: %{"solar_system_id" => 12345}}
      assert Extractor.get_system_id(killmail) == 12345
    end

    test "returns nil for missing system_id" do
      killmail = %{esi_data: %{}}
      assert Extractor.get_system_id(killmail) == nil
    end
  end

  describe "get_system_name/1" do
    test "extracts system_name from KillmailData" do
      killmail = %KillmailData{solar_system_name: "Jita"}
      assert Extractor.get_system_name(killmail) == "Jita"
    end

    test "extracts system_name from esi_data" do
      killmail = %{esi_data: %{"solar_system_name" => "Jita"}}
      assert Extractor.get_system_name(killmail) == "Jita"
    end

    test "returns nil for missing system_name" do
      killmail = %{esi_data: %{}}
      assert Extractor.get_system_name(killmail) == nil
    end
  end

  describe "get_victim/1" do
    test "extracts victim from KillmailData" do
      victim_data = %{"character_id" => 123, "character_name" => "Test Victim"}
      killmail = %KillmailData{victim: victim_data}
      assert Extractor.get_victim(killmail) == victim_data
    end

    test "extracts victim from esi_data" do
      victim_data = %{"character_id" => 123, "character_name" => "Test Victim"}
      killmail = %{esi_data: %{"victim" => victim_data}}
      assert Extractor.get_victim(killmail) == victim_data
    end

    test "returns empty map for missing victim" do
      killmail = %{esi_data: %{}}
      assert Extractor.get_victim(killmail) == %{}
    end
  end

  describe "get_attackers/1" do
    test "extracts attackers from KillmailData" do
      attackers_data = [%{"character_id" => 123, "character_name" => "Test Attacker"}]
      killmail = %KillmailData{attackers: attackers_data}
      assert Extractor.get_attackers(killmail) == attackers_data
    end

    test "extracts attackers from esi_data" do
      attackers_data = [%{"character_id" => 123, "character_name" => "Test Attacker"}]
      killmail = %{esi_data: %{"attackers" => attackers_data}}
      assert Extractor.get_attackers(killmail) == attackers_data
    end

    test "returns empty list for missing attackers" do
      killmail = %{esi_data: %{}}
      assert Extractor.get_attackers(killmail) == []
    end
  end

  describe "debug_data/1" do
    test "generates debug data from KillmailData" do
      killmail = %KillmailData{
        killmail_id: 12345,
        solar_system_id: 67890,
        solar_system_name: "Test System",
        victim: %{"character_id" => 123},
        attackers: [%{"character_id" => 456}, %{"character_id" => 789}]
      }

      debug_data = Extractor.debug_data(killmail)

      assert debug_data.killmail_id == 12345
      assert debug_data.system_id == 67890
      assert debug_data.system_name == "Test System"
      assert debug_data.has_victim_data == true
      assert debug_data.has_attacker_data == true
      assert debug_data.attacker_count == 2
    end

    test "generates debug data from mixed map" do
      killmail = %{
        killmail_id: 12345,
        solar_system_id: 67890,
        solar_system_name: "Test System",
        esi_data: %{
          "victim" => %{"character_id" => 123},
          "attackers" => [%{"character_id" => 456}]
        }
      }

      debug_data = Extractor.debug_data(killmail)

      assert debug_data.killmail_id == 12345
      assert debug_data.system_id == 67890
      assert debug_data.system_name == "Test System"
      assert debug_data.has_victim_data == true
      assert debug_data.has_attacker_data == true
      assert debug_data.attacker_count == 1
    end

    test "handles missing data gracefully" do
      killmail = %{killmail_id: 12345}

      debug_data = Extractor.debug_data(killmail)

      assert debug_data.killmail_id == 12345
      assert debug_data.system_id == nil
      assert debug_data.system_name == nil
      assert debug_data.has_victim_data == false
      assert debug_data.has_attacker_data == false
      assert debug_data.attacker_count == 0
    end
  end
end
