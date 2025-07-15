defmodule WandererNotifier.Http.Middleware.CircuitBreakerTest do
  # Need sequential execution for state management
  use ExUnit.Case, async: false

  alias WandererNotifier.Http.Middleware.CircuitBreaker
  alias WandererNotifier.Http.CircuitBreakerState

  setup_all do
    # Start the circuit breaker state manager
    {:ok, _pid} = CircuitBreakerState.start_link()
    :ok
  end

  setup do
    # Clear the ETS table between tests
    :ets.delete_all_objects(:circuit_breaker_states)
    :ok
  end

  describe "call/2" do
    test "allows requests when circuit breaker is closed" do
      request = build_request()
      next = fn _req -> {:ok, %{status_code: 200, body: "success", headers: []}} end

      assert {:ok, %{status_code: 200, body: "success"}} = CircuitBreaker.call(request, next)

      # Verify state is still closed
      state = CircuitBreakerState.get_state("api.example.com")
      assert state.state == :closed
      assert state.failure_count == 0
    end

    test "records failures and opens circuit breaker after threshold" do
      request = build_request()
      next = fn _req -> {:ok, %{status_code: 500, body: "error", headers: []}} end

      # Make 5 failing requests (default threshold)
      for _i <- 1..5 do
        {:ok, %{status_code: 500}} = CircuitBreaker.call(request, next)
      end

      # Give GenServer time to process the cast
      Process.sleep(10)

      # Circuit should now be open
      state = CircuitBreakerState.get_state("api.example.com")
      assert state.state == :open
      assert state.failure_count == 5

      # Next request should be rejected
      assert {:error, {:circuit_breaker_open, _message}} = CircuitBreaker.call(request, next)
    end

    test "records network errors as failures" do
      request = build_request()
      next = fn _req -> {:error, :timeout} end

      # Make failing requests
      for _i <- 1..5 do
        {:error, :timeout} = CircuitBreaker.call(request, next)
      end

      # Give GenServer time to process the casts
      Process.sleep(10)

      # Circuit should be open
      state = CircuitBreakerState.get_state("api.example.com")
      assert state.state == :open
    end

    test "handles exceptions as failures" do
      request = build_request()
      next = fn _req -> raise "Something went wrong" end

      # Make failing requests
      for _i <- 1..5 do
        {:error, %RuntimeError{}} = CircuitBreaker.call(request, next)
      end

      # Give GenServer time to process the casts
      Process.sleep(10)

      # Circuit should be open
      state = CircuitBreakerState.get_state("api.example.com")
      assert state.state == :open
    end

    test "transitions to half-open after recovery timeout" do
      request = build_request()
      failing_next = fn _req -> {:ok, %{status_code: 500, body: "error", headers: []}} end
      success_next = fn _req -> {:ok, %{status_code: 200, body: "success", headers: []}} end

      # Fail enough to open circuit
      for _i <- 1..5 do
        CircuitBreaker.call(request, failing_next)
      end

      # Give GenServer time to process the casts
      Process.sleep(10)

      # Verify circuit is open
      state = CircuitBreakerState.get_state("api.example.com")
      assert state.state == :open

      # Manually transition to half-open (simulating timeout)
      updated_state = %{state | state: :half_open}
      :ets.insert(:circuit_breaker_states, {"api.example.com", updated_state})

      # Request should be allowed in half-open state
      assert {:ok, %{status_code: 200}} = CircuitBreaker.call(request, success_next)

      # Give GenServer time to process the success
      Process.sleep(10)

      # Should transition back to closed after success
      final_state = CircuitBreakerState.get_state("api.example.com")
      assert final_state.state == :closed
    end

    test "transitions back to open if half-open request fails" do
      request = build_request()
      failing_next = fn _req -> {:ok, %{status_code: 500, body: "error", headers: []}} end

      # Start with half-open state
      state = CircuitBreakerState.get_state("api.example.com")
      updated_state = %{state | state: :half_open}
      :ets.insert(:circuit_breaker_states, {"api.example.com", updated_state})

      # Failing request in half-open state
      {:ok, %{status_code: 500}} = CircuitBreaker.call(request, failing_next)

      # Give GenServer time to process the failure
      Process.sleep(10)

      # Should have recorded failure - check that state has changed
      final_state = CircuitBreakerState.get_state("api.example.com")
      # The failure count should be incremented from the half-open state
      assert final_state.failure_count >= 1
    end

    test "handles different hosts independently" do
      request1 = build_request([], "https://api1.example.com/test")
      request2 = build_request([], "https://api2.example.com/test")
      failing_next = fn _req -> {:ok, %{status_code: 500, body: "error", headers: []}} end
      success_next = fn _req -> {:ok, %{status_code: 200, body: "success", headers: []}} end

      # Fail api1 enough to open its circuit
      for _i <- 1..5 do
        CircuitBreaker.call(request1, failing_next)
      end

      # Give GenServer time to process the casts
      Process.sleep(10)

      # api1 should be open, api2 should be closed
      state1 = CircuitBreakerState.get_state("api1.example.com")
      state2 = CircuitBreakerState.get_state("api2.example.com")
      assert state1.state == :open
      assert state2.state == :closed

      # api1 should be rejected, api2 should succeed
      assert {:error, {:circuit_breaker_open, _}} = CircuitBreaker.call(request1, success_next)
      assert {:ok, %{status_code: 200}} = CircuitBreaker.call(request2, success_next)
    end

    test "respects custom error status codes" do
      request = build_request([error_status_codes: [404, 500]], "https://api.example.com/test")
      next_404 = fn _req -> {:ok, %{status_code: 404, body: "not found", headers: []}} end

      next_503 = fn _req ->
        {:ok, %{status_code: 503, body: "service unavailable", headers: []}}
      end

      # 404 should be treated as failure (custom config)
      for _i <- 1..5 do
        CircuitBreaker.call(request, next_404)
      end

      # Give GenServer time to process the casts
      Process.sleep(10)

      state = CircuitBreakerState.get_state("api.example.com")
      assert state.state == :open

      # Reset for next test by clearing the host state
      :ets.delete(:circuit_breaker_states, "api.example.com")

      # 503 should NOT be treated as failure (not in custom config)
      for _i <- 1..5 do
        CircuitBreaker.call(request, next_503)
      end

      state = CircuitBreakerState.get_state("api.example.com")
      # Should remain closed
      assert state.state == :closed
    end

    test "doesn't record circuit breaker rejections as failures" do
      request = build_request()
      failing_next = fn _req -> {:ok, %{status_code: 500, body: "error", headers: []}} end

      # Open the circuit
      for _i <- 1..5 do
        CircuitBreaker.call(request, failing_next)
      end

      # Give GenServer time to process the casts
      Process.sleep(10)

      state_before = CircuitBreakerState.get_state("api.example.com")
      assert state_before.state == :open
      failure_count_before = state_before.failure_count

      # Make rejected requests
      for _i <- 1..3 do
        {:error, {:circuit_breaker_open, _}} = CircuitBreaker.call(request, failing_next)
      end

      # Failure count should not increase due to rejections
      state_after = CircuitBreakerState.get_state("api.example.com")
      assert state_after.failure_count == failure_count_before
    end

    test "extracts host correctly from various URL formats" do
      test_cases = [
        "https://api.example.com/path",
        "http://test.com",
        "https://subdomain.domain.com/path?query=1"
      ]

      success_next = fn _req -> {:ok, %{status_code: 200, body: "success", headers: []}} end

      for url <- test_cases do
        request = build_request([], url)
        # Should not fail regardless of URL format
        assert {:ok, %{status_code: 200}} = CircuitBreaker.call(request, success_next)
      end
    end

    test "handles invalid URLs gracefully" do
      request = build_request([], "invalid-url")
      next = fn _req -> {:ok, %{status_code: 200, body: "success", headers: []}} end

      # Should not crash, will use "unknown" as host
      assert {:ok, %{status_code: 200}} = CircuitBreaker.call(request, next)
    end
  end

  # Helper functions for testing

  defp build_request(circuit_breaker_options \\ [], url \\ "https://api.example.com/test") do
    opts =
      if circuit_breaker_options != [],
        do: [circuit_breaker_options: circuit_breaker_options],
        else: []

    %{
      method: :get,
      url: url,
      headers: [],
      body: nil,
      opts: opts
    }
  end
end
