defmodule WandererNotifier.Infrastructure.Http.Middleware.TelemetryTest do
  @moduledoc """
  Tests for the Telemetry middleware that tracks HTTP request metrics.
  """
  use ExUnit.Case, async: true

  alias WandererNotifier.Infrastructure.Http.Middleware.Telemetry

  setup do
    # Attach test handler to telemetry events
    handler_id = "test-handler-#{System.unique_integer()}"

    :telemetry.attach_many(
      handler_id,
      [
        [:wanderer_notifier, :http, :request, :start],
        [:wanderer_notifier, :http, :request, :stop],
        [:wanderer_notifier, :http, :request, :exception]
      ],
      &__MODULE__.handle_event/4,
      %{test_pid: self()}
    )

    on_exit(fn -> :telemetry.detach(handler_id) end)

    :ok
  end

  describe "call/2" do
    test "emits start and stop events for successful requests" do
      request = %{
        method: :get,
        url: "https://api.example.com/test",
        headers: [],
        body: "",
        options: [service: :esi]
      }

      next = fn _req ->
        # Simulate some processing time
        Process.sleep(10)
        {:ok, %{status_code: 200, body: "success"}}
      end

      assert {:ok, %{status_code: 200}} = Telemetry.call(request, next)

      # Verify start event
      assert_receive {:telemetry_event, [:wanderer_notifier, :http, :request, :start],
                      measurements, metadata}

      assert measurements.system_time > 0
      assert metadata.method == :get
      assert metadata.url == "https://api.example.com/test"
      assert metadata.service == :esi

      # Verify stop event
      assert_receive {:telemetry_event, [:wanderer_notifier, :http, :request, :stop],
                      measurements, metadata}

      assert measurements.duration > 0
      assert metadata.method == :get
      assert metadata.url == "https://api.example.com/test"
      assert metadata.service == :esi
      assert metadata.status_code == 200
    end

    test "emits exception event for errors" do
      request = %{
        method: :post,
        url: "https://api.example.com/error",
        headers: [],
        body: "{}",
        options: [service: :license]
      }

      next = fn _req ->
        {:error, :timeout}
      end

      assert {:error, :timeout} = Telemetry.call(request, next)

      # Verify start event
      assert_receive {:telemetry_event, [:wanderer_notifier, :http, :request, :start], _, _}

      # Verify exception event
      assert_receive {:telemetry_event, [:wanderer_notifier, :http, :request, :exception],
                      measurements, metadata}

      assert measurements.duration > 0
      assert metadata.method == :post
      assert metadata.url == "https://api.example.com/error"
      assert metadata.service == :license
      assert metadata.error == :timeout
    end

    test "handles missing service in options" do
      request = %{
        method: :get,
        url: "https://api.example.com/test",
        headers: [],
        body: "",
        options: []
      }

      next = fn _req -> {:ok, %{status_code: 200, body: "ok"}} end

      assert {:ok, _} = Telemetry.call(request, next)

      assert_receive {:telemetry_event, _, _, metadata}
      assert metadata.service == :unknown
    end

    test "includes all HTTP methods" do
      methods = [:get, :post, :put, :patch, :delete, :head, :options]

      for method <- methods do
        request = %{
          method: method,
          url: "https://api.example.com/#{method}",
          headers: [],
          body: "",
          options: []
        }

        next = fn _req -> {:ok, %{status_code: 200, body: "ok"}} end

        assert {:ok, _} = Telemetry.call(request, next)

        assert_receive {:telemetry_event, [:wanderer_notifier, :http, :request, :start], _,
                        metadata}

        assert metadata.method == method
      end
    end

    test "measures accurate duration" do
      request = %{
        method: :get,
        url: "https://api.example.com/slow",
        headers: [],
        body: "",
        options: []
      }

      # milliseconds
      delay = 50

      next = fn _req ->
        Process.sleep(delay)
        {:ok, %{status_code: 200, body: "slow response"}}
      end

      assert {:ok, _} = Telemetry.call(request, next)

      assert_receive {:telemetry_event, [:wanderer_notifier, :http, :request, :stop],
                      measurements, _}

      # Duration should be at least the delay (in nanoseconds)
      assert measurements.duration >= delay * 1_000_000
    end

    test "handles non-200 status codes" do
      statuses = [400, 401, 403, 404, 429, 500, 502, 503]

      for status <- statuses do
        request = %{
          method: :get,
          url: "https://api.example.com/status/#{status}",
          headers: [],
          body: "",
          options: []
        }

        next = fn _req -> {:ok, %{status_code: status, body: "error"}} end

        assert {:ok, _} = Telemetry.call(request, next)

        assert_receive {:telemetry_event, [:wanderer_notifier, :http, :request, :stop], _,
                        metadata}

        assert metadata.status_code == status
      end
    end

    test "propagates request through middleware chain" do
      request = %{
        method: :get,
        url: "https://api.example.com/test",
        headers: [{"x-custom", "header"}],
        body: "",
        options: [custom: :option]
      }

      next = fn req ->
        # Verify request is passed through unchanged
        assert req.method == :get
        assert req.url == "https://api.example.com/test"
        assert {"x-custom", "header"} in req.headers
        assert req.options[:custom] == :option
        {:ok, %{status_code: 200, body: "success"}}
      end

      assert {:ok, _} = Telemetry.call(request, next)
    end

    test "handles exceptions raised in next function" do
      request = %{
        method: :get,
        url: "https://api.example.com/crash",
        headers: [],
        body: "",
        options: []
      }

      next = fn _req ->
        raise "Simulated crash"
      end

      assert_raise RuntimeError, "Simulated crash", fn ->
        Telemetry.call(request, next)
      end

      # Should still emit start event
      assert_receive {:telemetry_event, [:wanderer_notifier, :http, :request, :start], _, _}

      # Exception event might not be emitted for raised exceptions
      # This depends on implementation details
    end
  end

  # Helper function to handle telemetry events in tests
  def handle_event(event, measurements, metadata, %{test_pid: pid}) do
    send(pid, {:telemetry_event, event, measurements, metadata})
  end
end
