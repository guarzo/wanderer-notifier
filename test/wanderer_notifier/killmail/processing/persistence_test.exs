defmodule WandererNotifier.Killmail.Processing.PersistenceTest do
  use ExUnit.Case, async: false
  import Mox

  alias WandererNotifier.Killmail.Core.Data
  alias WandererNotifier.Killmail.Processing.Persistence
  alias WandererNotifier.MockRepository

  # Test data
  @killmail_id 12345
  @character_id 98765
  @solar_system_id 30_000_142
  @attacker_id 54321
  @victim_id 87654

  @test_killmail %Data{
    killmail_id: @killmail_id,
    solar_system_id: @solar_system_id,
    solar_system_name: "Jita",
    kill_time: DateTime.utc_now(),
    raw_zkb_data: %{
      "totalValue" => 1_000_000.0
    },
    victim_id: @victim_id,
    victim_name: "Test Victim",
    attackers: [
      %{"character_id" => @attacker_id, "character_name" => "Test Attacker"}
    ]
  }

  setup :verify_on_exit!

  setup do
    # Set the repository module to be used by Persistence
    Application.put_env(:wanderer_notifier, :repository, MockRepository)
    Application.put_env(:wanderer_notifier, :environment, :test)

    # Add default stubs for common functions
    Mox.stub(MockRepository, :check_killmail_exists_in_database, fn _, _, _ -> false end)
    Mox.stub(MockRepository, :check_killmail_exists_in_database, fn _ -> false end)
    Mox.stub(MockRepository, :get_killmails_for_character, fn _ -> {:ok, []} end)
    Mox.stub(MockRepository, :get_killmails_for_system, fn _ -> {:ok, []} end)
    Mox.stub(MockRepository, :query, fn _ -> [] end)

    :ok
  end

  # We'll only test two critical functions to demonstrate the approach

  describe "exists?/3" do
    test "returns boolean for existence check" do
      # Set up the mock expectation for check_killmail_exists_in_database/3
      expect(MockRepository, :check_killmail_exists_in_database, fn k_id, c_id, role ->
        assert k_id == @killmail_id
        assert c_id == @character_id
        assert role == :victim
        true
      end)

      # Call the function to test
      result = Persistence.exists?(@killmail_id, @character_id, :victim)

      # The function transforms the check result to {:ok, boolean}
      assert result == {:ok, true}
    end
  end

  describe "get_killmails_for_character/1" do
    test "retrieves killmails for a character" do
      # Define simple mock data for the expected return format
      mock_result = [%{killmail_id: @killmail_id}]

      # Set up mock expectation
      expect(MockRepository, :get_killmails_for_character, fn char_id ->
        assert char_id == @character_id
        {:ok, mock_result}
      end)

      # Call the function to test
      result = Persistence.get_killmails_for_character(@character_id)

      # Assert we get the expected result through
      assert result == {:ok, mock_result}
    end
  end
end

# Create a stub module to handle default behaviors
defmodule WandererNotifier.MockRepositoryStub do
  # Add minimal stubs needed for tests
  def check_killmail_exists_in_database(_), do: false
  def check_killmail_exists_in_database(_, _, _), do: false
  def get_killmails_for_character(_), do: {:ok, []}
  def get_killmails_for_system(_), do: {:ok, []}
  def query(_), do: []
end
