defmodule WandererNotifier.Killmail.Queries.KillmailQueriesTest do
  use ExUnit.Case, async: false
  import Mox

  alias WandererNotifier.Killmail.Queries.KillmailQueries
  alias WandererNotifier.Resources.Killmail, as: KillmailResource
  alias WandererNotifier.Resources.KillmailCharacterInvolvement
  alias WandererNotifier.Resources.MockApi

  # Make sure mocks are verified when the test exits
  setup :verify_on_exit!

  describe "exists?/1" do
    test "returns true when killmail exists" do
      # Set up mock expectations
      MockApi
      |> expect(:read, fn _query -> {:ok, [%{id: "some-uuid"}]} end)

      assert KillmailQueries.exists?(12_345) == true
    end

    test "returns false when killmail doesn't exist" do
      # Set up mock expectations
      MockApi
      |> expect(:read, fn _query -> {:ok, []} end)

      assert KillmailQueries.exists?(12_345) == false
    end

    test "returns false on API error" do
      # Set up mock expectations
      MockApi
      |> expect(:read, fn _query -> {:error, "some error"} end)

      assert KillmailQueries.exists?(12_345) == false
    end
  end

  describe "get/1" do
    test "returns killmail when found" do
      # Mock a killmail resource
      killmail = %KillmailResource{killmail_id: 12_345}

      # Set up mock expectations
      MockApi
      |> expect(:read, fn _query -> {:ok, [killmail]} end)

      assert KillmailQueries.get(12_345) == {:ok, killmail}
    end

    test "returns error when not found" do
      # Set up mock expectations
      MockApi
      |> expect(:read, fn _query -> {:ok, []} end)

      assert KillmailQueries.get(12_345) == {:error, :not_found}
    end
  end

  describe "get_involvements/1" do
    test "returns involvements when found" do
      # Mock for exists? call
      MockApi
      |> expect(:read, fn _query -> {:ok, [%{id: "some-uuid"}]} end)

      # Mock some involvements
      involvements = [
        %KillmailCharacterInvolvement{character_id: 123},
        %KillmailCharacterInvolvement{character_id: 456}
      ]

      # Mock for involvements query
      MockApi
      |> expect(:read, fn _query -> {:ok, involvements} end)

      assert KillmailQueries.get_involvements(12_345) == {:ok, involvements}
    end

    test "returns error when killmail not found" do
      # Mock exists? to return false
      MockApi
      |> expect(:read, fn _query -> {:ok, []} end)

      assert KillmailQueries.get_involvements(12_345) == {:error, :not_found}
    end
  end

  describe "find_by_character/4" do
    test "returns killmails for character" do
      # Mock killmail resource
      killmail = %KillmailResource{killmail_id: 12_345}

      # Mock involvements with loaded killmails
      involvements = [
        %KillmailCharacterInvolvement{character_id: 123, killmail: killmail}
      ]

      # Set up mock expectations
      MockApi
      |> expect(:read, fn _query -> {:ok, involvements} end)

      start_date = DateTime.utc_now() |> DateTime.add(-86_400, :second)
      end_date = DateTime.utc_now()

      assert KillmailQueries.find_by_character(123, start_date, end_date) == {:ok, [killmail]}
    end

    test "handles API errors" do
      # Set up mock expectations
      MockApi
      |> expect(:read, fn _query -> {:error, "some error"} end)

      start_date = DateTime.utc_now() |> DateTime.add(-86_400, :second)
      end_date = DateTime.utc_now()

      assert KillmailQueries.find_by_character(123, start_date, end_date) ==
               {:error, "some error"}
    end
  end
end
