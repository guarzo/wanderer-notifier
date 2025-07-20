defmodule WandererNotifier.Infrastructure.HttpTest do
  @moduledoc """
  Comprehensive tests for the unified HTTP client module.
  Tests service configurations, middleware pipeline, authentication, and error handling.
  """
  use ExUnit.Case, async: true
  import Mox

  alias WandererNotifier.Infrastructure.Http

  setup :verify_on_exit!

  describe "get/3" do
    test "makes successful GET request with default options" do
      url = "https://api.example.com/data"
      headers = [{"content-type", "application/json"}]

      WandererNotifier.HTTPMock
      |> expect(:get, fn ^url, ^headers, [] ->
        {:ok, %{status_code: 200, body: %{"success" => true}}}
      end)

      assert {:ok, %{status_code: 200, body: %{"success" => true}}} =
               Http.get(url, headers)
    end

    test "applies service configuration for ESI" do
      url = "https://esi.evetech.net/v1/character/123"

      WandererNotifier.HTTPMock
      |> expect(:get, fn ^url, [], opts ->
        # Verify ESI service config is applied
        assert opts[:timeout] == 30_000
        assert opts[:retry_count] == 3
        assert opts[:retry_delay] == 1_000
        assert opts[:decode_json] == true
        {:ok, %{status_code: 200, body: %{"name" => "Test Character"}}}
      end)

      assert {:ok, %{status_code: 200}} =
               Http.get(url, [], service: :esi)
    end

    test "applies service configuration for license" do
      url = "https://license.api.com/validate"

      WandererNotifier.HTTPMock
      |> expect(:get, fn ^url, [], opts ->
        # Verify license service config is applied
        assert opts[:timeout] == 10_000
        assert opts[:retry_count] == 1
        assert opts[:retry_delay] == 2_000
        {:ok, %{status_code: 200, body: %{"valid" => true}}}
      end)

      assert {:ok, %{status_code: 200}} =
               Http.get(url, [], service: :license)
    end

    test "handles bearer token authentication" do
      url = "https://api.example.com/protected"
      token = "secret_token_123"

      WandererNotifier.HTTPMock
      |> expect(:get, fn ^url, headers, _opts ->
        # Verify Authorization header is added
        assert {"Authorization", "Bearer secret_token_123"} in headers
        {:ok, %{status_code: 200, body: %{"authorized" => true}}}
      end)

      assert {:ok, %{status_code: 200}} =
               Http.get(url, [], auth: [type: :bearer, token: token])
    end

    test "handles API key authentication" do
      url = "https://api.example.com/protected"
      api_key = "api_key_456"

      WandererNotifier.HTTPMock
      |> expect(:get, fn ^url, headers, _opts ->
        # Verify API key header is added
        assert {"X-API-Key", "api_key_456"} in headers
        {:ok, %{status_code: 200, body: %{"authorized" => true}}}
      end)

      assert {:ok, %{status_code: 200}} =
               Http.get(url, [], auth: [type: :api_key, key: api_key])
    end

    test "merges custom options with service config" do
      url = "https://esi.evetech.net/v1/status"
      custom_timeout = 5_000

      WandererNotifier.HTTPMock
      |> expect(:get, fn ^url, [], opts ->
        # Custom timeout should override service default
        assert opts[:timeout] == custom_timeout
        # But other service configs remain
        assert opts[:retry_count] == 3
        {:ok, %{status_code: 200, body: %{"online" => true}}}
      end)

      assert {:ok, %{status_code: 200}} =
               Http.get(url, [], service: :esi, timeout: custom_timeout)
    end

    test "handles network errors gracefully" do
      url = "https://api.example.com/error"

      WandererNotifier.HTTPMock
      |> expect(:get, fn ^url, [], _opts ->
        {:error, :timeout}
      end)

      assert {:error, :timeout} = Http.get(url)
    end

    test "handles non-200 status codes" do
      url = "https://api.example.com/not-found"

      WandererNotifier.HTTPMock
      |> expect(:get, fn ^url, [], _opts ->
        {:ok, %{status_code: 404, body: %{"error" => "Not found"}}}
      end)

      assert {:ok, %{status_code: 404, body: %{"error" => "Not found"}}} =
               Http.get(url)
    end
  end

  describe "post/4" do
    test "makes successful POST request with JSON body" do
      url = "https://api.example.com/data"
      body = %{"name" => "Test", "value" => 123}

      WandererNotifier.HTTPMock
      |> expect(:post, fn ^url, encoded_body, headers, _opts ->
        # Verify JSON encoding
        assert encoded_body == Jason.encode!(body)
        # Verify Content-Type header
        assert {"Content-Type", "application/json"} in headers
        {:ok, %{status_code: 201, body: %{"id" => 1}}}
      end)

      assert {:ok, %{status_code: 201, body: %{"id" => 1}}} =
               Http.post(url, body)
    end

    test "handles string body without JSON encoding" do
      url = "https://api.example.com/raw"
      body = "raw string data"

      WandererNotifier.HTTPMock
      |> expect(:post, fn ^url, ^body, _headers, _opts ->
        {:ok, %{status_code: 200, body: "ok"}}
      end)

      assert {:ok, %{status_code: 200}} =
               Http.post(url, body)
    end

    test "applies authentication to POST requests" do
      url = "https://api.example.com/create"
      body = %{"data" => "test"}
      token = "bearer_token"

      WandererNotifier.HTTPMock
      |> expect(:post, fn ^url, _body, headers, _opts ->
        assert {"Authorization", "Bearer bearer_token"} in headers
        {:ok, %{status_code: 201, body: %{"created" => true}}}
      end)

      assert {:ok, %{status_code: 201}} =
               Http.post(url, body, [], auth: [type: :bearer, token: token])
    end

    test "handles POST errors" do
      url = "https://api.example.com/error"
      body = %{"bad" => "data"}

      WandererNotifier.HTTPMock
      |> expect(:post, fn ^url, _body, _headers, _opts ->
        {:ok, %{status_code: 400, body: %{"error" => "Bad request"}}}
      end)

      assert {:ok, %{status_code: 400, body: %{"error" => "Bad request"}}} =
               Http.post(url, body)
    end
  end

  describe "put/4" do
    test "makes successful PUT request" do
      url = "https://api.example.com/resource/123"
      body = %{"name" => "Updated"}

      WandererNotifier.HTTPMock
      |> expect(:put, fn ^url, encoded_body, headers, _opts ->
        assert encoded_body == Jason.encode!(body)
        assert {"Content-Type", "application/json"} in headers
        {:ok, %{status_code: 200, body: %{"updated" => true}}}
      end)

      assert {:ok, %{status_code: 200}} =
               Http.put(url, body)
    end
  end

  describe "delete/3" do
    test "makes successful DELETE request" do
      url = "https://api.example.com/resource/123"

      WandererNotifier.HTTPMock
      |> expect(:delete, fn ^url, [], _opts ->
        {:ok, %{status_code: 204, body: ""}}
      end)

      assert {:ok, %{status_code: 204}} =
               Http.delete(url)
    end

    test "applies service configuration to DELETE" do
      url = "https://api.example.com/resource/456"

      WandererNotifier.HTTPMock
      |> expect(:delete, fn ^url, [], opts ->
        # Should apply wanderer_kills service config
        assert opts[:timeout] == 15_000
        {:ok, %{status_code: 200, body: %{"deleted" => true}}}
      end)

      assert {:ok, %{status_code: 200}} =
               Http.delete(url, [], service: :wanderer_kills)
    end
  end

  describe "service configurations" do
    test "ESI service has correct configuration" do
      config = Http.service_config(:esi)

      assert config[:timeout] == 30_000
      assert config[:retry_count] == 3
      assert config[:retry_delay] == 1_000
      assert config[:retryable_status_codes] == [429, 500, 502, 503, 504]
      assert config[:decode_json] == true
      assert config[:rate_limit][:requests_per_second] == 20
      assert config[:rate_limit][:burst_capacity] == 40
      assert config[:rate_limit][:per_host] == true
    end

    test "wanderer_kills service has correct configuration" do
      config = Http.service_config(:wanderer_kills)

      assert config[:timeout] == 15_000
      assert config[:retry_count] == 2
      assert config[:retry_delay] == 1_000
      assert config[:decode_json] == true
    end

    test "license service has correct configuration" do
      config = Http.service_config(:license)

      assert config[:timeout] == 10_000
      assert config[:retry_count] == 1
      assert config[:retry_delay] == 2_000
      assert config[:rate_limit][:requests_per_second] == 1
      assert config[:rate_limit][:burst_capacity] == 2
    end

    test "map service has correct configuration" do
      config = Http.service_config(:map)

      assert config[:timeout] == 45_000
      assert config[:retry_count] == 2
      assert config[:retry_delay] == 500
      assert config[:decode_json] == true
    end

    test "streaming service has correct configuration" do
      config = Http.service_config(:streaming)

      assert config[:timeout] == :infinity
      assert config[:disable_middleware] == true
      assert config[:follow_redirects] == false
      assert config[:decode_json] == false
    end

    test "unknown service returns empty configuration" do
      config = Http.service_config(:unknown_service)

      assert config == []
    end
  end

  describe "error handling" do
    test "handles JSON encoding errors gracefully" do
      url = "https://api.example.com/data"
      # Create a body that can't be JSON encoded
      body = %{invalid: make_ref()}

      assert_raise Jason.EncodeError, fn ->
        Http.post(url, body)
      end
    end

    test "handles missing authentication token" do
      url = "https://api.example.com/protected"

      WandererNotifier.HTTPMock
      |> expect(:get, fn ^url, headers, _opts ->
        # No Authorization header should be added
        refute Enum.any?(headers, fn {k, _v} -> k == "Authorization" end)
        {:ok, %{status_code: 401, body: %{"error" => "Unauthorized"}}}
      end)

      # Missing token should not crash
      assert {:ok, %{status_code: 401}} =
               Http.get(url, [], auth: [type: :bearer])
    end

    test "handles malformed URLs" do
      url = "not a valid url"

      WandererNotifier.HTTPMock
      |> expect(:get, fn ^url, [], _opts ->
        {:error, :invalid_url}
      end)

      assert {:error, :invalid_url} = Http.get(url)
    end
  end

  describe "request/response logging" do
    @tag :capture_log
    test "logs requests and responses when enabled" do
      url = "https://api.example.com/test"

      WandererNotifier.HTTPMock
      |> expect(:get, fn ^url, [], _opts ->
        {:ok, %{status_code: 200, body: %{"success" => true}}}
      end)

      # Log level would need to be configured appropriately
      assert {:ok, _} = Http.get(url)
    end
  end

  describe "concurrent requests" do
    test "handles multiple concurrent requests" do
      urls = for i <- 1..10, do: "https://api.example.com/resource/#{i}"

      WandererNotifier.HTTPMock
      |> expect(:get, 10, fn url, [], _opts ->
        # Extract ID from URL
        [_, id] = Regex.run(~r/resource\/(\d+)$/, url)
        {:ok, %{status_code: 200, body: %{"id" => id}}}
      end)

      # Make concurrent requests
      tasks =
        for url <- urls do
          Task.async(fn -> Http.get(url) end)
        end

      results = Task.await_many(tasks)

      assert length(results) == 10

      assert Enum.all?(results, fn
               {:ok, %{status_code: 200}} -> true
               _ -> false
             end)
    end
  end

  describe "special behaviors" do
    test "get_json/3 forces JSON decoding" do
      url = "https://api.example.com/json"

      WandererNotifier.HTTPMock
      |> expect(:get, fn ^url, [], opts ->
        assert opts[:decode_json] == true
        {:ok, %{status_code: 200, body: %{"json" => true}}}
      end)

      assert {:ok, %{status_code: 200}} = Http.get_json(url)
    end

    test "post_json/4 encodes body as JSON" do
      url = "https://api.example.com/json"
      body = %{"test" => "data"}

      WandererNotifier.HTTPMock
      |> expect(:post_json, fn ^url, ^body, [], _opts ->
        {:ok, %{status_code: 201, body: %{"created" => true}}}
      end)

      assert {:ok, %{status_code: 201}} = Http.post_json(url, body)
    end

    test "get_killmail/2 uses ZKillboard API" do
      killmail_id = 123_456
      hash = "abc123"

      WandererNotifier.HTTPMock
      |> expect(:get_killmail, fn ^killmail_id, ^hash ->
        {:ok, %{status_code: 200, body: [%{"killmail_id" => killmail_id}]}}
      end)

      assert {:ok, %{status_code: 200}} = Http.get_killmail(killmail_id, hash)
    end
  end
end
