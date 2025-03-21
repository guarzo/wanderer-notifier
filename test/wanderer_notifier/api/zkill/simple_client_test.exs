defmodule WandererNotifier.Api.ZKill.SimpleClientTest do
  use ExUnit.Case
  import Mox

  alias WandererNotifier.Api.ZKill.Client
  alias WandererNotifier.MockHTTPClient

  setup do
    # Use mock HTTP client for tests
    Application.put_env(:wanderer_notifier, :http_client, WandererNotifier.MockHTTPClient)
    :ok
  end

  describe "get_single_killmail/1" do
    test "successfully retrieves killmail data" do
      kill_id = "12345"

      mock_response = %{
        "killID" => kill_id,
        "hash" => "abc123"
      }

      # Set up the mock
      WandererNotifier.MockHTTPClient
      |> expect(:get, fn url, _headers, _opts ->
        assert String.contains?(url, kill_id)
        {:ok, %{status_code: 200, body: Jason.encode!(mock_response)}}
      end)

      # Call the function
      {:ok, result} = Client.get_single_killmail(kill_id)

      # Verify the result
      assert result["killID"] == kill_id
      assert result["hash"] == "abc123"
    end
  end
end
