defmodule WandererNotifier.TestCase do
  @moduledoc """
  This module defines the test case to be used by tests throughout the application.
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      # Import conveniences for testing
      import ExUnit.Assertions
      import WandererNotifier.TestCase

      # Alias common test modules
      alias WandererNotifier.MockHTTPClient
      alias WandererNotifier.MockESIService

      # Import mox for mocking
      import Mox
    end
  end

  setup _tags do
    # Verify mocks on exit by default
    Mox.verify_on_exit!()

    # Setup initial state or fixtures
    :ok
  end

  @doc """
  Helper to generate sample killmail data for testing
  """
  def sample_killmail do
    %{
      "killmail_id" => "12345",
      "killmail_time" => "2024-03-01T12:00:00Z",
      "solar_system_id" => 30_000_142,
      "zkb" => %{
        "hash" => "hash123",
        "locationID" => 30_000_142,
        "totalValue" => 12_345_678.90,
        "points" => 5
      },
      "victim" => %{
        "character_id" => "404850015",
        "character_name" => "Janissik",
        "corporation_id" => 98_551_135,
        "corporation_name" => "FLYSF",
        "ship_type_id" => 12345
      },
      "attackers" => [
        %{
          "character_id" => "123456789",
          "character_name" => "Attacker",
          "corporation_id" => 98_000_000,
          "corporation_name" => "Attackers Corp",
          "ship_type_id" => 54321
        }
      ]
    }
  end

  @doc """
  Helper to generate sample character data for testing
  """
  def sample_character_data do
    %{
      "character" => %{
        "name" => "Janissik",
        "alliance_id" => nil,
        "alliance_ticker" => nil,
        "corporation_id" => 98_551_135,
        "corporation_ticker" => "FLYSF",
        "eve_id" => "404850015"
      },
      "tracked" => true
    }
  end

  @doc """
  Helper to generate sample notification data for testing
  """
  def sample_notification do
    %{
      "character_id" => "404850015",
      "character_name" => "Janissik",
      "corporation_name" => "FLYSF",
      "corporation_id" => 98_551_135,
      "message" => "Test notification message",
      "timestamp" => DateTime.utc_now() |> DateTime.to_iso8601()
    }
  end
end
