defmodule WandererNotifier.Infrastructure.Http.IntegrationTest do
  @moduledoc """
  Integration tests for the HTTP module with full middleware pipeline.
  Tests the interaction between different middleware components.
  """
  use ExUnit.Case, async: false
  import Mox

  alias WandererNotifier.Infrastructure.Http

  setup :verify_on_exit!

  describe "full middleware pipeline" do
    test "successful request goes through all middleware" do
      # Track middleware execution order
      test_pid = self()

      WandererNotifier.HTTPMock
      |> expect(:get, fn url, headers, opts ->
        send(test_pid, {:http_called, url, headers, opts})
        {:ok, %{status_code: 200, body: %{"data" => "test"}}}
      end)

      # Attach telemetry handler
      handler_id = "test-#{System.unique_integer()}"

      :telemetry.attach(
        handler_id,
        [:wanderer_notifier, :http, :request, :stop],
        fn _event, measurements, metadata, _ ->
          send(test_pid, {:telemetry_emitted, measurements, metadata})
        end,
        nil
      )

      on_exit(fn -> :telemetry.detach(handler_id) end)

      # Make request with ESI service config
      assert {:ok, %{status_code: 200, body: %{"data" => "test"}}} =
               Http.get("https://esi.evetech.net/test", [], service: :esi)

      # Verify HTTP client was called with middleware modifications
      assert_receive {:http_called, _url, _headers, opts}
      assert opts[:timeout] == 30_000
      assert opts[:retry_count] == 3

      # Verify telemetry was emitted
      assert_receive {:telemetry_emitted, measurements, metadata}
      assert measurements.duration > 0
      assert metadata.service == :esi
      assert metadata.status_code == 200
    end

    test "retry middleware handles transient failures" do
      call_count = :counters.new(1, [])

      WandererNotifier.HTTPMock
      |> expect(:post, 3, fn _url, _body, _headers, _opts ->
        count = :counters.add(call_count, 1, 1)

        if count < 3 do
          {:ok, %{status_code: 503, body: "Service Unavailable"}}
        else
          {:ok, %{status_code: 200, body: %{"success" => true}}}
        end
      end)

      # Should retry and eventually succeed
      assert {:ok, %{status_code: 200}} =
               Http.post("https://api.example.com/flaky", %{data: "test"}, [],
                 service: :wanderer_kills
               )

      # Verify it was called 3 times
      assert :counters.get(call_count, 1) == 3
    end

    test "rate limiter prevents request floods" do
      # Configure very restrictive rate limit
      WandererNotifier.HTTPMock
      |> expect(:get, 2, fn _url, _headers, _opts ->
        {:ok, %{status_code: 200, body: "ok"}}
      end)

      opts = [
        # Has rate limiting configured
        service: :license,
        rate_limit: [
          requests_per_second: 2,
          burst_capacity: 2
        ]
      ]

      # First 2 should succeed
      assert {:ok, _} = Http.get("https://license.api.com/check", [], opts)
      assert {:ok, _} = Http.get("https://license.api.com/check", [], opts)

      # Third should be rate limited
      assert {:error, :rate_limited} =
               Http.get("https://license.api.com/check", [], opts)
    end

    test "circuit breaker prevents cascading failures" do
      WandererNotifier.HTTPMock
      |> expect(:get, 3, fn _url, _headers, _opts ->
        {:error, :connection_refused}
      end)

      opts = [
        circuit_breaker: [
          failure_threshold: 3,
          reset_timeout: 1000
        ]
      ]

      # First 3 failures trip the circuit
      assert {:error, :connection_refused} =
               Http.get("https://failing.api.com/endpoint", [], opts)

      assert {:error, :connection_refused} =
               Http.get("https://failing.api.com/endpoint", [], opts)

      assert {:error, :connection_refused} =
               Http.get("https://failing.api.com/endpoint", [], opts)

      # Circuit is now open
      assert {:error, :circuit_open} =
               Http.get("https://failing.api.com/endpoint", [], opts)
    end

    test "authentication headers are properly added" do
      WandererNotifier.HTTPMock
      |> expect(:get, fn _url, headers, _opts ->
        assert {"Authorization", "Bearer test_token_123"} in headers
        {:ok, %{status_code: 200, body: %{"authenticated" => true}}}
      end)

      assert {:ok, %{status_code: 200}} =
               Http.get("https://api.example.com/protected", [],
                 auth: [type: :bearer, token: "test_token_123"]
               )
    end

    test "combines custom headers with auth headers" do
      WandererNotifier.HTTPMock
      |> expect(:post, fn _url, _body, headers, _opts ->
        assert {"Authorization", "Bearer token123"} in headers
        assert {"X-Custom-Header", "custom_value"} in headers
        assert {"Content-Type", "application/json"} in headers
        {:ok, %{status_code: 201, body: %{"created" => true}}}
      end)

      custom_headers = [{"X-Custom-Header", "custom_value"}]

      assert {:ok, %{status_code: 201}} =
               Http.post("https://api.example.com/create", %{name: "test"}, custom_headers,
                 auth: [type: :bearer, token: "token123"]
               )
    end

    test "handles complex service configuration" do
      test_pid = self()

      WandererNotifier.HTTPMock
      |> expect(:get, fn url, headers, opts ->
        send(test_pid, {:opts_received, opts})
        {:ok, %{status_code: 200, body: %{"systems" => []}}}
      end)

      # Map service has specific configuration
      assert {:ok, _} = Http.get("https://map.api.com/systems", [], service: :map)

      assert_receive {:opts_received, opts}
      # 1 minute
      assert opts[:timeout] == 60_000
      assert opts[:retry_count] == 2
      assert opts[:decode_json] == true
    end

    test "streaming requests bypass certain middleware" do
      WandererNotifier.HTTPMock
      |> expect(:get, fn _url, _headers, opts ->
        # Streaming should have special config
        assert opts[:stream] == true
        # 5 minutes
        assert opts[:timeout] == 300_000
        # No retries for streams
        assert opts[:retry_count] == 0
        {:ok, %{status_code: 200, body: :stream_ref}}
      end)

      assert {:ok, %{body: :stream_ref}} =
               Http.get("https://api.example.com/stream", [], service: :streaming)
    end

    test "handles JSON encoding errors gracefully" do
      # Create non-encodable data
      non_encodable = %{ref: make_ref()}

      assert_raise Jason.EncodeError, fn ->
        Http.post("https://api.example.com/data", non_encodable)
      end
    end

    test "propagates custom options through middleware" do
      WandererNotifier.HTTPMock
      |> expect(:get, fn _url, _headers, opts ->
        # Custom options should be preserved
        assert opts[:custom_option] == :custom_value
        assert opts[:another_option] == 123
        {:ok, %{status_code: 200, body: "ok"}}
      end)

      assert {:ok, _} =
               Http.get("https://api.example.com/test", [],
                 custom_option: :custom_value,
                 another_option: 123,
                 service: :esi
               )
    end

    test "handles DELETE requests with auth" do
      WandererNotifier.HTTPMock
      |> expect(:delete, fn _url, headers, _opts ->
        assert {"X-API-Key", "secret_key"} in headers
        {:ok, %{status_code: 204, body: ""}}
      end)

      assert {:ok, %{status_code: 204}} =
               Http.delete("https://api.example.com/resource/123", [],
                 auth: [type: :api_key, key: "secret_key"]
               )
    end

    test "handles PUT requests with complex body" do
      WandererNotifier.HTTPMock
      |> expect(:put, fn _url, body, headers, _opts ->
        # Verify body is properly encoded
        decoded = Jason.decode!(body)
        assert decoded["nested"]["data"] == "value"
        assert decoded["array"] == [1, 2, 3]

        assert {"Content-Type", "application/json"} in headers
        {:ok, %{status_code: 200, body: %{"updated" => true}}}
      end)

      complex_body = %{
        nested: %{data: "value"},
        array: [1, 2, 3],
        boolean: true
      }

      assert {:ok, %{status_code: 200}} =
               Http.put("https://api.example.com/resource/123", complex_body)
    end

    test "middleware errors are properly propagated" do
      # No mock expectation - will fail if called

      # Rate limiter prevents the call
      opts = [
        rate_limit: [
          # No requests allowed
          requests_per_second: 0,
          burst_capacity: 0
        ]
      ]

      assert {:error, :rate_limited} =
               Http.get("https://api.example.com/test", [], opts)
    end
  end

  describe "error scenarios" do
    test "handles timeout errors with retry" do
      attempt = :counters.new(1, [])

      WandererNotifier.HTTPMock
      |> expect(:get, 3, fn _url, _headers, _opts ->
        count = :counters.add(attempt, 1, 1)

        if count < 3 do
          {:error, :timeout}
        else
          {:ok, %{status_code: 200, body: "finally!"}}
        end
      end)

      # Should retry timeouts and eventually succeed
      assert {:ok, %{status_code: 200, body: "finally!"}} =
               Http.get("https://api.example.com/slow", [],
                 retry_count: 3,
                 retry_delay: 10
               )
    end

    test "handles network errors" do
      WandererNotifier.HTTPMock
      |> expect(:get, 1, fn _url, _headers, _opts ->
        {:error, :nxdomain}
      end)

      assert {:error, :nxdomain} =
               Http.get("https://nonexistent.example.com/api", [], retry_count: 0)
    end

    test "handles malformed responses" do
      WandererNotifier.HTTPMock
      |> expect(:get, fn _url, _headers, _opts ->
        {:ok, %{status_code: 200, body: "not json"}}
      end)

      # When decode_json is false, should return raw body
      assert {:ok, %{status_code: 200, body: "not json"}} =
               Http.get("https://api.example.com/text", [], decode_json: false)
    end
  end
end
