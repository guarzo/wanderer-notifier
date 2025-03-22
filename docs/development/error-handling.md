# Error Handling Strategy

This document outlines the error handling strategy for the WandererNotifier application, providing guidelines for consistent and robust error management across the codebase.

## Core Principles

1. **Fail Fast** - Detect and report errors as early as possible
2. **Be Explicit** - Use explicit error handling rather than relying on default behaviors
3. **Classify Errors** - Different error types require different handling strategies
4. **Preserve Context** - Capture and preserve error context for debugging
5. **Graceful Degradation** - When possible, degrade functionality gracefully rather than crashing

## Error Classification

We classify errors into the following categories:

### Critical Errors

- Prevent the application from functioning correctly
- Require immediate attention
- Cannot be recovered from automatically
- Examples: database connection failures, API service outages, configuration errors

### Operational Errors

- Occur during normal operation
- Can be handled and recovered from
- May impact specific functionality but not the entire application
- Examples: temporary network issues, rate limiting, invalid user input

### Programmer Errors

- Result from bugs or incorrect assumptions in the code
- Should be fixed in the code rather than handled at runtime
- Examples: invalid function arguments, incorrect state management, improper API usage

## Error Handling Patterns

### Result Tuples

Use the Elixir convention of returning result tuples:

```elixir
# Success case
{:ok, result} = successful_operation()

# Error case
{:error, reason} = failed_operation()

# Pattern matching in function calls
def process_result({:ok, result}), do: handle_success(result)
def process_result({:error, reason}), do: handle_error(reason)
```

### Error Structs

Define structured error types for specific domains:

```elixir
defmodule WandererNotifier.Error do
  @moduledoc """
  Base error structure for WandererNotifier application.
  """

  defstruct [:type, :message, :reason, :stacktrace, :metadata]

  def new(type, message, opts \\ []) do
    %__MODULE__{
      type: type,
      message: message,
      reason: Keyword.get(opts, :reason),
      stacktrace: Keyword.get(opts, :stacktrace, nil),
      metadata: Keyword.get(opts, :metadata, %{})
    }
  end
end

# Domain-specific errors
defmodule WandererNotifier.ApiError do
  @moduledoc """
  Errors related to API operations.
  """

  defstruct [:service, :endpoint, :status_code, :response_body, :request_id]

  def new(service, endpoint, status_code, opts \\ []) do
    %__MODULE__{
      service: service,
      endpoint: endpoint,
      status_code: status_code,
      response_body: Keyword.get(opts, :response_body),
      request_id: Keyword.get(opts, :request_id)
    }
  end
end
```

### Using with Statements

Leverage Elixir's `with` construct for handling multiple potential failure points:

```elixir
def process_character(character_id) do
  with {:ok, character_data} <- fetch_character(character_id),
       {:ok, corporation_data} <- fetch_corporation(character_data.corporation_id),
       {:ok, alliance_data} <- fetch_alliance(character_data.alliance_id),
       {:ok, notification} <- build_notification(character_data, corporation_data, alliance_data),
       {:ok, _} <- send_notification(notification) do
    {:ok, "Character processed successfully"}
  else
    {:error, %ApiError{service: "ESI", status_code: 404}} ->
      {:error, "Character not found"}

    {:error, %ApiError{service: "ESI", status_code: code}} when code >= 500 ->
      {:error, "ESI service unavailable"}

    {:error, %ApiError{} = error} ->
      Logger.error("API error: #{inspect(error)}")
      {:error, "Failed to process character due to API error"}

    {:error, reason} ->
      Logger.error("Unknown error: #{inspect(reason)}")
      {:error, "Failed to process character due to an unexpected error"}
  end
end
```

### Try-Rescue Pattern

Use sparingly, primarily for handling expected exceptions from external libraries:

```elixir
def parse_json(json_string) do
  try do
    {:ok, Jason.decode!(json_string)}
  rescue
    e in Jason.DecodeError ->
      Logger.debug("Invalid JSON: #{inspect(json_string)}")
      {:error, "Invalid JSON format"}
  end
end
```

## API Client Error Handling

### Response Validation

All API responses should be validated:

```elixir
defmodule WandererNotifier.Api.ResponseValidator do
  @moduledoc """
  Validates API responses and converts them to standard result tuples.
  """

  def validate(%Tesla.Env{status: status, body: body} = response) when status >= 200 and status < 300 do
    case validate_response_body(body) do
      {:ok, validated_body} -> {:ok, validated_body}
      {:error, reason} -> {:error, ApiError.new("validation_error", reason, response: response)}
    end
  end

  def validate(%Tesla.Env{status: status} = response) when status >= 400 and status < 500 do
    {:error, ApiError.new("client_error", "Request error", status: status, response: response)}
  end

  def validate(%Tesla.Env{status: status} = response) when status >= 500 do
    {:error, ApiError.new("server_error", "Server error", status: status, response: response)}
  end

  def validate(%Tesla.Env{} = response) do
    {:error, ApiError.new("unknown_error", "Unknown response status", response: response)}
  end

  # Additional validation logic...
end
```

### Retry Logic

Implement retry logic for transient failures:

```elixir
defmodule WandererNotifier.Api.RetryStrategy do
  @moduledoc """
  Defines retry strategies for API calls.
  """

  def exponential_backoff(attempt) do
    base_delay = 500
    max_delay = 30_000
    jitter = :rand.uniform(100)

    delay = min(base_delay * :math.pow(2, attempt) + jitter, max_delay)
    trunc(delay)
  end
end

def fetch_with_retry(url, opts \\ []) do
  max_attempts = Keyword.get(opts, :max_attempts, 3)

  Enum.reduce_while(1..max_attempts, {:error, "Not attempted"}, fn attempt, _acc ->
    case fetch(url) do
      {:ok, result} ->
        {:halt, {:ok, result}}

      {:error, reason} ->
        if attempt < max_attempts do
          delay = RetryStrategy.exponential_backoff(attempt)
          Process.sleep(delay)
          {:cont, {:error, reason}}
        else
          {:halt, {:error, reason}}
        end
    end
  end)
end
```

## Error Handling in OTP Contexts

### GenServer Error Handling

Handle crashes within GenServer callbacks and provide recovery mechanisms:

```elixir
defmodule WandererNotifier.CharacterMonitor do
  use GenServer
  require Logger

  # ... initialization logic ...

  def handle_info({:process_character, character_id}, state) do
    case process_character(character_id) do
      {:ok, result} ->
        {:noreply, update_state(state, character_id, result)}

      {:error, reason} ->
        Logger.error("Failed to process character #{character_id}: #{inspect(reason)}")
        # Schedule retry with backoff
        Process.send_after(self(), {:retry_process_character, character_id, 1}, 5_000)
        {:noreply, state}
    end
  end

  def handle_info({:retry_process_character, character_id, attempt}, state) do
    max_attempts = 3

    if attempt <= max_attempts do
      case process_character(character_id) do
        {:ok, result} ->
          {:noreply, update_state(state, character_id, result)}

        {:error, reason} ->
          Logger.error("Retry #{attempt}/#{max_attempts} failed for character #{character_id}: #{inspect(reason)}")
          backoff = :math.pow(2, attempt) * 5_000 |> trunc()
          Process.send_after(self(), {:retry_process_character, character_id, attempt + 1}, backoff)
          {:noreply, state}
      end
    else
      Logger.error("Giving up on processing character #{character_id} after #{max_attempts} attempts")
      {:noreply, mark_character_as_failed(state, character_id)}
    end
  end

  # ... additional handlers ...
end
```

### Supervisor Strategies

Choose appropriate supervisor strategies based on the nature of the supervised processes:

```elixir
defmodule WandererNotifier.Application do
  use Application

  def start(_type, _args) do
    children = [
      # Core services - critical, restart all if these fail
      {WandererNotifier.Database, []},

      # API Clients - can be restarted independently
      %{
        id: WandererNotifier.EsiClient,
        start: {WandererNotifier.EsiClient, :start_link, []},
        restart: :transient  # Only restart if terminated abnormally
      },

      # Monitors - should be restarted, but failures are isolated
      {WandererNotifier.Supervisor.MonitorSupervisor, []}
    ]

    # Strategy: one_for_one - Each child is restarted independently
    Supervisor.start_link(children, strategy: :one_for_one, name: WandererNotifier.Supervisor)
  end
end

defmodule WandererNotifier.Supervisor.MonitorSupervisor do
  use Supervisor

  def start_link(init_arg) do
    Supervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  def init(_init_arg) do
    children = [
      {WandererNotifier.CharacterMonitor, []},
      {WandererNotifier.SystemMonitor, []}
    ]

    # Strategy: rest_for_one - If a child fails, all children after it are restarted
    Supervisor.init(children, strategy: :rest_for_one)
  end
end
```

## Logging Strategy

### Log Levels

Use appropriate log levels based on the severity and audience:

- **Debug**: Detailed information for developers, disabled in production
- **Info**: General operational information
- **Warning**: Potential issues that don't affect functionality yet
- **Error**: Errors that affect specific operations but not the entire application
- **Critical**: Errors that might cause the application to crash or become unusable

### Structured Logging

Use structured logging with consistent metadata:

```elixir
# Configure logger
config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id, :user_id, :module]

# In code
Logger.metadata(request_id: request_id, user_id: user_id)
Logger.info("Processing character", character_id: character.id, corporation_id: character.corporation_id)
```

### Context Preservation

Include relevant context in log messages:

```elixir
def process_character(character_id) do
  Logger.metadata(character_id: character_id)

  case fetch_character(character_id) do
    {:ok, character} ->
      Logger.metadata(corporation_id: character.corporation_id)
      Logger.info("Character processed successfully")
      {:ok, character}

    {:error, reason} ->
      Logger.error("Failed to process character", error: inspect(reason))
      {:error, reason}
  end
end
```

## Telemetry and Monitoring

### Event Emission

Emit telemetry events for errors to enable monitoring:

```elixir
defmodule WandererNotifier.Telemetry do
  def emit_error_event(error, metadata \\ %{}) do
    :telemetry.execute(
      [:wanderer_notifier, :error],
      %{count: 1},
      Map.merge(%{error_type: error.__struct__, error: error}, metadata)
    )
  end
end

# Usage
def handle_api_error(error) do
  Logger.error("API error occurred", error: inspect(error))
  WandererNotifier.Telemetry.emit_error_event(error, %{
    service: error.service,
    endpoint: error.endpoint,
    status_code: error.status_code
  })
  {:error, error}
end
```

### Health Checks

Implement health checks to detect error conditions:

```elixir
defmodule WandererNotifier.HealthCheck do
  def check_api_health() do
    services = [
      %{name: "ESI API", check_fn: &check_esi/0},
      %{name: "zKillboard API", check_fn: &check_zkillboard/0},
      %{name: "Map API", check_fn: &check_map_api/0}
    ]

    results = Enum.map(services, fn %{name: name, check_fn: check_fn} ->
      {name, check_fn.()}
    end)

    all_healthy = Enum.all?(results, fn {_, status} -> status == :ok end)

    {if(all_healthy, do: :ok, else: :error), results}
  end

  defp check_esi() do
    case WandererNotifier.EsiClient.status() do
      {:ok, %{"status" => "online"}} -> :ok
      _ -> :error
    end
  end

  # Additional health check implementations...
end
```

## Error Recovery Strategies

### Circuit Breaker Pattern

Implement circuit breakers for external services:

```elixir
defmodule WandererNotifier.CircuitBreaker do
  use GenServer

  # States: :closed (normal), :open (failing), :half_open (testing recovery)
  defstruct [:name, :service, :state, :failure_count, :failure_threshold,
             :recovery_time, :last_failure_time, :half_open_allowed_calls]

  # ... initialization logic ...

  def call(name, operation_fn) do
    case GenServer.call(via_tuple(name), :check_state) do
      :ok ->
        case safe_call(operation_fn) do
          {:ok, result} ->
            GenServer.cast(via_tuple(name), :report_success)
            {:ok, result}

          {:error, reason} ->
            GenServer.cast(via_tuple(name), :report_failure)
            {:error, reason}
        end

      {:error, :circuit_open} ->
        {:error, :service_unavailable}
    end
  end

  # ... additional implementation details ...
end

# Usage
def fetch_character(character_id) do
  CircuitBreaker.call(:esi_service, fn ->
    EsiClient.get_character(character_id)
  end)
end
```

### Fallback Mechanisms

Implement fallbacks for critical functionality:

```elixir
def get_system_status(system_id) do
  case fetch_latest_system_status(system_id) do
    {:ok, status} ->
      {:ok, status}

    {:error, reason} ->
      Logger.warn("Failed to fetch latest system status: #{inspect(reason)}", system_id: system_id)

      # Fallback 1: Check local cache
      case SystemCache.get(system_id) do
        {:ok, cached_status} ->
          Logger.info("Using cached system status", system_id: system_id, cache_age: cached_status.age)
          {:ok, %{cached_status | source: :cache}}

        {:error, _} ->
          # Fallback 2: Use default status
          Logger.warn("Using default system status", system_id: system_id)
          {:ok, default_system_status(system_id)}
      end
  end
end
```

## Testing Error Handling

### Unit Testing Error Paths

Explicitly test error handling paths:

```elixir
defmodule WandererNotifier.CharacterProcessorTest do
  use ExUnit.Case
  import Mox

  setup :verify_on_exit!

  test "handles API errors gracefully" do
    # Setup mock to return an error
    EsiClientMock
    |> expect(:get_character, fn _id ->
      {:error, %ApiError{service: "ESI", status_code: 500}}
    end)

    # Verify the processor handles the error appropriately
    result = CharacterProcessor.process_character(123)
    assert {:error, "ESI service unavailable"} = result
  end

  test "retries on transient errors" do
    # Setup mock to fail once then succeed
    EsiClientMock
    |> expect(:get_character, fn _id ->
      {:error, %ApiError{service: "ESI", status_code: 503}}
    end)
    |> expect(:get_character, fn _id ->
      {:ok, %Character{id: 123, name: "Test Character"}}
    end)

    # Verify retry behavior
    result = CharacterProcessor.process_character_with_retry(123)
    assert {:ok, %Character{id: 123}} = result
  end
end
```

### Integration Testing

Test how components handle errors across boundaries:

```elixir
defmodule WandererNotifier.IntegrationTest.ErrorHandlingTest do
  use ExUnit.Case

  @tag :integration
  test "system degrades gracefully when ESI is unavailable" do
    # Simulate ESI outage by setting invalid API endpoint
    original_url = Application.get_env(:wanderer_notifier, :esi_url)
    Application.put_env(:wanderer_notifier, :esi_url, "http://invalid-esi-url")

    on_exit(fn ->
      Application.put_env(:wanderer_notifier, :esi_url, original_url)
    end)

    # System should still start and handle basic operations
    assert {:ok, _} = WandererNotifier.start_test_application()

    # Critical features using fallbacks should work
    assert {:ok, systems} = WandererNotifier.list_tracked_systems()
    assert length(systems) > 0

    # Non-critical features should gracefully report errors
    assert {:error, "ESI service unavailable"} = WandererNotifier.fetch_character_details(123)
  end
end
```

## Best Practices

1. **Never silently swallow errors** - Always log or handle errors explicitly
2. **Categorize and tag errors** - Use error types and tags to categorize and filter errors
3. **Include context in error reports** - Provide sufficient context to diagnose issues
4. **Use domain-specific error types** - Create error types that match your domain model
5. **Implement graceful degradation** - Design the system to function with reduced capability during failures
6. **Monitor error rates** - Set up monitoring and alerting for error rates
7. **Document error handling patterns** - Ensure team consistency in error handling approaches
8. **Test error paths thoroughly** - Error handling code should be well-tested
9. **Use supervision trees appropriately** - Choose the right supervision strategy for each component
10. **Learn from errors** - Analyze error patterns to improve the system

## Anti-Patterns to Avoid

1. **Catching all exceptions** - Avoid blanket exception handlers
2. **Returning ambiguous error values** - Be explicit and structured with error returns
3. **Failing silently** - Always notify the caller of errors
4. **Inconsistent error formats** - Use consistent error structures throughout the application
5. **Excessive nesting of error handling** - Use `with` statements instead of nested error handling
6. **Missing context** - Error messages without context make debugging difficult
7. **Using exceptions for control flow** - Exceptions should be exceptional
8. **Ignoring transient errors** - Implement proper retry logic for transient failures
9. **Implicit error propagation** - Be explicit about error propagation
10. **No error prioritization** - Categorize errors by severity and impact
