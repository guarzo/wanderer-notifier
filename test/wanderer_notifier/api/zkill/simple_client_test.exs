defmodule WandererNotifier.Api.ZKill.SimpleClientTest do
  use ExUnit.Case

  # Define our own ApiClient module for testing
  # This completely replaces HttpClient calls in tests
  defmodule TestApiClient do
    def get(url, _headers, _opts) do
      kill_id = "12345"

      if String.contains?(url, kill_id) do
        mock_response = [
          %{
            "killmail_id" => kill_id,
            "zkb" => %{
              "hash" => "abc123"
            }
          }
        ]

        {:ok, %{status_code: 200, body: Jason.encode!(mock_response)}}
      else
        {:error, "URL not found"}
      end
    end
  end

  setup do
    # Override the HTTP client with our test implementation
    Application.put_env(:wanderer_notifier, :http_client, __MODULE__.TestApiClient)
    :ok
  end

  describe "get_single_killmail/1" do
    test "successfully retrieves killmail data" do
      kill_id = "12345"

      # Call the function (using our TestApiClient)
      {:ok, result} = WandererNotifier.Api.ZKill.Client.get_single_killmail(kill_id)

      # We'll just verify we got a successful response with some data
      assert is_list(result)

      if length(result) > 0 do
        first_kill = List.first(result)
        assert is_map(first_kill)
      end
    end
  end
end
