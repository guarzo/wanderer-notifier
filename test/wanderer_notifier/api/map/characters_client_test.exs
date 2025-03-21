defmodule WandererNotifier.Api.Map.CharactersClientTest do
  use WandererNotifier.TestCase
  alias WandererNotifier.Api.Map.CharactersClient
  alias WandererNotifier.MockHTTPClient

  setup do
    # Use our mock HTTP client
    Application.put_env(:wanderer_notifier, :http_client, WandererNotifier.MockHTTPClient)

    # Mock environment variables needed by the client
    Application.put_env(:wanderer_notifier, :map_url, "https://test-map.example.com")
    Application.put_env(:wanderer_notifier, :map_name, "test-map")
    Application.put_env(:wanderer_notifier, :map_token, "test-token")

    :ok
  end

  describe "get_characters/0" do
    test "successfully retrieves characters data" do
      mock_response = %{
        "data" => [
          sample_character(),
          %{
            "character" => %{
              "name" => "Another Character",
              "alliance_id" => 98765,
              "alliance_ticker" => "ANTR",
              "corporation_id" => 54321,
              "corporation_ticker" => "ACORP",
              "eve_id" => "987654321"
            },
            "tracked" => true
          }
        ]
      }

      # Mock the HTTP client response
      MockHTTPClient
      |> expect(:get, fn url, headers ->
        # Verify URL contains the map name
        assert String.contains?(url, "test-map")
        # Verify auth token is used
        assert Enum.any?(headers, fn {k, v} ->
                 k == "Authorization" && v == "Bearer test-token"
               end)

        {:ok, %HTTPoison.Response{status_code: 200, body: Jason.encode!(mock_response)}}
      end)

      # Call the function
      {:ok, result} = CharactersClient.get_characters()

      # Verify the result
      assert is_list(result)
      assert length(result) == 2
      [first, second] = result
      assert get_in(first, ["character", "name"]) == "Test Character"
      assert get_in(second, ["character", "name"]) == "Another Character"
    end

    test "handles error response from API" do
      # Mock the HTTP client response
      MockHTTPClient
      |> expect(:get, fn _url, _headers ->
        {:error, %HTTPoison.Error{reason: "connection_failed"}}
      end)

      # Call the function
      result = CharactersClient.get_characters()

      # Verify the error
      assert {:error, _} = result
    end

    test "handles non-200 responses" do
      # Mock the HTTP client response
      MockHTTPClient
      |> expect(:get, fn _url, _headers ->
        {:ok, %HTTPoison.Response{status_code: 403, body: "Forbidden"}}
      end)

      # Call the function
      result = CharactersClient.get_characters()

      # Verify the error
      assert {:error, _} = result
    end
  end

  describe "get_character/1" do
    test "successfully retrieves individual character data" do
      character_id = "123456789"

      mock_response = %{
        "data" => sample_character()
      }

      # Mock the HTTP client response
      MockHTTPClient
      |> expect(:get, fn url, _headers ->
        # Verify URL contains the character ID
        assert String.contains?(url, character_id)

        {:ok, %HTTPoison.Response{status_code: 200, body: Jason.encode!(mock_response)}}
      end)

      # Call the function
      {:ok, result} = CharactersClient.get_character(character_id)

      # Verify the result
      assert get_in(result, ["character", "name"]) == "Test Character"
      assert get_in(result, ["character", "eve_id"]) == "123456789"
    end

    test "handles character not found" do
      character_id = "nonexistent"

      # Mock the HTTP client response
      MockHTTPClient
      |> expect(:get, fn _url, _headers ->
        {:ok, %HTTPoison.Response{status_code: 404, body: "{\"error\": \"Character not found\"}"}}
      end)

      # Call the function
      result = CharactersClient.get_character(character_id)

      # Verify the error
      assert {:error, _} = result
    end
  end

  describe "add_character/1" do
    test "successfully adds a new character" do
      character_data = %{
        "name" => "New Character",
        "corporation_id" => 12345,
        "corporation_name" => "Test Corp",
        "eve_id" => "555555"
      }

      mock_response = %{
        "data" => %{
          "character" => %{
            "name" => "New Character",
            "corporation_id" => 12345,
            "corporation_ticker" => "TEST",
            "eve_id" => "555555"
          },
          "tracked" => true
        }
      }

      # Mock the HTTP client response
      MockHTTPClient
      |> expect(:post, fn url, body, headers ->
        # Verify URL is correct
        assert String.contains?(url, "test-map")
        # Verify body contains character data
        decoded_body = Jason.decode!(body)
        assert decoded_body["name"] == character_data["name"]
        # Verify auth headers
        assert Enum.any?(headers, fn {k, v} ->
                 k == "Authorization" && v == "Bearer test-token"
               end)

        {:ok, %HTTPoison.Response{status_code: 201, body: Jason.encode!(mock_response)}}
      end)

      # Call the function
      {:ok, result} = CharactersClient.add_character(character_data)

      # Verify the result
      assert get_in(result, ["character", "name"]) == "New Character"
      assert result["tracked"] == true
    end

    test "handles error when adding character" do
      character_data = %{
        "name" => "Invalid",
        "eve_id" => "invalid"
      }

      # Mock the HTTP client error response
      MockHTTPClient
      |> expect(:post, fn _url, _body, _headers ->
        {:ok,
         %HTTPoison.Response{status_code: 400, body: "{\"error\": \"Invalid character data\"}"}}
      end)

      # Call the function
      result = CharactersClient.add_character(character_data)

      # Verify the error
      assert {:error, _} = result
    end
  end

  describe "delete_character/1" do
    test "successfully deletes a character" do
      character_id = "123456789"

      # Mock the HTTP client response
      MockHTTPClient
      |> expect(:delete, fn url, headers ->
        # Verify URL contains the character ID
        assert String.contains?(url, character_id)
        # Verify auth headers
        assert Enum.any?(headers, fn {k, v} ->
                 k == "Authorization" && v == "Bearer test-token"
               end)

        {:ok, %HTTPoison.Response{status_code: 204, body: ""}}
      end)

      # Call the function
      result = CharactersClient.delete_character(character_id)

      # Verify success
      assert result == :ok
    end

    test "handles error when deleting character" do
      character_id = "nonexistent"

      # Mock the HTTP client error response
      MockHTTPClient
      |> expect(:delete, fn _url, _headers ->
        {:ok, %HTTPoison.Response{status_code: 404, body: "{\"error\": \"Character not found\"}"}}
      end)

      # Call the function
      result = CharactersClient.delete_character(character_id)

      # Verify the error
      assert {:error, _} = result
    end
  end
end
