defmodule WandererNotifier.Api.ZKill.ClientTest do
  use WandererNotifier.TestCase
  alias WandererNotifier.Api.ZKill.Client
  alias WandererNotifier.MockHTTPClient

  # Setup for each test
  setup do
    # Use our mock HTTP client
    Application.put_env(:wanderer_notifier, :http_client, WandererNotifier.MockHTTPClient)
    :ok
  end

  describe "get_killmail/1" do
    test "successfully retrieves killmail data" do
      kill_id = "12345"

      mock_response = %{
        "killID" => kill_id,
        "hash" => "abc123",
        "victimShipID" => 33328,
        "value" => 5_000_000
      }

      # Mock the HTTP client response
      MockHTTPClient
      |> expect(:get, fn url, _headers ->
        assert String.contains?(url, kill_id)
        {:ok, %HTTPoison.Response{status_code: 200, body: Jason.encode!(mock_response)}}
      end)

      # Call the function
      {:ok, result} = Client.get_killmail(kill_id)

      # Verify the result
      assert result["killID"] == kill_id
      assert result["hash"] == "abc123"
    end

    test "handles API errors" do
      kill_id = "invalid"

      # Mock the HTTP client error response
      MockHTTPClient
      |> expect(:get, fn _url, _headers ->
        {:error, %HTTPoison.Error{reason: "not found"}}
      end)

      # Call the function
      result = Client.get_killmail(kill_id)

      # Verify we get an error
      assert {:error, _} = result
    end

    test "handles non-200 responses" do
      kill_id = "12345"

      # Mock the HTTP client error response
      MockHTTPClient
      |> expect(:get, fn _url, _headers ->
        {:ok, %HTTPoison.Response{status_code: 404, body: "Not Found"}}
      end)

      # Call the function
      result = Client.get_killmail(kill_id)

      # Verify we get an error
      assert {:error, _} = result
    end
  end

  describe "get_character_kills/1" do
    test "successfully retrieves character kill data" do
      character_id = "67890"

      mock_response = [
        %{
          "killmail_id" => "12345",
          "zkb" => %{
            "hash" => "abc123"
          }
        }
      ]

      # Mock the HTTP client response
      MockHTTPClient
      |> expect(:get, fn url, _headers ->
        assert String.contains?(url, character_id)
        {:ok, %HTTPoison.Response{status_code: 200, body: Jason.encode!(mock_response)}}
      end)

      # Call the function
      {:ok, result} = Client.get_character_kills(character_id)

      # Verify the result is a list
      assert is_list(result)
      assert length(result) == 1
      assert hd(result)["killmail_id"] == "12345"
    end

    test "handles empty response from API" do
      character_id = "67890"

      # Mock the HTTP client response with empty array
      MockHTTPClient
      |> expect(:get, fn _url, _headers ->
        {:ok, %HTTPoison.Response{status_code: 200, body: "[]"}}
      end)

      # Call the function
      {:ok, result} = Client.get_character_kills(character_id)

      # Verify we get an empty list
      assert result == []
    end
  end
end
