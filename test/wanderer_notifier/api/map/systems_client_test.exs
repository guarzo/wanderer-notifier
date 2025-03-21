defmodule WandererNotifier.Api.Map.SystemsClientTest do
  use WandererNotifier.TestCase
  alias WandererNotifier.Api.Map.SystemsClient
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

  describe "get_systems/0" do
    test "successfully retrieves systems data" do
      mock_response = %{
        "data" => [
          sample_system(),
          %{
            "id" => "j654321",
            "name" => "J654321",
            "class" => "C3",
            "effect" => nil,
            "statics" => ["K162"],
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
      {:ok, result} = SystemsClient.get_systems()

      # Verify the result
      assert is_list(result)
      assert length(result) == 2
      [first, second] = result
      assert first["name"] == "J123456"
      assert second["name"] == "J654321"
    end

    test "handles error response from API" do
      # Mock the HTTP client response
      MockHTTPClient
      |> expect(:get, fn _url, _headers ->
        {:error, %HTTPoison.Error{reason: "connection_failed"}}
      end)

      # Call the function
      result = SystemsClient.get_systems()

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
      result = SystemsClient.get_systems()

      # Verify the error
      assert {:error, _} = result
    end

    test "handles malformed JSON response" do
      # Mock the HTTP client response
      MockHTTPClient
      |> expect(:get, fn _url, _headers ->
        {:ok, %HTTPoison.Response{status_code: 200, body: "{invalid json"}}
      end)

      # Call the function
      result = SystemsClient.get_systems()

      # Verify the error
      assert {:error, _} = result
    end
  end

  describe "get_system/1" do
    test "successfully retrieves individual system data" do
      system_id = "j123456"

      mock_response = %{
        "data" => sample_system()
      }

      # Mock the HTTP client response
      MockHTTPClient
      |> expect(:get, fn url, _headers ->
        # Verify URL contains the system ID
        assert String.contains?(url, system_id)

        {:ok, %HTTPoison.Response{status_code: 200, body: Jason.encode!(mock_response)}}
      end)

      # Call the function
      {:ok, result} = SystemsClient.get_system(system_id)

      # Verify the result
      assert result["id"] == "j123456"
      assert result["name"] == "J123456"
      assert result["class"] == "C5"
    end

    test "handles system not found" do
      system_id = "nonexistent"

      # Mock the HTTP client response
      MockHTTPClient
      |> expect(:get, fn _url, _headers ->
        {:ok, %HTTPoison.Response{status_code: 404, body: "{\"error\": \"System not found\"}"}}
      end)

      # Call the function
      result = SystemsClient.get_system(system_id)

      # Verify the error
      assert {:error, _} = result
    end
  end

  describe "add_system/1" do
    test "successfully adds a new system" do
      system_data = %{
        "id" => "j123456",
        "name" => "J123456",
        "class" => "C5"
      }

      mock_response = %{
        "data" => Map.merge(system_data, %{"tracked" => true})
      }

      # Mock the HTTP client response
      MockHTTPClient
      |> expect(:post, fn url, body, headers ->
        # Verify URL is correct
        assert String.contains?(url, "test-map")
        # Verify body contains system data
        decoded_body = Jason.decode!(body)
        assert decoded_body["id"] == system_data["id"]
        # Verify auth headers
        assert Enum.any?(headers, fn {k, v} ->
                 k == "Authorization" && v == "Bearer test-token"
               end)

        {:ok, %HTTPoison.Response{status_code: 201, body: Jason.encode!(mock_response)}}
      end)

      # Call the function
      {:ok, result} = SystemsClient.add_system(system_data)

      # Verify the result
      assert result["id"] == "j123456"
      assert result["tracked"] == true
    end

    test "handles error when adding system" do
      system_data = %{
        "id" => "invalid",
        "name" => "Invalid"
      }

      # Mock the HTTP client error response
      MockHTTPClient
      |> expect(:post, fn _url, _body, _headers ->
        {:ok, %HTTPoison.Response{status_code: 400, body: "{\"error\": \"Invalid system data\"}"}}
      end)

      # Call the function
      result = SystemsClient.add_system(system_data)

      # Verify the error
      assert {:error, _} = result
    end
  end

  describe "delete_system/1" do
    test "successfully deletes a system" do
      system_id = "j123456"

      # Mock the HTTP client response
      MockHTTPClient
      |> expect(:delete, fn url, headers ->
        # Verify URL contains the system ID
        assert String.contains?(url, system_id)
        # Verify auth headers
        assert Enum.any?(headers, fn {k, v} ->
                 k == "Authorization" && v == "Bearer test-token"
               end)

        {:ok, %HTTPoison.Response{status_code: 204, body: ""}}
      end)

      # Call the function
      result = SystemsClient.delete_system(system_id)

      # Verify success
      assert result == :ok
    end

    test "handles error when deleting system" do
      system_id = "nonexistent"

      # Mock the HTTP client error response
      MockHTTPClient
      |> expect(:delete, fn _url, _headers ->
        {:ok, %HTTPoison.Response{status_code: 404, body: "{\"error\": \"System not found\"}"}}
      end)

      # Call the function
      result = SystemsClient.delete_system(system_id)

      # Verify the error
      assert {:error, _} = result
    end
  end
end
