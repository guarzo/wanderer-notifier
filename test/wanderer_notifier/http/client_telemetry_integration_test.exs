defmodule WandererNotifier.Infrastructure.Http.ClientTelemetryIntegrationTest do
  use ExUnit.Case, async: true

  alias WandererNotifier.Infrastructure.Http.Client

  # Skip integration tests when running with mocks
  setup_all do
    case Application.get_env(:wanderer_notifier, :http_client) do
      WandererNotifier.HTTPMock ->
        {:ok, skip: true}

      _ ->
        {:ok, skip: false}
    end
  end

  # Mock telemetry events capture
  setup %{skip: skip} = context do
    if skip do
      {:ok, context}
    else
      # Capture telemetry events during tests
      test_pid = self()

      :telemetry.attach_many(
        "test-client-telemetry-events",
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
        :telemetry.detach("test-client-telemetry-events")
      end)

      {:ok, context}
    end
  end

  describe "HTTP Client with default telemetry middleware" do
    test "emits telemetry events for simple GET request", %{skip: skip} do
      if skip do
        {:skip, "Skipping integration test when using HTTP mocks"}
      else
        # This will fail because we're hitting a real URL, but telemetry should still be emitted
        assert {:error, _} = Client.get("https://httpbin.org/status/500")

        # Should receive request start event
        assert_receive {:telemetry_event, [:wanderer_notifier, :http, :request_start],
                        start_measurements, start_metadata}

        assert %{timestamp: _, request_size_bytes: size} = start_measurements
        assert is_integer(size) and size > 0
        assert %{method: :get, host: "httpbin.org", service: "httpbin.org"} = start_metadata

        # Should receive request error event (because of 500 status)
        assert_receive {:telemetry_event, [:wanderer_notifier, :http, :request_error],
                        error_measurements, error_metadata}

        assert %{timestamp: _, duration_ms: duration} = error_measurements
        assert is_integer(duration) and duration >= 0
        assert %{error_type: "http_5xx"} = error_metadata
      end
    end

    @tag :skip_with_mocks
    test "can override default middleware to exclude telemetry", %{skip: skip} do
      if skip do
        {:skip, "Skipping integration test when using HTTP mocks"}
      else
        # Override middleware to exclude telemetry
        assert {:error, _} = Client.get("https://httpbin.org/status/404", middlewares: [])

        # Should not receive any telemetry events
        refute_receive {:telemetry_event, _, _, _}, 100
      end
    end

    @tag :skip_with_mocks
    test "includes custom telemetry options in metadata", %{skip: skip} do
      if skip do
        {:skip, "Skipping integration test when using HTTP mocks"}
      else
        telemetry_options = [
          service_name: "test_service",
          custom_metadata: %{team: "test", env: "development"}
        ]

        assert {:error, _} =
                 Client.get("https://httpbin.org/status/500",
                   telemetry_options: telemetry_options
                 )

        # Should receive events with custom metadata
        assert_receive {:telemetry_event, [:wanderer_notifier, :http, :request_start],
                        _start_measurements, start_metadata}

        assert %{service: "test_service", team: "test", env: "development"} = start_metadata
      end
    end

    @tag :skip_with_mocks
    test "handles POST requests with body correctly", %{skip: skip} do
      if skip do
        {:skip, "Skipping integration test when using HTTP mocks"}
      else
        body = %{test: "data", timestamp: System.system_time()}

        assert {:error, _} = Client.post_json("https://httpbin.org/status/201", body)

        # Should receive request start with calculated body size
        assert_receive {:telemetry_event, [:wanderer_notifier, :http, :request_start],
                        start_measurements, start_metadata}

        assert %{request_size_bytes: size} = start_measurements
        # Size should include the JSON body
        json_size = body |> Jason.encode!() |> byte_size()
        assert size > json_size

        assert %{method: :post} = start_metadata
      end
    end

    @tag :skip_with_mocks
    test "maintains request ID consistency across events", %{skip: skip} do
      if skip do
        {:skip, "Skipping integration test when using HTTP mocks"}
      else
        assert {:error, _} = Client.get("https://httpbin.org/status/500")

        # Collect all events for this request
        events = collect_telemetry_events(2)

        # Extract request IDs
        request_ids =
          events
          |> Enum.map(fn {_event, _measurements, metadata} -> metadata.request_id end)
          |> Enum.uniq()

        # Should have exactly one unique request ID across all events
        assert length(request_ids) == 1
        assert [request_id] = request_ids
        assert is_binary(request_id)
      end
    end
  end

  # Helper function to collect multiple telemetry events
  defp collect_telemetry_events(count, events \\ [])
  defp collect_telemetry_events(0, events), do: Enum.reverse(events)

  defp collect_telemetry_events(count, events) do
    receive do
      {:telemetry_event, event, measurements, metadata} ->
        collect_telemetry_events(count - 1, [{event, measurements, metadata} | events])
    after
      1000 ->
        # Return what we have so far
        Enum.reverse(events)
    end
  end
end
