defmodule WandererNotifier.Http.Middleware.TelemetryTest do
  use ExUnit.Case, async: true

  alias WandererNotifier.Http.Middleware.Telemetry

  # Mock telemetry events capture
  setup do
    # Capture telemetry events during tests
    test_pid = self()

    :telemetry.attach_many(
      "test-telemetry-events",
      [
        [:wanderer_notifier, :http, :request_start],
        [:wanderer_notifier, :http, :request_finish],
        [:wanderer_notifier, :http, :request_error],
        [:wanderer_notifier, :http, :request_exception]
      ],
      fn event, measurements, metadata, _config ->
        send(test_pid, {:telemetry_event, event, measurements, metadata})
      end,
      nil
    )

    on_exit(fn ->
      :telemetry.detach("test-telemetry-events")
    end)

    :ok
  end

  describe "call/2" do
    test "emits telemetry events for successful request" do
      request = build_request()

      next = fn _req ->
        {:ok,
         %{status_code: 200, body: "success", headers: [{"content-type", "application/json"}]}}
      end

      assert {:ok, %{status_code: 200, body: "success"}} = Telemetry.call(request, next)

      # Should receive request start event
      assert_receive {:telemetry_event, [:wanderer_notifier, :http, :request_start],
                      start_measurements, start_metadata}

      assert %{timestamp: _, request_size_bytes: size} = start_measurements
      assert is_integer(size) and size > 0
      assert %{method: :get, host: "api.example.com", service: "api.example.com"} = start_metadata

      # Should receive request finish event
      assert_receive {:telemetry_event, [:wanderer_notifier, :http, :request_finish],
                      finish_measurements, finish_metadata}

      assert %{timestamp: _, duration_ms: duration, response_size_bytes: resp_size} =
               finish_measurements

      assert is_integer(duration) and duration >= 0
      assert is_integer(resp_size) and resp_size > 0
      assert %{status_code: 200, status_class: "2xx"} = finish_metadata
    end

    test "emits telemetry events for failed request" do
      request = build_request()
      next = fn _req -> {:error, :timeout} end

      assert {:error, :timeout} = Telemetry.call(request, next)

      # Should receive request start event
      assert_receive {:telemetry_event, [:wanderer_notifier, :http, :request_start],
                      _start_measurements, _start_metadata}

      # Should receive request error event
      assert_receive {:telemetry_event, [:wanderer_notifier, :http, :request_error],
                      error_measurements, error_metadata}

      assert %{timestamp: _, duration_ms: duration} = error_measurements
      assert is_integer(duration) and duration >= 0
      assert %{error_type: "timeout", error: "timeout"} = error_metadata
    end

    test "emits telemetry events for HTTP error response" do
      request = build_request()
      next = fn _req -> {:error, {:http_error, 500, "server error"}} end

      assert {:error, {:http_error, 500, "server error"}} = Telemetry.call(request, next)

      # Should receive request error event
      assert_receive {:telemetry_event, [:wanderer_notifier, :http, :request_error],
                      _error_measurements, error_metadata}

      assert %{error_type: "http_5xx", error: "HTTP 500"} = error_metadata
    end

    test "emits telemetry events for request exception" do
      request = build_request()
      next = fn _req -> raise "Something went wrong" end

      assert_raise RuntimeError, "Something went wrong", fn ->
        Telemetry.call(request, next)
      end

      # Should receive request exception event
      assert_receive {:telemetry_event, [:wanderer_notifier, :http, :request_exception],
                      exception_measurements, exception_metadata}

      assert %{timestamp: _, duration_ms: duration} = exception_measurements
      assert is_integer(duration) and duration >= 0
      assert %{error_type: "exception"} = exception_metadata
      assert exception_metadata.exception =~ "RuntimeError"
    end

    test "handles process exit during request" do
      request = build_request()
      next = fn _req -> exit(:normal) end

      assert catch_exit(Telemetry.call(request, next)) == :normal

      # Should receive request exception event for exit
      assert_receive {:telemetry_event, [:wanderer_notifier, :http, :request_exception],
                      _exception_measurements, exception_metadata}

      assert %{error_type: "exception", exception: "Exit: :normal"} = exception_metadata
    end

    test "includes custom service name when provided" do
      request = build_request(service_name: "external_api")
      next = fn _req -> {:ok, %{status_code: 200, body: "success", headers: []}} end

      Telemetry.call(request, next)

      assert_receive {:telemetry_event, [:wanderer_notifier, :http, :request_start],
                      _start_measurements, start_metadata}

      assert %{service: "external_api"} = start_metadata
    end

    test "includes custom metadata when provided" do
      custom_metadata = %{team: "backend", feature: "killmails"}
      request = build_request(custom_metadata: custom_metadata)
      next = fn _req -> {:ok, %{status_code: 200, body: "success", headers: []}} end

      Telemetry.call(request, next)

      assert_receive {:telemetry_event, [:wanderer_notifier, :http, :request_start],
                      _start_measurements, start_metadata}

      assert %{team: "backend", feature: "killmails"} = start_metadata
    end

    test "calculates request size correctly" do
      request = build_request([], "https://api.example.com/test", "test body")
      next = fn _req -> {:ok, %{status_code: 200, body: "success", headers: []}} end

      Telemetry.call(request, next)

      assert_receive {:telemetry_event, [:wanderer_notifier, :http, :request_start],
                      start_measurements, _start_metadata}

      assert %{request_size_bytes: size} = start_measurements
      # Should include body size, headers, URL, and method
      assert size > byte_size("test body")
    end

    test "calculates response size when enabled" do
      request = build_request(track_response_size: true)
      response_body = "this is a response body"

      next = fn _req ->
        {:ok, %{status_code: 200, body: response_body, headers: [{"content-type", "text/plain"}]}}
      end

      Telemetry.call(request, next)

      assert_receive {:telemetry_event, [:wanderer_notifier, :http, :request_finish],
                      finish_measurements, _finish_metadata}

      assert %{response_size_bytes: size} = finish_measurements
      # Should include body size and headers
      assert size >= byte_size(response_body)
    end

    test "handles different status code classes correctly" do
      test_cases = [
        {200, "2xx"},
        {301, "3xx"},
        {404, "4xx"},
        {500, "5xx"},
        {999, "unknown"}
      ]

      for {status_code, expected_class} <- test_cases do
        request = build_request()
        next = fn _req -> {:ok, %{status_code: status_code, body: "response", headers: []}} end

        Telemetry.call(request, next)

        assert_receive {:telemetry_event, [:wanderer_notifier, :http, :request_finish],
                        _finish_measurements, finish_metadata}

        assert %{status_class: ^expected_class} = finish_metadata
      end
    end

    test "categorizes different error types correctly" do
      error_cases = [
        {:timeout, "timeout"},
        {:connect_timeout, "connect_timeout"},
        {:econnrefused, "connection_refused"},
        {:ehostunreach, "host_unreachable"},
        {:enetunreach, "network_unreachable"},
        {:econnreset, "connection_reset"},
        {{:circuit_breaker_open, "Circuit is open"}, "circuit_breaker_open"},
        {{:rate_limited, "Too many requests"}, "rate_limited"},
        {{:http_error, 404, "Not found"}, "http_4xx"},
        {{:http_error, 500, "Server error"}, "http_5xx"},
        {:unknown_error, "unknown"}
      ]

      for {error, expected_type} <- error_cases do
        request = build_request()
        next = fn _req -> {:error, error} end

        Telemetry.call(request, next)

        assert_receive {:telemetry_event, [:wanderer_notifier, :http, :request_error],
                        _error_measurements, error_metadata}

        assert %{error_type: ^expected_type} = error_metadata
      end
    end

    test "extracts host correctly from various URL formats" do
      test_cases = [
        {"https://api.example.com/path", "api.example.com"},
        {"http://test.com", "test.com"},
        {"https://subdomain.domain.com/path?query=1", "subdomain.domain.com"},
        {"invalid-url", "unknown"}
      ]

      next = fn _req -> {:ok, %{status_code: 200, body: "success", headers: []}} end

      for {url, expected_host} <- test_cases do
        request = build_request([], url)
        Telemetry.call(request, next)

        assert_receive {:telemetry_event, [:wanderer_notifier, :http, :request_start],
                        _start_measurements, start_metadata}

        assert %{host: ^expected_host} = start_metadata
      end
    end

    test "masks sensitive information in URLs" do
      request =
        build_request([], "https://api.example.com/users?token=secret123&auth=key456#fragment")

      next = fn _req -> {:ok, %{status_code: 200, body: "success", headers: []}} end

      Telemetry.call(request, next)

      assert_receive {:telemetry_event, [:wanderer_notifier, :http, :request_start],
                      _start_measurements, start_metadata}

      # URL should not contain query params or fragments
      assert start_metadata.url == "https://api.example.com/users"
      refute String.contains?(start_metadata.url, "token")
      refute String.contains?(start_metadata.url, "auth")
      refute String.contains?(start_metadata.url, "fragment")
    end

    test "generates unique request IDs" do
      request = build_request()
      next = fn _req -> {:ok, %{status_code: 200, body: "success", headers: []}} end

      # Make multiple requests
      Telemetry.call(request, next)
      Telemetry.call(request, next)

      # Collect request IDs
      assert_receive {:telemetry_event, [:wanderer_notifier, :http, :request_start], _m1,
                      metadata1}

      assert_receive {:telemetry_event, [:wanderer_notifier, :http, :request_start], _m2,
                      metadata2}

      # Request IDs should be different
      assert metadata1.request_id != metadata2.request_id
      assert is_binary(metadata1.request_id)
      assert is_binary(metadata2.request_id)
    end

    test "handles JSON body size calculation" do
      json_body = %{test: "data", nested: %{key: "value"}}
      request = build_request([], "https://api.example.com/test", json_body)
      next = fn _req -> {:ok, %{status_code: 200, body: "success", headers: []}} end

      Telemetry.call(request, next)

      assert_receive {:telemetry_event, [:wanderer_notifier, :http, :request_start],
                      start_measurements, _start_metadata}

      assert %{request_size_bytes: size} = start_measurements

      expected_json_size = json_body |> Jason.encode!() |> byte_size()
      assert size > expected_json_size
    end

    test "handles response with JSON body size calculation" do
      request = build_request(track_response_size: true)
      json_response = %{result: "success", data: [1, 2, 3]}

      next = fn _req ->
        {:ok, %{status_code: 200, body: json_response, headers: []}}
      end

      Telemetry.call(request, next)

      assert_receive {:telemetry_event, [:wanderer_notifier, :http, :request_finish],
                      finish_measurements, _finish_metadata}

      assert %{response_size_bytes: size} = finish_measurements

      expected_json_size = json_response |> Jason.encode!() |> byte_size()
      assert size >= expected_json_size
    end
  end

  # Helper functions for testing

  defp build_request(telemetry_options \\ [], url \\ "https://api.example.com/test", body \\ nil) do
    opts = if telemetry_options != [], do: [telemetry_options: telemetry_options], else: []

    %{
      method: :get,
      url: url,
      headers: [{"authorization", "Bearer token123"}],
      body: body,
      opts: opts
    }
  end
end
