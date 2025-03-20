# WandererNotifier Code Style Guide

This guide outlines the coding standards, architectural patterns, and best practices to follow when developing for the WandererNotifier project.

## Core Principles

- **Clarity Over Cleverness**: Write clear, self-documenting code rather than clever or overly complex solutions
- **Functional Programming**: Embrace immutability, pure functions, and data transformation pipelines
- **Pattern Matching**: Use pattern matching for control flow instead of conditionals when possible
- **Separation of Concerns**: Keep modules focused on single responsibilities
- **Explicit Over Implicit**: Prefer explicit contracts and interfaces over implicit assumptions
- **Fail Fast**: Let errors surface early rather than propagating invalid states
- **Document Decisions**: Document the "why" behind non-obvious implementation choices

## Elixir Style Guidelines

### Module Organization

- **Namespacing**: Use PascalCase for modules with logical namespacing (e.g., `WandererNotifier.Api.Map.Client`)
- **File Structure**: One module per file with matching directory structure
- **Module Size**: Keep modules focused; split large modules into smaller, purpose-specific ones
- **Domain Grouping**: Group related modules by domain/feature in directories
- **Facade Pattern**: Create client modules as facades that hide implementation details

### Function Style

- **Naming**: Use descriptive snake_case for functions and variables
- **Function Size**: Keep functions small and focused on a single task
- **Pattern Matching Exit**: Use pattern matching for early returns, avoiding deep conditionals
- **Pipeline-Oriented**: Prefer the pipe operator (`|>`) for data transformation chains
- **Guards**: Use guard clauses to restrict function inputs (`when is_map(data)`)
- **Private Helpers**: Extract implementation details to private helper functions

### Data Handling

- **Structured Types**: Define domain-specific structs with proper type specs
- **Data Normalization**: Normalize incoming data into consistent struct formats
- **Immutable Transformations**: Transform data through pipelines of pure functions
- **Access Behaviour**: Implement the Access behaviour for map-like struct operations
- **Result Tuples**: Return `{:ok, result}` or `{:error, reason}` for operations that may fail
- **Nil Handling**: Be explicit about handling nil values with defaults or early returns

### Error Handling

- **Let It Crash Philosophy**: For truly unexpected errors, let the process crash and restart
- **Result Tuples**: Use `{:ok, result}` and `{:error, reason}` consistently
- **Explicit Error Types**: Categorize errors with atoms for better handling (`{:error, :not_found}`)
- **Try/Rescue**: Use try/rescue sparingly, mainly for interacting with external systems
- **Retry Mechanisms**: Implement retries with exponential backoff for transient failures
- **Logging**: Log errors with context at appropriate severity levels

### Documentation

- **@moduledoc**: Include detailed module documentation explaining purpose and usage
- **@doc**: Document all public functions with clear descriptions
- **@spec**: Provide type specifications for all public functions
- **Examples**: Include usage examples in documentation when helpful
- **Comments**: Add comments explaining complex logic or non-obvious decisions
- **Consistent Formatting**: Follow consistent formatting in documentation

## API Client Implementation

- **Layered Architecture**:
  - Base HTTP client with retry and error handling
  - Service-specific clients built on the base client
  - Facade clients coordinating multiple services
- **URL Builder**: Use dedicated modules for URL construction
- **Response Validators**: Validate API responses with dedicated validators
- **Consistent Results**: Return `{:ok, result}` or `{:error, reason}` for all operations
- **Automatic Retries**: Retry transient errors with exponential backoff
- **Error Classification**: Classify errors as transient or permanent
- **Response Parsing**: Parse and transform responses into domain-specific types
- **Debug Logging**: Log request/response details at debug level

## OTP Patterns

- **Supervision Trees**: Organize components into logical supervision trees
- **Child Specifications**: Provide explicit child_spec implementations
- **Restart Strategies**: Choose appropriate restart strategies based on service criticality
- **GenServer Implementation**: Follow consistent patterns for GenServers:
  - Clear state definition
  - Explicit API functions
  - Proper handle\_\* callbacks
  - Defensive state updates
- **Named Processes**: Register important processes with the Registry
- **Process Configuration**: Configure processes from application environment

## Testing Approach

- **Test Structure**: Mirror implementation module structure in tests
- **Case Organization**: Group tests with `describe` blocks for logical organization
- **Setup Context**: Use setup blocks to prepare test data
- **Test Independence**: Ensure tests can run independently with `async: true`
- **Coverage**: Test both happy paths and edge cases
- **Assertions**: Use clear assertions that indicate what's being tested
- **Mocking**: Use mocks judiciously, prefer dependency injection
- **Comprehensive Coverage**: Aim for high test coverage of critical paths

## React Component Design

- **Functional Components**: Use functional components with hooks
- **Component Organization**: Organize components by feature or domain
- **Props Design**: Make props explicit with sensible defaults
- **State Management**: Keep state local when possible, using useState
- **Side Effects**: Manage side effects with useEffect and proper dependencies
- **Error States**: Handle and display errors gracefully
- **Loading States**: Show appropriate loading indicators
- **Styling Approach**: Use TailwindCSS with consistent patterns
- **Reusable Components**: Extract commonly used UI elements into reusable components

## Configuration Management

- **Environment Awareness**: Adapt configuration based on environment
- **Feature Flags**: Use feature flags to control functionality
- **Default Values**: Provide sensible defaults for all configuration
- **Validation**: Validate configuration at startup
- **Secrets Handling**: Never store secrets in code; use environment variables
- **Environment Variables**: Use clearly named environment variables

## Logging Standards

- **Context Inclusion**: Include module/context in log messages (`[Module] Message`)
- **Appropriate Levels**: Use the right log level:
  - `:debug` for detailed troubleshooting
  - `:info` for normal operations
  - `:warn` for potential issues
  - `:error` for actual failures
- **Structured Errors**: Include details and context with errors
- **Sensitive Data**: Never log sensitive information (credentials, tokens)

## Caching Strategy

- **TTL-Based**: Use time-to-live based on data freshness requirements
- **Cache Keys**: Follow consistent naming conventions for cache keys
- **Monitoring**: Monitor cache size and hit/miss rates
- **Invalidation**: Implement strategic invalidation for changed data
- **Fallbacks**: Provide fallbacks when cached data is unavailable

## Git Workflow

- **Descriptive Commits**: Write clear commit messages explaining the what and why
- **Feature Branches**: Develop new features in dedicated branches
- **Pull Requests**: Use PRs for code review before merging
- **Documentation Updates**: Update documentation alongside code changes
- **Changelogs**: Maintain changelogs for significant changes

## Implementation Guidelines

- **Breaking Changes**: Discuss changes affecting more than 3 files before implementation
- **MECE Approach**: Follow Mutually Exclusive, Collectively Exhaustive pattern for changes
- **API Contracts**: Maintain backward compatibility or version APIs appropriately
- **Performance Considerations**: Profile and optimize critical paths
- **Memory Management**: Be mindful of memory usage, especially in long-running processes
- **Security**: Follow security best practices, especially for external API interactions
