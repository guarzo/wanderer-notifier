defmodule WandererNotifier.License.ClientV2Test do
  use ExUnit.Case, async: true
  import Mox

  alias WandererNotifier.License.ClientV2

  setup :verify_on_exit!

  describe "ClientV2 validate_bot/2" do
    test "successfully validates bot with license_valid format" do
      notifier_api_token = "test-token"
      license_key = "test-license-key"

      expected_response = %{
        "license_valid" => true,
        "message" => "License is valid",
        "features" => ["premium_embeds"]
      }

      expect(WandererNotifier.HTTPMock, :post, fn url, body, headers, opts ->
        assert url == "https://license.example.com/api/validate_bot"
        assert {"Authorization", "Bearer #{notifier_api_token}"} in headers
        assert {"Content-Type", "application/json"} in headers

        decoded_body = Jason.decode!(body)
        assert decoded_body["license_key"] == license_key

        # Verify no rate limiting during startup
        assert opts[:rate_limit_options] == []

        {:ok, %{status_code: 200, body: expected_response}}
      end)

      result = ClientV2.validate_bot(notifier_api_token, license_key)
      assert {:ok, response} = result
      assert response[:valid] == true
      assert response[:raw_response]["license_valid"] == true
    end

    test "handles bot validation errors" do
      notifier_api_token = "test-token"
      license_key = "invalid-key"

      expect(WandererNotifier.HTTPMock, :post, fn _url, _body, _headers, _opts ->
        {:ok, %{status_code: 400, body: "Bad Request"}}
      end)

      result = ClientV2.validate_bot(notifier_api_token, license_key)
      assert {:error, :request_failed} = result
    end

    test "handles network timeouts during bot validation" do
      notifier_api_token = "test-token"
      license_key = "test-key"

      expect(WandererNotifier.HTTPMock, :post, fn _url, _body, _headers, _opts ->
        {:error, :timeout}
      end)

      result = ClientV2.validate_bot(notifier_api_token, license_key)
      assert {:error, :request_failed} = result
    end

    test "handles invalid response format during bot validation" do
      notifier_api_token = "test-token"
      license_key = "test-key"

      expect(WandererNotifier.HTTPMock, :post, fn _url, _body, _headers, _opts ->
        {:ok, %{status_code: 200, body: "invalid response"}}
      end)

      result = ClientV2.validate_bot(notifier_api_token, license_key)
      assert {:ok, response} = result
      assert response[:valid] == false
      assert response[:error_message] =~ "Invalid response format"
    end
  end

  describe "ClientV2 validate_license/2" do
    test "successfully validates license with valid format" do
      license_key = "test-license-key"
      notifier_api_token = "test-token"

      expected_response = %{
        "valid" => true,
        "bot_assigned" => true,
        "message" => "License is valid and bot is assigned"
      }

      expect(WandererNotifier.HTTPMock, :post, fn url, body, headers, opts ->
        assert url == "https://license.example.com/api/validate_license"
        assert {"Authorization", "Bearer #{notifier_api_token}"} in headers

        decoded_body = Jason.decode!(body)
        assert decoded_body["license_key"] == license_key

        # Verify rate limiting is configured for license requests
        rate_limit_opts = opts[:rate_limit_options]
        assert rate_limit_opts[:requests_per_second] == 1
        assert rate_limit_opts[:burst_capacity] == 2
        assert rate_limit_opts[:per_host] == true

        {:ok, %{status_code: 200, body: expected_response}}
      end)

      result = ClientV2.validate_license(license_key, notifier_api_token)
      assert {:ok, %{"valid" => true, "bot_assigned" => true}} = result
    end

    test "handles license_valid format response" do
      license_key = "test-license-key"
      notifier_api_token = "test-token"

      expected_response = %{
        "license_valid" => true,
        "message" => "License is valid"
      }

      expect(WandererNotifier.HTTPMock, :post, fn _url, _body, _headers, _opts ->
        {:ok, %{status_code: 200, body: expected_response}}
      end)

      result = ClientV2.validate_license(license_key, notifier_api_token)
      assert {:ok, %{"license_valid" => true, "valid" => true}} = result
    end

    test "handles unknown response format" do
      license_key = "test-license-key"
      notifier_api_token = "test-token"

      unexpected_response = %{
        "some_field" => "some_value",
        "another_field" => 123
      }

      expect(WandererNotifier.HTTPMock, :post, fn _url, _body, _headers, _opts ->
        {:ok, %{status_code: 200, body: unexpected_response}}
      end)

      result = ClientV2.validate_license(license_key, notifier_api_token)
      assert {:ok, response} = result
      assert response["valid"] == false
      assert response["message"] == "Unrecognized response format"
      assert response["some_field"] == "some_value"
    end

    test "handles partial validation (license valid but bot not assigned)" do
      license_key = "test-license-key"
      notifier_api_token = "test-token"

      expected_response = %{
        "valid" => true,
        "bot_assigned" => false,
        "message" => "License is valid but bot is not assigned"
      }

      expect(WandererNotifier.HTTPMock, :post, fn _url, _body, _headers, _opts ->
        {:ok, %{status_code: 200, body: expected_response}}
      end)

      result = ClientV2.validate_license(license_key, notifier_api_token)
      assert {:ok, %{"valid" => true, "bot_assigned" => false}} = result
    end

    test "handles license validation errors" do
      license_key = "invalid-key"
      notifier_api_token = "test-token"

      expect(WandererNotifier.HTTPMock, :post, fn _url, _body, _headers, _opts ->
        {:error, :timeout}
      end)

      result = ClientV2.validate_license(license_key, notifier_api_token)
      assert {:error, "Request timed out"} = result
    end

    test "handles exceptions during license validation" do
      license_key = "test-key"
      notifier_api_token = "test-token"

      expect(WandererNotifier.HTTPMock, :post, fn _url, _body, _headers, _opts ->
        raise "Network error"
      end)

      result = ClientV2.validate_license(license_key, notifier_api_token)
      assert {:error, error_message} = result
      assert error_message =~ "Exception"
    end

    test "handles rate limit errors" do
      license_key = "test-key"
      notifier_api_token = "test-token"

      expect(WandererNotifier.HTTPMock, :post, fn _url, _body, _headers, _opts ->
        {:error, :rate_limited}
      end)

      result = ClientV2.validate_license(license_key, notifier_api_token)
      assert {:error, error_message} = result
      assert error_message =~ "Request failed"
    end
  end

  describe "ClientV2 configuration" do
    test "uses correct base configuration" do
      assert ClientV2.base_url() == "https://license.example.com"
      assert ClientV2.default_timeout() == 15_000
      assert ClientV2.default_recv_timeout() == 15_000
      assert ClientV2.service_name() == "license_manager"
    end
  end

  describe "ClientV2 request options" do
    test "configures different options for bot validation vs license validation" do
      notifier_api_token = "test-token"
      license_key = "test-key"

      # Test bot validation (no rate limiting)
      expect(WandererNotifier.HTTPMock, :post, fn _url, _body, _headers, opts ->
        assert opts[:rate_limit_options] == []
        assert opts[:retry_options][:max_attempts] == 2
        assert opts[:retry_options][:context] == "License validation request"

        {:ok, %{status_code: 200, body: %{"license_valid" => true}}}
      end)

      ClientV2.validate_bot(notifier_api_token, license_key)

      # Test license validation (with rate limiting)
      expect(WandererNotifier.HTTPMock, :post, fn _url, _body, _headers, opts ->
        rate_limit_opts = opts[:rate_limit_options]
        assert rate_limit_opts[:requests_per_second] == 1
        assert rate_limit_opts[:burst_capacity] == 2
        assert opts[:retry_options][:max_attempts] == 3
        assert opts[:retry_options][:context] == "License request"

        {:ok, %{status_code: 200, body: %{"valid" => true}}}
      end)

      ClientV2.validate_license(license_key, notifier_api_token)
    end
  end
end
