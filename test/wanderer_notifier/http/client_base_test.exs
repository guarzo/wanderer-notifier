defmodule WandererNotifier.Http.ClientBaseTest do
  use ExUnit.Case, async: true
  import Mox

  alias WandererNotifier.Http.ClientBase

  setup :verify_on_exit!

  # Test module that uses ClientBase
  defmodule TestClient do
    use WandererNotifier.Http.ClientBase,
      base_url: "https://test.example.com",
      timeout: 5000,
      service_name: "test_service"

    def get_test_resource(id) do
      url = "#{base_url()}/resources/#{id}"

      request(:get, url,
        headers: build_headers(),
        opts: build_default_opts()
      )
    end

    def post_test_resource(data) do
      url = "#{base_url()}/resources"

      request(:post, url,
        body: data,
        headers: build_headers(),
        opts: build_default_opts()
      )
    end
  end

  setup :verify_on_exit!

  describe "build_default_opts/2" do
    test "builds default options with timeouts" do
      opts = ClientBase.build_default_opts()

      assert opts[:timeout] == 15_000
      assert opts[:recv_timeout] == 15_000
    end

    test "merges base options with defaults" do
      base_opts = [custom: :value]
      config = %{timeout: 5000}
      opts = ClientBase.build_default_opts(base_opts, config)

      assert opts[:custom] == :value
      assert opts[:timeout] == 5000
      assert opts[:recv_timeout] == 15_000
    end

    test "adds retry options when provided" do
      config = %{
        retry_options: [
          max_attempts: 3,
          base_backoff: 1000
        ]
      }

      opts = ClientBase.build_default_opts([], config)

      assert opts[:retry_options] == [max_attempts: 3, base_backoff: 1000]
    end

    test "adds rate limit options when provided" do
      config = %{
        rate_limit_options: [
          requests_per_second: 10,
          burst_capacity: 20
        ]
      }

      opts = ClientBase.build_default_opts([], config)

      assert opts[:rate_limit_options] == [requests_per_second: 10, burst_capacity: 20]
    end

    test "adds telemetry options when provided" do
      config = %{
        telemetry_options: [
          service_name: "test_service"
        ]
      }

      opts = ClientBase.build_default_opts([], config)

      assert opts[:telemetry_options] == [service_name: "test_service"]
    end
  end

  describe "build_headers/2" do
    test "builds default headers" do
      headers = ClientBase.build_headers()

      assert {"Content-Type", "application/json"} in headers
      assert {"Accept", "application/json"} in headers
      assert {"User-Agent", "WandererNotifier/1.0"} in headers
    end

    test "adds custom headers" do
      custom = [{"Authorization", "Bearer token"}]
      headers = ClientBase.build_headers(custom)

      assert {"Authorization", "Bearer token"} in headers
      assert {"Content-Type", "application/json"} in headers
    end

    test "uses custom user agent when provided" do
      headers = ClientBase.build_headers([], user_agent: "CustomAgent/2.0")

      assert {"User-Agent", "CustomAgent/2.0"} in headers
    end
  end

  describe "decode_json_response/1" do
    test "decodes valid JSON string" do
      json = ~s({"key": "value", "number": 42})

      assert {:ok, decoded} = ClientBase.decode_json_response(json)
      assert decoded["key"] == "value"
      assert decoded["number"] == 42
    end

    test "returns error for invalid JSON" do
      invalid_json = ~s({invalid json})

      assert {:error, {:json_decode_error, _}} = ClientBase.decode_json_response(invalid_json)
    end

    test "passes through non-binary data" do
      data = %{"already" => "decoded"}

      assert {:ok, ^data} = ClientBase.decode_json_response(data)
    end
  end

  describe "handle_response/2" do
    test "handles successful response with default success codes" do
      response = {:ok, %{status_code: 200, body: %{"data" => "test"}}}

      result = ClientBase.handle_response(response)
      assert result == {:ok, %{"data" => "test"}}
    end

    test "handles response with custom success codes" do
      response = {:ok, %{status_code: 201, body: %{"created" => true}}}

      result = ClientBase.handle_response(response, success_codes: [200, 201, 204])
      assert result == {:ok, %{"created" => true}}
    end

    test "handles error responses" do
      response = {:ok, %{status_code: 404, body: "Not Found"}}

      result = ClientBase.handle_response(response)
      assert {:error, {:http_error, 404}} = result
    end

    test "includes custom handlers in response handling" do
      response = {:ok, %{status_code: 404, body: "Not Found"}}
      custom_handler = {404, fn _status, _body -> {:error, :not_found} end}

      result = ClientBase.handle_response(response, custom_handlers: [custom_handler])
      assert result == {:error, :not_found}
    end

    test "handles network errors" do
      response = {:error, :timeout}

      result = ClientBase.handle_response(response)
      assert result == {:error, :timeout}
    end
  end

  describe "with_timing/1" do
    test "measures successful request timing" do
      request_fn = fn -> {:ok, %{status_code: 200, body: "success"}} end

      {:ok, response} = ClientBase.with_timing(request_fn)
      assert response.status_code == 200
    end

    test "adds duration to error map" do
      request_fn = fn -> {:error, %{reason: "timeout"}} end

      {:error, error} = ClientBase.with_timing(request_fn)
      assert error.reason == "timeout"
      assert is_number(error.duration_ms)
    end

    test "handles non-map errors" do
      request_fn = fn -> {:error, :network_error} end

      {:error, reason} = ClientBase.with_timing(request_fn)
      assert reason == :network_error
    end
  end

  describe "request/3" do
    test "makes GET request without timing" do
      expect(WandererNotifier.HTTPMock, :get, fn url, headers, opts ->
        assert url == "https://test.example.com/test"
        assert headers == []
        assert opts == []
        {:ok, %{status_code: 200, body: "success"}}
      end)

      result = ClientBase.request(:get, "https://test.example.com/test")
      assert {:ok, %{status_code: 200, body: "success"}} = result
    end

    test "makes POST request with body" do
      body = %{data: "test"}

      expect(WandererNotifier.HTTPMock, :post, fn url, recv_body, headers, _opts ->
        assert url == "https://test.example.com/test"
        assert recv_body == body
        assert headers == [{"Custom", "Header"}]
        {:ok, %{status_code: 201, body: "created"}}
      end)

      result =
        ClientBase.request(:post, "https://test.example.com/test",
          body: body,
          headers: [{"Custom", "Header"}]
        )

      assert {:ok, %{status_code: 201, body: "created"}} = result
    end

    test "makes request with timing enabled" do
      expect(WandererNotifier.HTTPMock, :get, fn _url, _headers, _opts ->
        {:ok, %{status_code: 200, body: "success"}}
      end)

      result = ClientBase.request(:get, "https://test.example.com/test", with_timing: true)
      assert {:ok, %{status_code: 200, body: "success"}} = result
    end
  end

  describe "TestClient usage" do
    test "get_test_resource uses ClientBase functionality" do
      expect(WandererNotifier.HTTPMock, :get, fn url, headers, opts ->
        assert url == "https://test.example.com/resources/123"
        assert {"Content-Type", "application/json"} in headers
        assert {"User-Agent", "WandererNotifier/1.0"} in headers
        assert opts[:timeout] == 15_000
        {:ok, %{status_code: 200, body: %{"id" => 123}}}
      end)

      result = TestClient.get_test_resource(123)
      assert {:ok, %{status_code: 200, body: %{"id" => 123}}} = result
    end

    test "post_test_resource uses ClientBase functionality" do
      data = %{name: "Test Resource"}

      expect(WandererNotifier.HTTPMock, :post, fn url, body, headers, _opts ->
        assert url == "https://test.example.com/resources"
        assert body == data
        assert {"Content-Type", "application/json"} in headers
        {:ok, %{status_code: 201, body: %{"id" => 456}}}
      end)

      result = TestClient.post_test_resource(data)
      assert {:ok, %{status_code: 201, body: %{"id" => 456}}} = result
    end

    test "overridden module attributes work correctly" do
      assert TestClient.base_url() == "https://test.example.com"
      assert TestClient.default_timeout() == 5000
      assert TestClient.service_name() == "test_service"
    end
  end
end
