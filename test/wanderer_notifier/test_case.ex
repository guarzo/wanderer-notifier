defmodule WandererNotifier.TestCase do
  @moduledoc """
  Base test case for WandererNotifier tests.

  Provides common setup and helpers for tests.
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      use ExUnit.Case
      import Mox

      # Import helpers
      import WandererNotifier.TestCase

      # Common test setup
      setup :verify_on_exit!
      setup :set_mocks
    end
  end

  # Set up common test mocks
  def set_mocks(_context) do
    # Ensure application is set to test environment
    Application.put_env(:wanderer_notifier, :env, :test)

    # Set up Discord channel ID and bot token for testing
    Application.put_env(:wanderer_notifier, :discord_channel_id, "test_channel_id")
    Application.put_env(:wanderer_notifier, :discord_bot_token, "test_bot_token")

    # Set up map API configuration for testing
    Application.put_env(:wanderer_notifier, :map_url, "https://test-map.example.com")
    Application.put_env(:wanderer_notifier, :map_name, "test-map")
    Application.put_env(:wanderer_notifier, :map_token, "test-token")

    # Return the context
    %{}
  end

  # Helper to create sample killmail data
  def sample_killmail do
    %{
      "killmail_id" => "12345",
      "zkb" => %{
        "locationID" => 12345,
        "hash" => "abc123",
        "totalValue" => 1_000_000.0,
        "points" => 10
      },
      "victim" => %{
        "character_id" => "67890",
        "character_name" => "Test Victim",
        "corporation_id" => "98765",
        "corporation_name" => "Test Corp",
        "ship_type_id" => "4321",
        "ship_type_name" => "Test Ship"
      },
      "attackers" => [
        %{
          "character_id" => "11111",
          "character_name" => "Test Attacker",
          "corporation_id" => "22222",
          "corporation_name" => "Attacker Corp",
          "final_blow" => true,
          "ship_type_id" => "33333",
          "ship_type_name" => "Attacker Ship"
        }
      ],
      "esi_data" => %{
        "solar_system_id" => 30_000_142,
        "solar_system_name" => "Jita"
      }
    }
  end

  # Helper to create sample system data
  def sample_system do
    %{
      "id" => "j123456",
      "name" => "J123456",
      "class" => "C5",
      "effect" => "Pulsar",
      "statics" => ["N062", "E545"],
      "added_at" => "2023-01-01T12:00:00Z",
      "tracked" => true
    }
  end

  # Helper to create sample character data
  def sample_character do
    %{
      "character" => %{
        "name" => "Test Character",
        "alliance_id" => 12345,
        "alliance_ticker" => "TEST",
        "corporation_id" => 67890,
        "corporation_ticker" => "TSTC",
        "eve_id" => "123456789"
      },
      "tracked" => true
    }
  end
end
