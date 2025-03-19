defmodule WandererNotifier.LicenseManager.ClientTest do
  use ExUnit.Case
  import Mox
  alias WandererNotifier.LicenseManager.Client

  # Make sure mocks are verified when the test exits
  setup :verify_on_exit!

  setup do
    # Set up environment variables for testing
    Application.put_env(:wanderer_notifier, :license_manager_api_url, "https://api.example.com")
    Application.put_env(:wanderer_notifier, :bot_registration_token, "test-bot-token")

    :ok
  end

  describe "validate_license/1" do
    test "returns {:ok, response} when the license is valid" do
      license_key = "valid-license-key"
      expected_url = "https://api.example.com/api/licenses/validate"

      expected_headers = [
        {"Content-Type", "application/json"}
      ]

      expected_body =
        Jason.encode!(%{
          license_key: license_key,
          bot_token: "test-bot-token",
          bot_type: "wanderer_notifier"
        })

      # Mock the HTTP response
      expect(HTTPoison, :post, fn ^expected_url, ^expected_body, ^expected_headers ->
        {:ok,
         %HTTPoison.Response{
           status_code: 200,
           body:
             Jason.encode!(%{
               "valid" => true,
               "features" => ["feature1", "feature2"],
               "tier" => "premium"
             })
         }}
      end)

      assert {:ok, response} = Client.validate_license(license_key)
      assert response["valid"] == true
      assert response["features"] == ["feature1", "feature2"]
      assert response["tier"] == "premium"
    end

    test "returns {:error, :unauthorized} when the API returns 401" do
      license_key = "invalid-license-key"

      # Mock the HTTP response
      expect(HTTPoison, :post, fn _, _, _ ->
        {:ok, %HTTPoison.Response{status_code: 401, body: ""}}
      end)

      assert {:error, :unauthorized} = Client.validate_license(license_key)
    end

    test "returns {:error, :license_not_found} when the API returns 404" do
      license_key = "nonexistent-license-key"

      # Mock the HTTP response
      expect(HTTPoison, :post, fn _, _, _ ->
        {:ok, %HTTPoison.Response{status_code: 404, body: ""}}
      end)

      assert {:error, :license_not_found} = Client.validate_license(license_key)
    end

    test "returns {:error, :api_error} when the API returns an unexpected status code" do
      license_key = "error-license-key"

      # Mock the HTTP response
      expect(HTTPoison, :post, fn _, _, _ ->
        {:ok, %HTTPoison.Response{status_code: 500, body: "Internal Server Error"}}
      end)

      assert {:error, :api_error} = Client.validate_license(license_key)
    end

    test "returns {:error, :request_failed} when the HTTP request fails" do
      license_key = "network-error-license-key"

      # Mock the HTTP response
      expect(HTTPoison, :post, fn _, _, _ ->
        {:error, %HTTPoison.Error{reason: :timeout}}
      end)

      assert {:error, :request_failed} = Client.validate_license(license_key)
    end

    test "returns {:error, :invalid_response} when the response is not valid JSON" do
      license_key = "invalid-json-license-key"

      # Mock the HTTP response
      expect(HTTPoison, :post, fn _, _, _ ->
        {:ok, %HTTPoison.Response{status_code: 200, body: "not valid json"}}
      end)

      assert {:error, :invalid_response} = Client.validate_license(license_key)
    end
  end
end
