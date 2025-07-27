defmodule WandererNotifier.Domains.Notifications.Formatters.KillmailTest do
  use ExUnit.Case, async: true
  import Mox

  alias WandererNotifier.Domains.Notifications.Formatters.Killmail, as: KillmailFormatter
  alias WandererNotifier.Domains.Killmail.Killmail

  setup :verify_on_exit!

  setup do
    # Set up ESI service mock
    Application.put_env(
      :wanderer_notifier,
      :esi_service,
      WandererNotifier.Infrastructure.Adapters.ESI.ServiceMock
    )

    :ok
  end

  describe "format_kill_notification/1" do
    test "formats basic killmail notification" do
      # Mock system cache dependencies
      Application.put_env(:wanderer_notifier, :killmail_cache_module, WandererNotifier.TestMocks)

      killmail = %Killmail{
        killmail_id: 123_456,
        zkb: %{"totalValue" => 50_000_000},
        attackers: [
          %{
            "character_id" => 95_654_321,
            "final_blow" => true,
            "ship_type_id" => 11_567
          }
        ],
        esi_data: %{
          "killmail_time" => "2024-01-01T12:00:00Z",
          "victim" => %{
            "character_id" => 95_123_456,
            "ship_type_id" => 587
          },
          "attackers" => [
            %{
              "character_id" => 95_654_321,
              "final_blow" => true,
              "ship_type_id" => 11_567
            }
          ]
        }
      }

      result = KillmailFormatter.format_kill_notification(killmail)

      assert is_map(result)
      assert result[:type] == :kill_notification
      assert Map.has_key?(result, :title)
      assert Map.has_key?(result, :description)
    end

    test "handles killmail with minimal data" do
      Application.put_env(:wanderer_notifier, :killmail_cache_module, WandererNotifier.TestMocks)

      killmail = %Killmail{
        killmail_id: 789_123,
        zkb: %{},
        attackers: [],
        esi_data: %{
          "victim" => %{},
          "attackers" => []
        }
      }

      result = KillmailFormatter.format_kill_notification(killmail)

      assert is_map(result)
      assert result[:type] == :kill_notification
      # Should not crash with minimal data
    end

    test "handles killmail with nil esi_data" do
      Application.put_env(:wanderer_notifier, :killmail_cache_module, WandererNotifier.TestMocks)

      killmail = %Killmail{
        killmail_id: 456_789,
        zkb: %{},
        attackers: [],
        esi_data: nil
      }

      result = KillmailFormatter.format_kill_notification(killmail)

      assert is_map(result)
      assert result[:type] == :kill_notification
      # Should handle nil esi_data gracefully
    end
  end

  describe "format/1" do
    test "formats killmail for notification" do
      killmail = %Killmail{
        killmail_id: 123_456,
        victim_character_name: "Test Pilot",
        victim_ship_name: "Rifter",
        value: 50_000_000,
        zkb: %{"totalValue" => 50_000_000},
        esi_data: %{
          "killmail_time" => "2024-01-01T12:00:00Z",
          "victim" => %{
            "character_id" => 95_123_456,
            "character_name" => "Test Pilot",
            "corporation_name" => "Test Corp",
            "ship_type_name" => "Rifter"
          },
          "attackers" => [
            %{
              "character_id" => 95_654_321,
              "character_name" => "Attacker Pilot",
              "corporation_name" => "Attacker Corp"
            }
          ]
        }
      }

      result = KillmailFormatter.format(killmail)

      assert is_map(result)
      assert result[:title] == "Test Pilot's Rifter destroyed"
      assert is_binary(result[:description])
      assert result[:color] == 0xD9534F
      assert is_list(result[:fields])
    end
  end
end
