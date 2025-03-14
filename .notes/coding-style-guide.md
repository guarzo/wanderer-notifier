# Wanderer Notifier: Coding Style Guide

## Introduction

This document outlines the coding standards and best practices for the Wanderer Notifier project. Following these guidelines ensures code consistency, maintainability, and readability across the codebase. These standards apply to all developers contributing to the project.

## General Principles

### 1. Clarity Over Cleverness

- Write code that is easy to understand rather than code that is clever or overly concise
- Optimize for readability and maintainability first
- Include comments for complex logic, but prefer self-documenting code

### 2. Functional Programming Approach

- Embrace Elixir's functional programming paradigm
- Prefer immutable data structures and pure functions
- Use recursion or higher-order functions instead of imperative loops

### 3. Consistency

- Follow established patterns in the existing codebase
- Use consistent naming, formatting, and organization
- When in doubt, match the style of surrounding code

### 4. Documentation

- Document all modules, public functions, and complex private functions
- Include examples in documentation where appropriate
- Keep documentation up-to-date when changing code

## Elixir-Specific Guidelines

### Naming Conventions

- **Modules**: Use `PascalCase` for module names
  ```elixir
  defmodule WandererNotifier.Discord.Notifier do
  ```

- **Functions and Variables**: Use `snake_case` for function and variable names
  ```elixir
  def send_enriched_kill_embed(enriched_kill, kill_id) do
  ```

- **Constants**: Use `SCREAMING_SNAKE_CASE` for module attributes used as constants
  ```elixir
  @max_recent_kills 100
  ```

- **Predicates**: Functions that return booleans should end with a question mark
  ```elixir
  def character_tracking_enabled?() do
  ```

### Module Structure

1. **Module Documentation**: Begin with a `@moduledoc` describing the module's purpose
   ```elixir
   @moduledoc """
   Sends notifications to Discord as channel messages using a bot token.
   Supports plain text messages and rich embed messages.
   """
   ```

2. **Module Attributes**: Define module attributes next
   ```elixir
   @base_url "https://discord.com/api/channels"
   @verbose_logging false
   ```

3. **Type Specifications**: Include `@type` and `@callback` definitions
   ```elixir
   @callback send_message(String.t()) :: :ok | {:error, any()}
   ```

4. **Public Functions**: List public functions before private ones
   ```elixir
   def send_message(message) when is_binary(message) do
   ```

5. **Private Functions**: Group related private functions together
   ```elixir
   defp build_url do
   ```

### Function Design

1. **Function Size**: Keep functions small and focused on a single responsibility
   - Aim for functions under 15 lines
   - Extract complex logic into helper functions

2. **Arity**: Limit the number of parameters
   - Prefer 0-3 parameters per function
   - Use maps or structs for functions requiring many parameters

3. **Pattern Matching**: Use pattern matching in function heads
   ```elixir
   def send_message(message) when is_binary(message) do
   ```

4. **Guard Clauses**: Use guard clauses to enforce preconditions
   ```elixir
   def format_isk_value(amount) when is_number(amount) do
   ```

5. **Default Arguments**: Use default arguments for optional parameters
   ```elixir
   def send_embed(title, description, url \\ nil, color \\ 0x00FF00) do
   ```

### Error Handling

1. **Pattern Matching**: Use pattern matching for error handling
   ```elixir
   case HttpClient.request("POST", url, headers(), json_payload) do
     {:ok, %HTTPoison.Response{status_code: status}} when status in 200..299 ->
       :ok
     {:ok, %HTTPoison.Response{status_code: status, body: body}} ->
       Logger.error("Discord API request failed with status #{status}")
       {:error, body}
     {:error, err} ->
       Logger.error("Discord API request error: #{inspect(err)}")
       {:error, err}
   end
   ```

2. **Let It Crash**: Follow Erlang's "let it crash" philosophy for unexpected errors
   - Use supervisors to restart failed processes
   - Don't catch exceptions unless you can handle them meaningfully

3. **Explicit Error Returns**: Return tagged tuples for expected error conditions
   ```elixir
   {:error, "map_url or map_name not configured"}
   ```

4. **Logging**: Log errors with appropriate severity levels
   ```elixir
   Logger.error("Failed to get enriched killmail for #{kill_id}: #{inspect(reason)}")
   ```

### Concurrency Patterns

1. **OTP Behaviors**: Use appropriate OTP behaviors
   - `GenServer` for stateful processes
   - `Supervisor` for process supervision
   - `Application` for application lifecycle

2. **Message Passing**: Use message passing for inter-process communication
   ```elixir
   GenServer.call(__MODULE__, :validate)
   ```

3. **Process Isolation**: Design for process isolation to contain failures

4. **Supervision Trees**: Organize processes in supervision trees with appropriate restart strategies

## Code Organization

### Project Structure

- **lib/**: Application source code
  - **lib/wanderer_notifier/**: Core application modules
    - **cache/**: Cache management modules
    - **config/**: Configuration modules
    - **discord/**: Discord integration modules
    - **esi/**: EVE Swagger Interface modules
    - **features/**: Feature management modules
    - **helpers/**: Helper modules and utilities
    - **http/**: HTTP client modules
    - **license/**: License management modules
    - **map/**: Map API integration modules
    - **service/**: Service modules
    - **stats/**: Statistics tracking modules
    - **web/**: Web dashboard modules
    - **zkill/**: zKillboard integration modules
  - **lib/wanderer_notifier.ex**: Main application module

- **test/**: Test files mirroring the structure of lib/
- **config/**: Configuration files
- **rel/**: Release configuration
- **.notes/**: Project documentation

### File Organization

- One module per file
- File name should match the last part of the module name in snake_case
- Group related modules in subdirectories

## Testing Guidelines

### Test Structure

1. **Test Organization**: Mirror the application's module structure in tests
   ```elixir
   defmodule WandererNotifier.Discord.NotifierTest do
   ```

2. **Test Grouping**: Group related tests using `describe` blocks
   ```elixir
   describe "send_message/1" do
   ```

3. **Test Naming**: Use descriptive test names that explain the expected behavior
   ```elixir
   test "returns true when the feature is enabled" do
   ```

### Test Practices

1. **Unit Tests**: Write unit tests for all public functions
   - Test happy paths and error conditions
   - Use mocks for external dependencies

2. **Integration Tests**: Write integration tests for critical workflows
   - Test interactions between components
   - Use test helpers to set up test state

3. **Test Coverage**: Aim for high test coverage, especially for critical paths

4. **Test Independence**: Each test should be independent and not rely on state from other tests

## Documentation Guidelines

### Module Documentation

- Include a `@moduledoc` for every module
- Describe the module's purpose, responsibilities, and usage
- Include examples for complex modules

### Function Documentation

- Document all public functions with `@doc`
- Include parameter descriptions and return value information
- Add examples for non-trivial functions

### Type Specifications

- Include `@spec` for all public functions
- Use custom types with `@type` for complex data structures
- Leverage dialyzer for static type checking

## Commit and Pull Request Guidelines

### Commit Messages

- Use clear, descriptive commit messages
- Start with a verb in the present tense (e.g., "Add", "Fix", "Update")
- Keep the first line under 72 characters
- Include more details in the commit body if necessary

### Pull Requests

- Keep PRs focused on a single change or feature
- Include a clear description of the changes
- Reference related issues
- Ensure all tests pass before requesting review

## Performance Considerations

### Optimization Guidelines

1. **Premature Optimization**: Avoid premature optimization
   - Write clear, correct code first
   - Optimize only when necessary and after profiling

2. **Resource Usage**: Be mindful of resource usage
   - Use efficient data structures
   - Implement caching for expensive operations
   - Release resources when no longer needed

3. **Concurrency**: Leverage Elixir's concurrency for performance
   - Use parallel processing for independent operations
   - Be aware of potential bottlenecks in external services

## Specific Patterns in Wanderer Notifier

### Cache Management

- Use the `WandererNotifier.Cache.Repository` module for caching
- Implement appropriate TTL (Time To Live) for cached items
- Handle cache misses gracefully

```elixir
# Example of cache usage
case CacheRepo.get(cache_key) do
  nil ->
    # Cache miss - fetch data and update cache
    result = fetch_data()
    CacheRepo.put(cache_key, result, ttl: 3600)
    result
  cached_value ->
    # Cache hit
    cached_value
end
```

### Feature Flags

- Use the `WandererNotifier.Features` module to check feature availability
- Base feature availability on license status and configuration
- Implement graceful degradation for disabled features

```elixir
# Example of feature flag usage
if Features.enabled?(:tracked_systems_notifications) do
  # Feature is enabled
  process_system_notification(system)
else
  # Feature is disabled
  Logger.info("System tracking disabled due to license restrictions")
  {:error, :feature_disabled}
end
```

### Notification Formatting

- Follow established patterns for notification formatting
- Create different formats based on license status
- Include all required information in notifications

```elixir
# Example of notification formatting
if license_valid do
  # Rich embed for licensed users
  create_rich_embed(data)
else
  # Simple text for free users
  create_simple_text(data)
end
```

## Conclusion

This style guide is designed to promote consistency and quality across the Wanderer Notifier codebase. By following these guidelines, we ensure that our code remains maintainable, readable, and robust as the project evolves.

Remember that this guide is a living document. As our codebase and team evolve, we may update these guidelines to reflect new best practices and lessons learned.

---

*For questions or clarifications about this style guide, please contact the project maintainers.* 