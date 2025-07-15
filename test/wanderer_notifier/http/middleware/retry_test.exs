defmodule WandererNotifier.Http.Middleware.RetryTest do
  use ExUnit.Case, async: true

  alias WandererNotifier.Http.Middleware.Retry

  describe "call/2" do
    test "returns successful response without retry" do
      request = build_request()
      next = fn _req -> {:ok, %{status_code: 200, body: "success", headers: []}} end

      assert {:ok, %{status_code: 200, body: "success"}} = Retry.call(request, next)
    end

    test "retries on retryable HTTP status codes" do
      request = build_request()

      # First call returns 500, second returns 200
      agent = start_call_counter()

      next = fn _req ->
        count = increment_counter(agent)

        case count do
          1 -> {:ok, %{status_code: 500, body: "error", headers: []}}
          2 -> {:ok, %{status_code: 200, body: "success", headers: []}}
        end
      end

      assert {:ok, %{status_code: 200, body: "success"}} = Retry.call(request, next)
      assert get_counter(agent) == 2
    end

    test "retries on network errors" do
      request = build_request()

      # First call returns connection error, second succeeds
      agent = start_call_counter()

      next = fn _req ->
        count = increment_counter(agent)

        case count do
          1 -> {:error, :econnrefused}
          2 -> {:ok, %{status_code: 200, body: "success", headers: []}}
        end
      end

      assert {:ok, %{status_code: 200, body: "success"}} = Retry.call(request, next)
      assert get_counter(agent) == 2
    end

    test "respects max_attempts configuration" do
      request = build_request(max_attempts: 2)

      # Always returns an error
      agent = start_call_counter()

      next = fn _req ->
        increment_counter(agent)
        {:error, :timeout}
      end

      assert {:error, :timeout} = Retry.call(request, next)
      assert get_counter(agent) == 2
    end

    test "does not retry non-retryable errors" do
      request = build_request()

      agent = start_call_counter()

      next = fn _req ->
        increment_counter(agent)
        {:error, :some_other_error}
      end

      assert {:error, :some_other_error} = Retry.call(request, next)
      assert get_counter(agent) == 1
    end

    test "does not retry non-retryable HTTP status codes" do
      request = build_request()

      agent = start_call_counter()

      next = fn _req ->
        increment_counter(agent)
        {:ok, %{status_code: 404, body: "not found", headers: []}}
      end

      assert {:ok, %{status_code: 404, body: "not found"}} = Retry.call(request, next)
      assert get_counter(agent) == 1
    end

    test "respects custom retryable_status_codes" do
      request = build_request(retryable_status_codes: [404, 500])

      # First call returns 404 (now retryable), second returns 200
      agent = start_call_counter()

      next = fn _req ->
        count = increment_counter(agent)

        case count do
          1 -> {:ok, %{status_code: 404, body: "not found", headers: []}}
          2 -> {:ok, %{status_code: 200, body: "success", headers: []}}
        end
      end

      assert {:ok, %{status_code: 200, body: "success"}} = Retry.call(request, next)
      assert get_counter(agent) == 2
    end

    test "respects custom retryable_errors" do
      request = build_request(retryable_errors: [:custom_error])

      # First call returns custom error, second succeeds
      agent = start_call_counter()

      next = fn _req ->
        count = increment_counter(agent)

        case count do
          1 -> {:error, :custom_error}
          2 -> {:ok, %{status_code: 200, body: "success", headers: []}}
        end
      end

      assert {:ok, %{status_code: 200, body: "success"}} = Retry.call(request, next)
      assert get_counter(agent) == 2
    end

    test "handles HTTP error tuples" do
      request = build_request()

      # First call returns HTTP error tuple, second succeeds  
      agent = start_call_counter()

      next = fn _req ->
        count = increment_counter(agent)

        case count do
          1 -> {:error, {:http_error, 500, "internal error"}}
          2 -> {:ok, %{status_code: 200, body: "success", headers: []}}
        end
      end

      assert {:ok, %{status_code: 200, body: "success"}} = Retry.call(request, next)
      assert get_counter(agent) == 2
    end

    test "handles timeout tuple errors" do
      request = build_request()

      # First call returns timeout tuple, second succeeds
      agent = start_call_counter()

      next = fn _req ->
        count = increment_counter(agent)

        case count do
          1 -> {:error, {:timeout, "connection timeout"}}
          2 -> {:ok, %{status_code: 200, body: "success", headers: []}}
        end
      end

      assert {:ok, %{status_code: 200, body: "success"}} = Retry.call(request, next)
      assert get_counter(agent) == 2
    end

    test "uses exponential backoff with jitter" do
      request =
        build_request(
          max_attempts: 3,
          base_backoff: 100,
          jitter: true
        )

      # Always fails to test the retry delays
      agent = start_call_counter()

      next = fn _req ->
        increment_counter(agent)
        {:error, :timeout}
      end

      start_time = System.monotonic_time(:millisecond)
      {:error, :timeout} = Retry.call(request, next)
      end_time = System.monotonic_time(:millisecond)

      # Should have made 3 attempts with delays between them
      # Total time should be at least the sum of delays (100ms + 200ms = 300ms)
      assert get_counter(agent) == 3
      # Account for jitter and processing time
      assert end_time - start_time >= 250
    end
  end

  # Helper functions for testing

  defp build_request(retry_options \\ []) do
    opts = if retry_options != [], do: [retry_options: retry_options], else: []

    %{
      method: :get,
      url: "https://api.example.com/test",
      headers: [],
      body: nil,
      opts: opts
    }
  end

  defp start_call_counter do
    {:ok, agent} = Agent.start_link(fn -> 0 end)
    agent
  end

  defp increment_counter(agent) do
    Agent.get_and_update(agent, fn count ->
      new_count = count + 1
      {new_count, new_count}
    end)
  end

  defp get_counter(agent) do
    Agent.get(agent, & &1)
  end
end
