defmodule WandererNotifier.Infrastructure.Http.Middleware.RateLimiterTest do
  @moduledoc """
  Tests for the RateLimiter middleware that enforces request rate limits.
  """
  # Rate limiting is stateful
  use ExUnit.Case, async: false

  alias WandererNotifier.Infrastructure.Http.Middleware.RateLimiter

  setup do
    # Reset rate limiter state between tests if table exists
    # Hammer creates an ETS table with the module name
    if :ets.whereis(WandererNotifier.RateLimiter) != :undefined do
      :ets.delete_all_objects(WandererNotifier.RateLimiter)
    else
      # Create the ETS table if it doesn't exist (for testing)
      :ets.new(WandererNotifier.RateLimiter, [:set, :public, :named_table])
    end

    :ok
  end

  describe "call/2" do
    test "allows requests within rate limit" do
      request = %{
        method: :get,
        url: "https://api.example.com/test",
        headers: [],
        body: "",
        options: [
          rate_limit: [
            requests_per_second: 10,
            burst_capacity: 5
          ]
        ]
      }

      next = fn _req -> {:ok, %{status_code: 200, body: "ok"}} end

      # Make 5 requests (within burst capacity)
      for _ <- 1..5 do
        assert {:ok, %{status_code: 200}} = RateLimiter.call(request, next)
      end
    end

    test "blocks requests exceeding rate limit" do
      request = %{
        method: :get,
        url: "https://api.example.com/limited",
        headers: [],
        body: "",
        options: [
          rate_limit: [
            requests_per_second: 2,
            burst_capacity: 2
          ]
        ]
      }

      next = fn _req -> {:ok, %{status_code: 200, body: "ok"}} end

      # First 2 requests should succeed (burst capacity)
      assert {:ok, %{status_code: 200}} = RateLimiter.call(request, next)
      assert {:ok, %{status_code: 200}} = RateLimiter.call(request, next)

      # Third request should be rate limited
      assert {:error, :rate_limited} = RateLimiter.call(request, next)
    end

    test "respects per-host rate limiting" do
      base_options = [
        rate_limit: [
          requests_per_second: 2,
          burst_capacity: 2,
          per_host: true
        ]
      ]

      request1 = %{
        method: :get,
        url: "https://api1.example.com/test",
        headers: [],
        body: "",
        options: base_options
      }

      request2 = %{
        method: :get,
        url: "https://api2.example.com/test",
        headers: [],
        body: "",
        options: base_options
      }

      next = fn _req -> {:ok, %{status_code: 200, body: "ok"}} end

      # Each host should have its own rate limit
      assert {:ok, _} = RateLimiter.call(request1, next)
      assert {:ok, _} = RateLimiter.call(request1, next)
      assert {:error, :rate_limited} = RateLimiter.call(request1, next)

      # Different host should still be allowed
      assert {:ok, _} = RateLimiter.call(request2, next)
      assert {:ok, _} = RateLimiter.call(request2, next)
      assert {:error, :rate_limited} = RateLimiter.call(request2, next)
    end

    test "global rate limiting when per_host is false" do
      base_options = [
        rate_limit: [
          requests_per_second: 2,
          burst_capacity: 2,
          per_host: false
        ]
      ]

      request1 = %{
        method: :get,
        url: "https://api1.example.com/test",
        headers: [],
        body: "",
        options: base_options
      }

      request2 = %{
        method: :get,
        url: "https://api2.example.com/test",
        headers: [],
        body: "",
        options: base_options
      }

      next = fn _req -> {:ok, %{status_code: 200, body: "ok"}} end

      # Global limit applies across all hosts
      assert {:ok, _} = RateLimiter.call(request1, next)
      assert {:ok, _} = RateLimiter.call(request2, next)
      # Third request to any host should be limited
      assert {:error, :rate_limited} = RateLimiter.call(request1, next)
      assert {:error, :rate_limited} = RateLimiter.call(request2, next)
    end

    test "bypasses rate limiting when not configured" do
      request = %{
        method: :get,
        url: "https://api.example.com/unlimited",
        headers: [],
        body: "",
        # No rate_limit config
        options: []
      }

      next = fn _req -> {:ok, %{status_code: 200, body: "ok"}} end

      # Should allow unlimited requests
      for _ <- 1..100 do
        assert {:ok, %{status_code: 200}} = RateLimiter.call(request, next)
      end
    end

    test "refills tokens over time" do
      request = %{
        method: :get,
        url: "https://api.example.com/refill",
        headers: [],
        body: "",
        options: [
          rate_limit: [
            # 10 tokens per second
            requests_per_second: 10,
            burst_capacity: 2
          ]
        ]
      }

      next = fn _req -> {:ok, %{status_code: 200, body: "ok"}} end

      # Use burst capacity
      assert {:ok, _} = RateLimiter.call(request, next)
      assert {:ok, _} = RateLimiter.call(request, next)
      assert {:error, :rate_limited} = RateLimiter.call(request, next)

      # Wait for window to reset (Hammer uses fixed windows, not gradual refill)
      Process.sleep(1100)

      # Should be allowed again after window reset
      assert {:ok, _} = RateLimiter.call(request, next)
    end

    test "handles malformed URLs gracefully" do
      request = %{
        method: :get,
        url: "not a valid url",
        headers: [],
        body: "",
        options: [
          rate_limit: [
            requests_per_second: 10,
            burst_capacity: 5,
            per_host: true
          ]
        ]
      }

      next = fn _req -> {:ok, %{status_code: 200, body: "ok"}} end

      # Should still work with invalid URL
      assert {:ok, _} = RateLimiter.call(request, next)
    end

    test "different methods share the same rate limit" do
      base_request = %{
        method: :get,
        url: "https://api.example.com/resource",
        headers: [],
        body: "",
        options: [
          rate_limit: [
            requests_per_second: 2,
            burst_capacity: 3
          ]
        ]
      }

      next = fn _req -> {:ok, %{status_code: 200, body: "ok"}} end

      # Different HTTP methods share the rate limit
      assert {:ok, _} = RateLimiter.call(%{base_request | method: :get}, next)
      assert {:ok, _} = RateLimiter.call(%{base_request | method: :post}, next)
      assert {:ok, _} = RateLimiter.call(%{base_request | method: :put}, next)
      assert {:error, :rate_limited} = RateLimiter.call(%{base_request | method: :delete}, next)
    end

    test "concurrent requests respect rate limits" do
      request = %{
        method: :get,
        url: "https://api.example.com/concurrent",
        headers: [],
        body: "",
        options: [
          rate_limit: [
            requests_per_second: 10,
            burst_capacity: 5
          ]
        ]
      }

      next = fn _req ->
        # Simulate some work
        Process.sleep(10)
        {:ok, %{status_code: 200, body: "ok"}}
      end

      # Launch 10 concurrent requests
      tasks =
        for _ <- 1..10 do
          Task.async(fn -> RateLimiter.call(request, next) end)
        end

      results = Task.await_many(tasks)

      # Count successes and rate limited responses
      {successes, rate_limited} =
        Enum.split_with(results, fn
          {:ok, _} -> true
          {:error, :rate_limited} -> false
        end)

      # Should have exactly burst_capacity successes
      assert length(successes) == 5
      assert length(rate_limited) == 5
    end

    test "rate limiter state persists across calls" do
      request = %{
        method: :get,
        url: "https://api.example.com/persistent",
        headers: [],
        body: "",
        options: [
          rate_limit: [
            requests_per_second: 1,
            burst_capacity: 1
          ]
        ]
      }

      next = fn _req -> {:ok, %{status_code: 200, body: "ok"}} end

      # First call uses the token
      assert {:ok, _} = RateLimiter.call(request, next)

      # Immediate second call should be rate limited
      assert {:error, :rate_limited} = RateLimiter.call(request, next)

      # Even after creating new request struct
      new_request = Map.put(request, :headers, [{"new", "header"}])
      assert {:error, :rate_limited} = RateLimiter.call(new_request, next)
    end
  end

  describe "bucket key generation" do
    test "creates consistent keys for same host" do
      request1 = %{
        url: "https://api.example.com/path1",
        options: [rate_limit: [per_host: true]]
      }

      request2 = %{
        url: "https://api.example.com/path2",
        options: [rate_limit: [per_host: true]]
      }

      # Both should generate same bucket key
      key1 = RateLimiter.bucket_key(request1)
      key2 = RateLimiter.bucket_key(request2)

      assert key1 == key2
    end

    test "creates different keys for different hosts" do
      request1 = %{
        url: "https://api1.example.com/path",
        options: [rate_limit: [per_host: true]]
      }

      request2 = %{
        url: "https://api2.example.com/path",
        options: [rate_limit: [per_host: true]]
      }

      key1 = RateLimiter.bucket_key(request1)
      key2 = RateLimiter.bucket_key(request2)

      assert key1 != key2
    end

    test "creates same key for global rate limiting" do
      request1 = %{
        url: "https://api1.example.com/path",
        options: [rate_limit: [per_host: false]]
      }

      request2 = %{
        url: "https://api2.example.com/path",
        options: [rate_limit: [per_host: false]]
      }

      key1 = RateLimiter.bucket_key(request1)
      key2 = RateLimiter.bucket_key(request2)

      assert key1 == key2
      assert key1 == :global
    end
  end
end
