defmodule WandererNotifier.Infrastructure.Http.Middleware.CircuitBreakerTest do
  @moduledoc """
  Tests for the CircuitBreaker middleware that prevents cascading failures.
  """
  # Circuit breaker maintains state
  use ExUnit.Case, async: false

  alias WandererNotifier.Infrastructure.Http.Middleware.CircuitBreaker

  setup do
    # Reset circuit breaker state between tests
    :ets.delete_all_objects(:circuit_breaker_states)
    :ok
  end

  describe "call/2 - closed state" do
    test "allows requests through in closed state" do
      request = build_request("https://api.example.com/healthy")
      next = fn _req -> {:ok, %{status_code: 200, body: "ok"}} end

      # Multiple successful requests
      for _ <- 1..10 do
        assert {:ok, %{status_code: 200}} = CircuitBreaker.call(request, next)
      end
    end

    test "remains closed with occasional errors below threshold" do
      request = build_request("https://api.example.com/mostly-healthy")
      call_count = :counters.new(1, [])

      next = fn _req ->
        count = :counters.add(call_count, 1, 1)
        # Fail every 5th request (20% error rate)
        if rem(count, 5) == 0 do
          {:error, :timeout}
        else
          {:ok, %{status_code: 200, body: "ok"}}
        end
      end

      # Make 20 requests
      results =
        for _ <- 1..20 do
          CircuitBreaker.call(request, next)
        end

      # Should have ~4 errors and ~16 successes
      errors = Enum.count(results, &match?({:error, _}, &1))
      # Below 50% threshold
      assert errors > 0 and errors < 10

      # Circuit should still be closed
      assert {:ok, _} =
               CircuitBreaker.call(request, fn _ -> {:ok, %{status_code: 200, body: "ok"}} end)
    end
  end

  describe "call/2 - open state" do
    test "opens circuit after error threshold exceeded" do
      request =
        build_request("https://api.example.com/failing",
          failure_threshold: 3,
          threshold_window: 1000,
          reset_timeout: 100
        )

      next = fn _req -> {:error, :connection_failed} end

      # First 3 failures should go through
      assert {:error, :connection_failed} = CircuitBreaker.call(request, next)
      assert {:error, :connection_failed} = CircuitBreaker.call(request, next)
      assert {:error, :connection_failed} = CircuitBreaker.call(request, next)

      # Circuit should now be open
      assert {:error, :circuit_open} = CircuitBreaker.call(request, next)
      assert {:error, :circuit_open} = CircuitBreaker.call(request, next)
    end

    test "opens circuit on high error percentage" do
      request =
        build_request("https://api.example.com/flaky",
          failure_threshold: 5,
          threshold_window: 1000,
          error_threshold_percentage: 50
        )

      call_count = :counters.new(1, [])

      next = fn _req ->
        count = :counters.add(call_count, 1, 1)
        # Fail 60% of requests
        if count <= 6 do
          {:error, :internal_error}
        else
          {:ok, %{status_code: 200, body: "ok"}}
        end
      end

      # Make 10 requests
      for _ <- 1..10 do
        CircuitBreaker.call(request, next)
      end

      # Circuit should be open due to high error rate
      assert {:error, :circuit_open} = CircuitBreaker.call(request, next)
    end

    test "different hosts have independent circuits" do
      failing_request =
        build_request("https://failing.example.com/api",
          failure_threshold: 2
        )

      healthy_request =
        build_request("https://healthy.example.com/api",
          failure_threshold: 2
        )

      failing_next = fn _req -> {:error, :timeout} end
      healthy_next = fn _req -> {:ok, %{status_code: 200, body: "ok"}} end

      # Trip circuit for failing host
      assert {:error, :timeout} = CircuitBreaker.call(failing_request, failing_next)
      assert {:error, :timeout} = CircuitBreaker.call(failing_request, failing_next)
      assert {:error, :circuit_open} = CircuitBreaker.call(failing_request, failing_next)

      # Healthy host should still work
      assert {:ok, %{status_code: 200}} = CircuitBreaker.call(healthy_request, healthy_next)
    end
  end

  describe "call/2 - half-open state" do
    test "transitions to half-open after reset timeout" do
      request =
        build_request("https://api.example.com/recovering",
          failure_threshold: 2,
          # 50ms
          reset_timeout: 50
        )

      # Trip the circuit
      failing_next = fn _req -> {:error, :timeout} end
      assert {:error, :timeout} = CircuitBreaker.call(request, failing_next)
      assert {:error, :timeout} = CircuitBreaker.call(request, failing_next)
      assert {:error, :circuit_open} = CircuitBreaker.call(request, failing_next)

      # Wait for reset timeout
      Process.sleep(60)

      # Should allow one test request (half-open)
      success_next = fn _req -> {:ok, %{status_code: 200, body: "recovered"}} end
      assert {:ok, %{status_code: 200}} = CircuitBreaker.call(request, success_next)

      # Circuit should be closed again
      assert {:ok, %{status_code: 200}} = CircuitBreaker.call(request, success_next)
    end

    test "returns to open state if test request fails" do
      request =
        build_request("https://api.example.com/still-failing",
          failure_threshold: 2,
          reset_timeout: 50
        )

      failing_next = fn _req -> {:error, :still_broken} end

      # Trip the circuit
      assert {:error, :still_broken} = CircuitBreaker.call(request, failing_next)
      assert {:error, :still_broken} = CircuitBreaker.call(request, failing_next)
      assert {:error, :circuit_open} = CircuitBreaker.call(request, failing_next)

      # Wait for reset timeout
      Process.sleep(60)

      # Test request fails
      assert {:error, :still_broken} = CircuitBreaker.call(request, failing_next)

      # Should be open again immediately
      assert {:error, :circuit_open} = CircuitBreaker.call(request, failing_next)
    end

    test "requires multiple successes to fully close" do
      request =
        build_request("https://api.example.com/gradual-recovery",
          failure_threshold: 2,
          reset_timeout: 50,
          # Need 3 successes to close
          success_threshold: 3
        )

      # Trip the circuit
      failing_next = fn _req -> {:error, :down} end
      assert {:error, :down} = CircuitBreaker.call(request, failing_next)
      assert {:error, :down} = CircuitBreaker.call(request, failing_next)
      assert {:error, :circuit_open} = CircuitBreaker.call(request, failing_next)

      # Wait for reset timeout
      Process.sleep(60)

      success_next = fn _req -> {:ok, %{status_code: 200, body: "ok"}} end

      # Need 3 successful requests to fully close
      # 1
      assert {:ok, _} = CircuitBreaker.call(request, success_next)
      # 2
      assert {:ok, _} = CircuitBreaker.call(request, success_next)
      # 3
      assert {:ok, _} = CircuitBreaker.call(request, success_next)

      # Now fully closed, can handle multiple requests
      for _ <- 1..10 do
        assert {:ok, _} = CircuitBreaker.call(request, success_next)
      end
    end
  end

  describe "error handling" do
    test "counts different error types" do
      request =
        build_request("https://api.example.com/various-errors",
          failure_threshold: 5
        )

      errors = [:timeout, :connection_refused, :dns_error, :ssl_error, {:http_error, 500}]
      error_index = :counters.new(1, [])

      next = fn _req ->
        index = :counters.add(error_index, 1, 1)
        {:error, Enum.at(errors, rem(index - 1, length(errors)))}
      end

      # All error types should count toward failure threshold
      for _ <- 1..5 do
        assert {:error, _} = CircuitBreaker.call(request, next)
      end

      # Circuit should be open
      assert {:error, :circuit_open} = CircuitBreaker.call(request, next)
    end

    test "doesn't count client errors as failures" do
      request =
        build_request("https://api.example.com/client-errors",
          failure_threshold: 3
        )

      next = fn _req -> {:ok, %{status_code: 400, body: %{"error" => "bad request"}}} end

      # Client errors (4xx) shouldn't trip the circuit
      for _ <- 1..10 do
        assert {:ok, %{status_code: 400}} = CircuitBreaker.call(request, next)
      end

      # Circuit should still be closed
      success_next = fn _req -> {:ok, %{status_code: 200, body: "ok"}} end
      assert {:ok, _} = CircuitBreaker.call(request, success_next)
    end

    test "counts 5xx errors as failures" do
      request =
        build_request("https://api.example.com/server-errors",
          failure_threshold: 3
        )

      statuses = [500, 502, 503, 504]
      status_index = :counters.new(1, [])

      next = fn _req ->
        index = :counters.add(status_index, 1, 1)
        status = Enum.at(statuses, rem(index - 1, length(statuses)))
        {:ok, %{status_code: status, body: "server error"}}
      end

      # Server errors should count as failures
      assert {:ok, %{status_code: 500}} = CircuitBreaker.call(request, next)
      assert {:ok, %{status_code: 502}} = CircuitBreaker.call(request, next)
      assert {:ok, %{status_code: 503}} = CircuitBreaker.call(request, next)

      # Circuit should be open
      assert {:error, :circuit_open} = CircuitBreaker.call(request, next)
    end
  end

  describe "configuration" do
    test "uses default configuration when not specified" do
      request = %{
        method: :get,
        url: "https://api.example.com/defaults",
        headers: [],
        body: "",
        # No circuit_breaker config
        options: []
      }

      # Should use sensible defaults and still work
      next = fn _req -> {:ok, %{status_code: 200, body: "ok"}} end
      assert {:ok, _} = CircuitBreaker.call(request, next)
    end

    test "respects custom configuration" do
      request =
        build_request("https://api.example.com/custom",
          # Trip after 1 failure
          failure_threshold: 1,
          # 10ms reset
          reset_timeout: 10,
          # 100ms window
          threshold_window: 100,
          # 1 success to close
          success_threshold: 1
        )

      # Single failure should trip
      failing_next = fn _req -> {:error, :boom} end
      assert {:error, :boom} = CircuitBreaker.call(request, failing_next)
      assert {:error, :circuit_open} = CircuitBreaker.call(request, failing_next)

      # Quick reset
      Process.sleep(15)

      # Single success should close
      success_next = fn _req -> {:ok, %{status_code: 200, body: "ok"}} end
      assert {:ok, _} = CircuitBreaker.call(request, success_next)
      assert {:ok, _} = CircuitBreaker.call(request, success_next)
    end
  end

  describe "concurrent access" do
    test "handles concurrent requests safely" do
      request =
        build_request("https://api.example.com/concurrent",
          failure_threshold: 10
        )

      # Mix of successes and failures
      next = fn _req ->
        if :rand.uniform() > 0.3 do
          {:ok, %{status_code: 200, body: "ok"}}
        else
          {:error, :random_failure}
        end
      end

      # Launch many concurrent requests
      tasks =
        for _ <- 1..50 do
          Task.async(fn ->
            Process.sleep(:rand.uniform(10))
            CircuitBreaker.call(request, next)
          end)
        end

      results = Task.await_many(tasks)

      # Should have mix of results without crashes
      successes = Enum.count(results, &match?({:ok, _}, &1))
      errors = Enum.count(results, &match?({:error, _}, &1))

      assert successes + errors == 50
    end
  end

  # Helper function to build request with circuit breaker config
  defp build_request(url, config \\ []) do
    %{
      method: :get,
      url: url,
      headers: [],
      body: "",
      options: [
        circuit_breaker:
          Keyword.merge(
            [
              failure_threshold: 5,
              reset_timeout: 1000,
              threshold_window: 5000,
              success_threshold: 2,
              error_threshold_percentage: 50
            ],
            config
          )
      ]
    }
  end
end
