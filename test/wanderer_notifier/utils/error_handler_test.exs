defmodule WandererNotifier.Shared.Utils.ErrorHandlerTest do
  use ExUnit.Case, async: true
  alias WandererNotifier.Shared.Utils.ErrorHandler

  describe "normalize_error/1" do
    test "converts string errors to atoms" do
      assert ErrorHandler.normalize_error({:error, "timeout"}) == {:error, :timeout}
      assert ErrorHandler.normalize_error({:error, "not found"}) == {:error, :not_found}

      assert ErrorHandler.normalize_error({:error, "Connection refused"}) ==
               {:error, :network_error}
    end

    test "preserves existing error tuples" do
      assert ErrorHandler.normalize_error({:error, :timeout}) == {:error, :timeout}

      assert ErrorHandler.normalize_error({:error, {:category, "details"}}) ==
               {:error, {:category, "details"}}
    end

    test "converts bare atoms to error tuples" do
      assert ErrorHandler.normalize_error(:timeout) == {:error, :timeout}
      assert ErrorHandler.normalize_error(:not_found) == {:error, :not_found}
    end

    test "handles :ok edge case" do
      assert ErrorHandler.normalize_error(:ok) == {:error, :unknown_error}
    end

    test "wraps unknown values" do
      assert ErrorHandler.normalize_error(123) == {:error, {:unknown_error, 123}}

      assert ErrorHandler.normalize_error("plain string") ==
               {:error, {:unknown_error, "plain string"}}
    end
  end

  describe "with_error_handling/1" do
    test "returns successful results unchanged" do
      assert ErrorHandler.with_error_handling(fn -> {:ok, "success"} end) == {:ok, "success"}
    end

    test "catches and formats exceptions" do
      result = ErrorHandler.with_error_handling(fn -> raise "oops" end)
      assert {:error, {:exception, %RuntimeError{message: "oops"}}} = result
    end

    test "catches exit signals" do
      result = ErrorHandler.with_error_handling(fn -> exit(:shutdown) end)
      assert {:error, {:exit, :shutdown}} = result
    end
  end

  describe "with_timeout/2" do
    test "returns result when completed within timeout" do
      result = ErrorHandler.with_timeout(fn -> {:ok, "done"} end, 100)
      assert result == {:ok, "done"}
    end

    test "returns timeout error when function exceeds timeout" do
      result =
        ErrorHandler.with_timeout(
          fn ->
            Process.sleep(150)
            {:ok, "done"}
          end,
          50
        )

      assert result == {:error, :timeout}
    end
  end

  describe "http_error_to_tuple/1" do
    test "maps common 4xx errors" do
      assert ErrorHandler.http_error_to_tuple(400) == {:error, :bad_request}
      assert ErrorHandler.http_error_to_tuple(401) == {:error, :unauthorized}
      assert ErrorHandler.http_error_to_tuple(403) == {:error, :forbidden}
      assert ErrorHandler.http_error_to_tuple(404) == {:error, :not_found}
      assert ErrorHandler.http_error_to_tuple(408) == {:error, :timeout}
      assert ErrorHandler.http_error_to_tuple(429) == {:error, :rate_limited}
    end

    test "maps common 5xx errors" do
      assert ErrorHandler.http_error_to_tuple(500) == {:error, :internal_server_error}
      assert ErrorHandler.http_error_to_tuple(502) == {:error, :bad_gateway}
      assert ErrorHandler.http_error_to_tuple(503) == {:error, :service_unavailable}
      assert ErrorHandler.http_error_to_tuple(504) == {:error, :gateway_timeout}
    end

    test "maps unknown errors generically" do
      assert ErrorHandler.http_error_to_tuple(418) == {:error, {:http_error, 418}}
      assert ErrorHandler.http_error_to_tuple(511) == {:error, {:http_error, 511}}
    end
  end

  describe "categorize_error/1" do
    test "categorizes network errors" do
      assert ErrorHandler.categorize_error(:timeout) == :network
      assert ErrorHandler.categorize_error(:connect_timeout) == :network
      assert ErrorHandler.categorize_error(:closed) == :network
      assert ErrorHandler.categorize_error(:network_error) == :network
    end

    test "categorizes auth errors" do
      assert ErrorHandler.categorize_error(:unauthorized) == :auth
      assert ErrorHandler.categorize_error(:forbidden) == :auth
      assert ErrorHandler.categorize_error(:invalid_token) == :auth
    end

    test "categorizes data errors" do
      assert ErrorHandler.categorize_error(:invalid_json) == :data
      assert ErrorHandler.categorize_error(:invalid_data) == :data
      assert ErrorHandler.categorize_error(:missing_fields) == :data
      assert ErrorHandler.categorize_error(:validation_error) == :data
    end

    test "categorizes service errors" do
      assert ErrorHandler.categorize_error(:service_unavailable) == :service
      assert ErrorHandler.categorize_error(:rate_limited) == :service
      assert ErrorHandler.categorize_error(:circuit_breaker_open) == :service
    end

    test "categorizes HTTP errors" do
      assert ErrorHandler.categorize_error({:http_error, 400}) == :client_error
      assert ErrorHandler.categorize_error({:http_error, 404}) == :client_error
      assert ErrorHandler.categorize_error({:http_error, 500}) == :server_error
      assert ErrorHandler.categorize_error({:http_error, 503}) == :server_error
    end

    test "extracts category from tagged tuples" do
      assert ErrorHandler.categorize_error({:validation, "details"}) == :validation
      assert ErrorHandler.categorize_error({:custom_category, %{}}) == :custom_category
    end

    test "returns unknown for unrecognized errors" do
      assert ErrorHandler.categorize_error("string") == :unknown
      assert ErrorHandler.categorize_error(123) == :unknown
    end
  end

  describe "format_error/1" do
    test "formats common error atoms" do
      assert ErrorHandler.format_error(:timeout) == "Operation timed out"
      assert ErrorHandler.format_error(:not_found) == "Resource not found"
      assert ErrorHandler.format_error(:unauthorized) == "Authentication required"
      assert ErrorHandler.format_error(:forbidden) == "Access denied"
      assert ErrorHandler.format_error(:rate_limited) == "Rate limit exceeded"
      assert ErrorHandler.format_error(:service_unavailable) == "Service temporarily unavailable"
      assert ErrorHandler.format_error(:network_error) == "Network connection error"
      assert ErrorHandler.format_error(:invalid_data) == "Invalid data provided"
    end

    test "formats HTTP errors" do
      assert ErrorHandler.format_error({:http_error, 404}) == "HTTP error: 404"
      assert ErrorHandler.format_error({:http_error, 500}) == "HTTP error: 500"
    end

    test "formats validation errors" do
      assert ErrorHandler.format_error({:validation_error, "name required"}) ==
               "Validation error: name required"
    end

    test "formats exceptions" do
      exception = %RuntimeError{message: "something went wrong"}

      assert ErrorHandler.format_error({:exception, exception}) ==
               "Unexpected error: something went wrong"
    end

    test "formats tagged errors" do
      assert ErrorHandler.format_error({:database_error, "connection lost"}) ==
               "Database error: \"connection lost\""
    end

    test "formats unknown errors" do
      assert ErrorHandler.format_error(:unknown_atom) == "Error: :unknown_atom"
      assert ErrorHandler.format_error(123) == "Error: 123"
    end
  end

  describe "enrich_error/2" do
    test "enriches simple atom errors" do
      assert ErrorHandler.enrich_error({:error, :not_found}, %{resource: "user", id: 123}) ==
               {:error, {:not_found, %{resource: "user", id: 123}}}
    end

    test "merges context with existing maps" do
      error = {:error, {:validation, %{field: "email"}}}
      context = %{user_id: 123}

      assert ErrorHandler.enrich_error(error, context) ==
               {:error, {:validation, %{field: "email", user_id: 123}}}
    end

    test "wraps non-map details" do
      error = {:error, {:category, "string details"}}
      context = %{user_id: 123}

      assert ErrorHandler.enrich_error(error, context) ==
               {:error, {:category, %{user_id: 123, details: "string details"}}}
    end

    test "handles unknown error formats" do
      error = {:error, "string error"}
      context = %{user_id: 123}

      assert ErrorHandler.enrich_error(error, context) ==
               {:error, {:enriched_error, %{user_id: 123, original: "string error"}}}
    end

    test "passes through non-error values unchanged" do
      assert ErrorHandler.enrich_error({:ok, "value"}, %{context: "data"}) == {:ok, "value"}
    end
  end

  describe "with_retry/2" do
    test "succeeds on first attempt" do
      counter = :counters.new(1, [])

      result =
        ErrorHandler.with_retry(
          fn ->
            :counters.add(counter, 1, 1)
            {:ok, "success"}
          end,
          max_attempts: 3
        )

      assert result == {:ok, "success"}
      assert :counters.get(counter, 1) == 1
    end

    test "retries on specified errors" do
      counter = :counters.new(1, [])

      result =
        ErrorHandler.with_retry(
          fn ->
            :counters.add(counter, 1, 1)
            count = :counters.get(counter, 1)

            if count < 3 do
              {:error, :timeout}
            else
              {:ok, "success"}
            end
          end,
          max_attempts: 5,
          retry_on: [:timeout],
          base_delay: 10
        )

      assert result == {:ok, "success"}
      assert :counters.get(counter, 1) == 3
    end

    test "stops retrying after max attempts" do
      counter = :counters.new(1, [])

      result =
        ErrorHandler.with_retry(
          fn ->
            :counters.add(counter, 1, 1)
            {:error, :timeout}
          end,
          max_attempts: 2,
          retry_on: [:timeout],
          base_delay: 10
        )

      assert result == {:error, :timeout}
      assert :counters.get(counter, 1) == 2
    end

    test "does not retry on non-retryable errors" do
      counter = :counters.new(1, [])

      result =
        ErrorHandler.with_retry(
          fn ->
            :counters.add(counter, 1, 1)
            {:error, :forbidden}
          end,
          max_attempts: 3,
          retry_on: [:timeout],
          base_delay: 10
        )

      assert result == {:error, :forbidden}
      assert :counters.get(counter, 1) == 1
    end

    test "retries on category match" do
      counter = :counters.new(1, [])

      result =
        ErrorHandler.with_retry(
          fn ->
            :counters.add(counter, 1, 1)
            count = :counters.get(counter, 1)

            if count < 2 do
              {:error, {:network, "connection failed"}}
            else
              {:ok, "success"}
            end
          end,
          max_attempts: 3,
          retry_on: [:network],
          base_delay: 10
        )

      assert result == {:ok, "success"}
      assert :counters.get(counter, 1) == 2
    end
  end

  describe "aggregate_results/1" do
    test "collects all successful results" do
      results = [{:ok, 1}, {:ok, 2}, {:ok, 3}]
      assert ErrorHandler.aggregate_results(results) == {:ok, [1, 2, 3]}
    end

    test "returns first error encountered" do
      results = [{:ok, 1}, {:error, :failed}, {:ok, 3}]
      assert ErrorHandler.aggregate_results(results) == {:error, :failed}
    end

    test "handles empty list" do
      assert ErrorHandler.aggregate_results([]) == {:ok, []}
    end

    test "preserves order of successful results" do
      results = [{:ok, "a"}, {:ok, "b"}, {:ok, "c"}]
      assert ErrorHandler.aggregate_results(results) == {:ok, ["a", "b", "c"]}
    end
  end

  describe "error_to_status/1" do
    test "maps error atoms to HTTP status codes" do
      assert ErrorHandler.error_to_status({:error, :bad_request}) == 400
      assert ErrorHandler.error_to_status({:error, :unauthorized}) == 401
      assert ErrorHandler.error_to_status({:error, :forbidden}) == 403
      assert ErrorHandler.error_to_status({:error, :not_found}) == 404
      assert ErrorHandler.error_to_status({:error, :timeout}) == 408
      assert ErrorHandler.error_to_status({:error, :rate_limited}) == 429
      assert ErrorHandler.error_to_status({:error, :service_unavailable}) == 503
    end

    test "preserves HTTP error status codes" do
      assert ErrorHandler.error_to_status({:error, {:http_error, 418}}) == 418
      assert ErrorHandler.error_to_status({:error, {:http_error, 451}}) == 451
    end

    test "returns 500 for unknown errors" do
      assert ErrorHandler.error_to_status({:error, :unknown}) == 500
      assert ErrorHandler.error_to_status({:error, {:custom, "data"}}) == 500
    end
  end

  describe "log_error/3" do
    # Since log_error has side effects (logging), we'll test it minimally
    test "logs error without crashing" do
      # This just ensures the function doesn't crash
      assert ErrorHandler.log_error("Test error", :timeout, %{test: true}) == :ok
      assert ErrorHandler.log_error("Another error", {:http_error, 404}) == :ok
    end
  end
end
