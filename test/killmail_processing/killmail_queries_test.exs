defmodule WandererNotifier.KillmailProcessing.KillmailQueriesTest do
  use ExUnit.Case, async: false

  alias WandererNotifier.KillmailProcessing.KillmailQueries
  alias WandererNotifier.Resources.Api
  alias WandererNotifier.Resources.Killmail, as: KillmailResource
  alias WandererNotifier.Resources.KillmailCharacterInvolvement

  # Mock module for the Api
  defmodule MockApi do
    def read(_query) do
      # Get the mocked response from the test process
      case Process.get(:mock_api_response) do
        {result, value} ->
          {result, value}
        nil ->
          {:error, :not_mocked}
      end
    end
  end

  setup do
    # Store the original Api module
    original_api = Api

    # Replace the Api module with our mock for this test
    # This approach avoids having to modify the actual code
    :code.unstick_mod(WandererNotifier.Resources.Api)
    Code.compiler_options(ignore_module_conflict: true)
    defmodule WandererNotifier.Resources.Api do
      def read(query) do
        # Delegate to the mock
        WandererNotifier.KillmailProcessing.KillmailQueriesTest.MockApi.read(query)
      end
    end
    Code.compiler_options(ignore_module_conflict: false)

    # Cleanup function to restore the original Api module after the test
    on_exit(fn ->
      :code.unstick_mod(WandererNotifier.Resources.Api)
      Code.compiler_options(ignore_module_conflict: true)
      Code.eval_string("defmodule WandererNotifier.Resources.Api, do: nil")
      Code.delete_current_time_unit_cache()
      Code.compiler_options(ignore_module_conflict: false)
    end)

    :ok
  end

  describe "exists?/1" do
    test "returns true when killmail exists" do
      # Mock the API to return a result
      Process.put(:mock_api_response, {:ok, [%{id: "some-uuid"}]})

      assert KillmailQueries.exists?(12345) == true
    end

    test "returns false when killmail doesn't exist" do
      # Mock the API to return an empty list
      Process.put(:mock_api_response, {:ok, []})

      assert KillmailQueries.exists?(12345) == false
    end

    test "returns false on API error" do
      # Mock the API to return an error
      Process.put(:mock_api_response, {:error, "some error"})

      assert KillmailQueries.exists?(12345) == false
    end
  end

  describe "get/1" do
    test "returns killmail when found" do
      # Mock a killmail resource
      killmail = %KillmailResource{killmail_id: 12345}

      # Mock the API to return the killmail
      Process.put(:mock_api_response, {:ok, [killmail]})

      assert KillmailQueries.get(12345) == {:ok, killmail}
    end

    test "returns error when not found" do
      # Mock the API to return an empty list
      Process.put(:mock_api_response, {:ok, []})

      assert KillmailQueries.get(12345) == {:error, :not_found}
    end
  end

  describe "get_involvements/1" do
    test "returns involvements when found" do
      # First mock the exists? call to return true
      Process.put(:mock_api_response, {:ok, [%{id: "some-uuid"}]})

      # Mock some involvements
      involvements = [
        %KillmailCharacterInvolvement{character_id: 123},
        %KillmailCharacterInvolvement{character_id: 456}
      ]

      # Now mock the involvements query
      Process.put(:mock_api_response, {:ok, involvements})

      assert KillmailQueries.get_involvements(12345) == {:ok, involvements}
    end

    test "returns error when killmail not found" do
      # Mock the exists? call to return false
      Process.put(:mock_api_response, {:ok, []})

      assert KillmailQueries.get_involvements(12345) == {:error, :not_found}
    end
  end

  describe "find_by_character/4" do
    test "returns killmails for character" do
      # Mock killmail resource
      killmail = %KillmailResource{killmail_id: 12345}

      # Mock involvements with loaded killmails
      involvements = [
        %KillmailCharacterInvolvement{character_id: 123, killmail: killmail}
      ]

      # Mock the API response
      Process.put(:mock_api_response, {:ok, involvements})

      start_date = DateTime.utc_now() |> DateTime.add(-86400, :second)
      end_date = DateTime.utc_now()

      assert KillmailQueries.find_by_character(123, start_date, end_date) == {:ok, [killmail]}
    end

    test "handles API errors" do
      # Mock an API error
      Process.put(:mock_api_response, {:error, "some error"})

      start_date = DateTime.utc_now() |> DateTime.add(-86400, :second)
      end_date = DateTime.utc_now()

      assert KillmailQueries.find_by_character(123, start_date, end_date) == {:error, "some error"}
    end
  end
end
