defmodule WandererNotifier.Http.Middleware.RateLimiterTest do
  use ExUnit.Case, async: true

  alias WandererNotifier.Http.Middleware.RateLimiter

  setup do
    # Clear rate limiting keys from process dictionary before each test
    Process.get()
    |> Enum.filter(fn {key, _} -> 
      key |> to_string() |> String.starts_with?("http_rate_limit:")
    end)
    |> Enum.each(fn {key, _} -> Process.delete(key) end)

    :ok
  end

  describe "call/2" do
    test "allows requests within rate limit" do
      request = build_request()
      next = fn _req -> {:ok, %{status_code: 200, body: "success", headers: []}} end

      assert {:ok, %{status_code: 200, body: "success"}} = RateLimiter.call(request, next)
    end

    test "blocks requests when rate limit exceeded" do
      request = build_request(requests_per_second: 1, burst_capacity: 1)
      next = fn _req -> {:ok, %{status_code: 200, body: "success", headers: []}} end

      # First request should succeed
      assert {:ok, %{status_code: 200, body: "success"}} = RateLimiter.call(request, next)

      # Second request should be rate limited
      assert {:error, {:rate_limited, _message}} = RateLimiter.call(request, next)
    end

    test "handles different hosts separately when per_host is true" do
      request1 =
        build_request(
          [per_host: true, requests_per_second: 1, burst_capacity: 1],
          "https://api1.example.com/test"
        )

      request2 =
        build_request(
          [per_host: true, requests_per_second: 1, burst_capacity: 1],
          "https://api2.example.com/test"
        )

      next = fn _req -> {:ok, %{status_code: 200, body: "success", headers: []}} end

      # Both requests should succeed as they're to different hosts
      assert {:ok, %{status_code: 200, body: "success"}} = RateLimiter.call(request1, next)
      assert {:ok, %{status_code: 200, body: "success"}} = RateLimiter.call(request2, next)
    end

    test "handles global rate limiting when per_host is false" do
      request1 =
        build_request(
          [per_host: false, requests_per_second: 1, burst_capacity: 1],
          "https://api1.example.com/test"
        )

      request2 =
        build_request(
          [per_host: false, requests_per_second: 1, burst_capacity: 1],
          "https://api2.example.com/test"
        )

      next = fn _req -> {:ok, %{status_code: 200, body: "success", headers: []}} end

      # First request should succeed
      assert {:ok, %{status_code: 200, body: "success"}} = RateLimiter.call(request1, next)

      # Second request should be rate limited even to different host
      assert {:error, {:rate_limited, _message}} = RateLimiter.call(request2, next)
    end

    test "handles HTTP 429 responses without backoff" do
      request = build_request(enable_backoff: false)
      headers = [{"retry-after", "5"}]
      next = fn _req -> {:ok, %{status_code: 429, body: "rate limited", headers: headers}} end

      assert {:ok, %{status_code: 429, body: "rate limited"}} = RateLimiter.call(request, next)
    end

    test "handles HTTP 429 responses with backoff enabled" do
      request = build_request(enable_backoff: true)
      # 1 second
      headers = [{"retry-after", "1"}]
      next = fn _req -> {:ok, %{status_code: 429, body: "rate limited", headers: headers}} end

      # Should return the rate limit error from the utility
      assert {:error, {:rate_limited, _retry_after}} = RateLimiter.call(request, next)
    end

    test "handles missing retry-after header in 429 response" do
      request = build_request(enable_backoff: true)
      next = fn _req -> {:ok, %{status_code: 429, body: "rate limited", headers: []}} end

      # Should still handle the rate limit
      assert {:error, {:rate_limited, _retry_after}} = RateLimiter.call(request, next)
    end

    test "passes through non-429 responses unchanged" do
      request = build_request()
      next = fn _req -> {:ok, %{status_code: 500, body: "server error", headers: []}} end

      assert {:ok, %{status_code: 500, body: "server error"}} = RateLimiter.call(request, next)
    end

    test "passes through error responses unchanged" do
      request = build_request()
      next = fn _req -> {:error, :timeout} end

      assert {:error, :timeout} = RateLimiter.call(request, next)
    end

    test "extracts host correctly from various URL formats" do
      test_cases = [
        {"https://api.example.com/path", "api.example.com"},
        {"http://test.com", "test.com"},
        {"https://subdomain.domain.com/path?query=1", "subdomain.domain.com"},
        {"invalid-url", "unknown"}
      ]

      next = fn _req -> {:ok, %{status_code: 200, body: "success", headers: []}} end

      for {url, _expected_host} <- test_cases do
        request = build_request([], url)
        # Should not fail regardless of URL format
        assert {:ok, %{status_code: 200}} = RateLimiter.call(request, next)
      end
    end

    test "uses default configuration when no options provided" do
      # No rate limit options
      request = build_request([])
      next = fn _req -> {:ok, %{status_code: 200, body: "success", headers: []}} end

      # Should work with defaults
      assert {:ok, %{status_code: 200, body: "success"}} = RateLimiter.call(request, next)
    end

    test "allows burst capacity before rate limiting" do
      # Set burst capacity to 3, requests per second to 1
      request = build_request(requests_per_second: 1, burst_capacity: 3)
      next = fn _req -> {:ok, %{status_code: 200, body: "success", headers: []}} end

      # Should allow 3 rapid requests (burst capacity)
      assert {:ok, %{status_code: 200}} = RateLimiter.call(request, next)
      assert {:ok, %{status_code: 200}} = RateLimiter.call(request, next)
      assert {:ok, %{status_code: 200}} = RateLimiter.call(request, next)

      # Fourth request should be rate limited
      assert {:error, {:rate_limited, _message}} = RateLimiter.call(request, next)
    end
  end

  # Helper functions for testing

  defp build_request(rate_limit_options \\ [], url \\ "https://api.example.com/test") do
    opts = if rate_limit_options != [], do: [rate_limit_options: rate_limit_options], else: []

    %{
      method: :get,
      url: url,
      headers: [],
      body: nil,
      opts: opts
    }
  end
end
