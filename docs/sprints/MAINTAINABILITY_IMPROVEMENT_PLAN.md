# Wanderer Notifier Maintainability Improvement Plan

## Executive Summary

This document outlines a comprehensive plan to improve the maintainability of the Wanderer Notifier application. The plan is organized into six phases, prioritized by impact and implementation complexity.

## Current State Analysis

### Key Issues Identified

1. **Code Duplication**: Multiple HTTP client implementations, repeated error handling patterns, duplicate logging modules
2. **Architectural Complexity**: Large application.ex file, mixed abstraction levels, unclear module boundaries
3. **Inconsistent Patterns**: Various approaches to configuration, caching, and error handling
4. **Testing Gaps**: Limited property-based testing, integration test coverage could be improved

### Strengths to Preserve

- Good use of OTP patterns and supervision trees
- Comprehensive error handling and resilience patterns
- Well-structured test organization with Mox
- Clear domain separation in most areas

## Improvement Phases

### Phase 1: Core Infrastructure Consolidation (High Priority)

#### 1.1 HTTP Client Unification

**Problem**: Duplicate HTTP client implementations (`WandererNotifier.HTTP` and `WandererNotifier.Http.Client`)

**Solution**:
- Remove `WandererNotifier.HTTP` module
- Standardize on `WandererNotifier.Http.Client` with middleware architecture
- Migrate all services to use the centralized client
- Update all HTTP calls to use consistent interface

**Benefits**:
- Single point of configuration
- Consistent error handling across all HTTP operations
- Easier debugging and monitoring
- Reduced code by ~500 lines

#### 1.2 Error Handling Standardization

**Problem**: Repetitive error handling patterns across 142 files

**Solution**:
Create error handling macros in `WandererNotifier.Utils.ErrorHandler`:

```elixir
defmacro with_error_context(context, do: block) do
  quote do
    case unquote(block) do
      {:ok, result} -> {:ok, result}
      {:error, reason} -> 
        Logger.error("Error in #{unquote(context)}", %{error: reason})
        {:error, reason}
    end
  end
end

defmacro handle_result(result, opts \\ []) do
  quote do
    case unquote(result) do
      {:ok, value} -> {:ok, value}
      {:error, reason} -> 
        ErrorHandler.format_error(reason, unquote(opts))
    end
  end
end
```

Define domain-specific error modules:
- `WandererNotifier.Errors.KillmailError`
- `WandererNotifier.Errors.MapError`
- `WandererNotifier.Errors.NotificationError`

**Benefits**:
- 50% reduction in error handling boilerplate
- Consistent error reporting and logging
- Easier to add new error types
- Better error context for debugging

#### 1.3 Logging Consolidation

**Problem**: Multiple logger implementations with 215 Logger calls across 41 files

**Solution**:
- Keep only `WandererNotifier.Logger.Logger` as the main implementation
- Remove `ApiLogger`, `ErrorLogger`, `StructuredLogger` duplicates
- Create context-aware logging macros:

```elixir
defmacro log_operation(level, operation, metadata \\ [], do: block) do
  quote do
    start_time = System.monotonic_time()
    Logger.unquote(level)("Starting #{unquote(operation)}", unquote(metadata))
    
    result = unquote(block)
    
    duration = System.monotonic_time() - start_time
    metadata = Keyword.put(unquote(metadata), :duration_ms, duration)
    
    case result do
      {:ok, _} -> Logger.info("Completed #{unquote(operation)}", metadata)
      {:error, reason} -> Logger.error("Failed #{unquote(operation)}", Keyword.put(metadata, :error, reason))
    end
    
    result
  end
end
```

**Benefits**:
- Unified log format across application
- Automatic operation timing
- Consistent metadata structure
- Easier log analysis and monitoring

### Phase 2: Architecture Refactoring (High Priority)

#### 2.1 Application Initialization Extraction

**Problem**: `application.ex` contains 400+ lines of initialization logic

**Solution**:
Extract initialization into dedicated modules:

```elixir
# lib/wanderer_notifier/init/config_validator.ex
defmodule WandererNotifier.Init.ConfigValidator do
  def validate_required_config do
    # Move config validation logic here
  end
end

# lib/wanderer_notifier/init/service_starter.ex
defmodule WandererNotifier.Init.ServiceStarter do
  def start_services(config) do
    # Move service startup logic here
  end
end

# lib/wanderer_notifier/init/health_checker.ex
defmodule WandererNotifier.Init.HealthChecker do
  def verify_startup_health do
    # Move health check logic here
  end
end
```

Simplified `application.ex`:
```elixir
def start(_type, _args) do
  with :ok <- Init.ConfigValidator.validate_required_config(),
       {:ok, config} <- Init.ConfigLoader.load_config(),
       :ok <- Init.ServiceStarter.start_services(config) do
    
    children = build_supervision_tree(config)
    
    opts = [strategy: :one_for_one, name: WandererNotifier.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
```

**Benefits**:
- Easier to test initialization logic
- Clear separation of concerns
- Reduced complexity in main application file
- Better error handling during startup

#### 2.2 Module Boundary Enforcement

**Problem**: Unclear dependencies between modules leading to potential circular dependencies

**Solution**:
- Define clear context boundaries with public APIs
- Create facade modules for cross-context communication:

```elixir
# lib/wanderer_notifier/contexts/killmail_context.ex
defmodule WandererNotifier.Contexts.KillmailContext do
  @moduledoc """
  Public API for killmail operations.
  All external access to killmail functionality goes through this module.
  """
  
  defdelegate process_killmail(data), to: WandererNotifier.Killmail.Pipeline
  defdelegate get_recent_kills(opts), to: WandererNotifier.Killmail.WandererKillsClient
  
  # Hide internal modules from external access
end
```

- Add `@moduledoc false` to internal modules
- Use `@doc` tags to clearly mark public vs internal functions

**Benefits**:
- Reduced coupling between contexts
- Clearer dependencies
- Easier to refactor internals without breaking external contracts
- Better encapsulation

#### 2.3 Configuration Management Centralization

**Problem**: 107 occurrences of `Application.get_env` scattered across 32 files

**Solution**:
Create centralized configuration store:

```elixir
defmodule WandererNotifier.Config.Store do
  use GenServer
  
  # Cache all config at startup
  def start_link(_) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end
  
  def init(_) do
    config = load_and_validate_config()
    {:ok, config}
  end
  
  # Typed accessors
  def discord_token, do: get_config(:discord_token)
  def websocket_url, do: get_config(:websocket_url)
  def feature_enabled?(feature), do: get_config([:features, feature], false)
  
  defp get_config(key, default \\ nil) do
    GenServer.call(__MODULE__, {:get, key, default})
  end
end
```

Implement typed schemas using Ecto:
```elixir
defmodule WandererNotifier.Config.Schema do
  use Ecto.Schema
  
  embedded_schema do
    field :discord_token, :string
    field :websocket_url, :string
    field :cache_ttl, :integer, default: 3600
    
    embeds_one :features, Features do
      field :notifications_enabled, :boolean, default: true
      field :kill_notifications_enabled, :boolean, default: true
    end
  end
  
  def changeset(config, params) do
    config
    |> cast(params, [:discord_token, :websocket_url, :cache_ttl])
    |> validate_required([:discord_token])
    |> cast_embed(:features)
  end
end
```

**Benefits**:
- Type safety and validation
- Single source of truth for configuration
- Performance improvement (no repeated env lookups)
- Easier testing with config injection

### Phase 3: Code Simplification (Medium Priority)

#### 3.1 Cache Access Pattern Unification

**Problem**: Inconsistent cache access patterns across the codebase

**Solution**:
Enforce use of `CacheHelper.fetch_with_cache/6` and create decorators:

```elixir
defmodule WandererNotifier.Cache.Decorators do
  defmacro cacheable(opts \\ []) do
    quote do
      @cacheable unquote(opts)
    end
  end
  
  defmacro __before_compile__(_env) do
    quote do
      # Auto-wrap functions marked with @cacheable
    end
  end
end

# Usage:
defmodule WandererNotifier.ESI.Service do
  use WandererNotifier.Cache.Decorators
  
  @cacheable ttl: :timer.hours(24), key: :character
  def get_character(id) do
    # Implementation - caching handled automatically
  end
end
```

Centralize TTL configuration:
```elixir
defmodule WandererNotifier.Cache.Config do
  def ttl_for(:character), do: :timer.hours(24)
  def ttl_for(:corporation), do: :timer.hours(24)
  def ttl_for(:system), do: :timer.hours(1)
  def ttl_for(:notification), do: :timer.minutes(30)
end
```

**Benefits**:
- DRY principle applied consistently
- Easier to adjust cache strategies
- Clear cache configuration
- Reduced boilerplate

#### 3.2 Data Transformation Pipeline

**Problem**: Repeated transformation logic across modules

**Solution**:
Create composable transformation pipeline:

```elixir
defmodule WandererNotifier.Transform do
  def pipeline(data, transformations) do
    Enum.reduce_while(transformations, {:ok, data}, fn transform, {:ok, acc} ->
      case transform.(acc) do
        {:ok, result} -> {:cont, {:ok, result}}
        {:error, _} = error -> {:halt, error}
      end
    end)
  end
  
  # Common transformations
  def parse_json(data) when is_binary(data) do
    case Jason.decode(data) do
      {:ok, parsed} -> {:ok, parsed}
      {:error, _} -> {:error, :invalid_json}
    end
  end
  
  def validate_schema(data, schema) do
    case schema.changeset(struct(schema), data) do
      %{valid?: true} = changeset -> {:ok, Ecto.Changeset.apply_changes(changeset)}
      changeset -> {:error, changeset}
    end
  end
  
  def enrich_with(data, enrichment_fn) do
    enrichment_fn.(data)
  end
end

# Usage:
def process_killmail(raw_data) do
  Transform.pipeline(raw_data, [
    &Transform.parse_json/1,
    &Transform.validate_schema(&1, KillmailSchema),
    &Transform.enrich_with(&1, &ESI.enrich_killmail/1)
  ])
end
```

**Benefits**:
- Reusable transformation functions
- Clear data flow
- Easy to test individual transformations
- Composable and extensible

#### 3.3 Notification Protocol Implementation

**Problem**: Duplicate formatting logic across notification types

**Solution**:
Define notification formatter protocol:

```elixir
defprotocol WandererNotifier.Notifications.Formatter do
  @doc "Format notification for Discord"
  def to_discord_message(notification)
  
  @doc "Format notification for plain text"
  def to_plain_text(notification)
  
  @doc "Check if notification should be sent"
  def should_notify?(notification)
end

# Implementations
defimpl WandererNotifier.Notifications.Formatter, for: KillmailNotification do
  def to_discord_message(notification) do
    Common.build_embed()
    |> Common.add_title("Kill: #{notification.victim}")
    |> Common.add_field("System", notification.system)
    |> Common.add_timestamp(notification.time)
  end
end
```

Create shared formatting utilities:
```elixir
defmodule WandererNotifier.Notifications.Formatters.Common do
  def build_embed(color \\ :blue) do
    %{embeds: [%{color: color_code(color)}]}
  end
  
  def add_title(embed, title) do
    put_in(embed, [:embeds, Access.at(0), :title], title)
  end
  
  def add_field(embed, name, value, inline \\ false) do
    # Implementation
  end
  
  def format_isk(value) do
    # Shared ISK formatting logic
  end
  
  def format_character_link(id, name) do
    # Shared character link formatting
  end
end
```

**Benefits**:
- Consistent formatting across notification types
- Easy to add new notification types
- Shared utilities reduce duplication
- Protocol provides clear interface

### Phase 4: Module Organization (Medium Priority)

#### 4.1 Naming Convention Standardization

**Problem**: Inconsistent module naming (singular vs plural, underscores vs nested)

**Solution**:
Adopt consistent naming conventions:
- Use singular names for modules
- Use nested modules for sub-components
- Follow Elixir naming conventions

Renames needed:
```
notifications/ → notification/
notifiers/ → notifier/
schedulers/ → scheduler/
supervisors/ → supervisor/
notification_service.ex → notification.ex
```

**Benefits**:
- Predictable module locations
- Easier navigation
- Consistent with Elixir conventions

#### 4.2 Directory Structure Refinement

**Problem**: Some modules don't fit cleanly into current structure

**Solution**:
Reorganize into clearer structure:

```
lib/wanderer_notifier/
├── core/              # Core business logic
│   ├── killmail/      # Killmail processing
│   ├── map/           # Map tracking
│   └── notification/  # Notification logic
├── adapters/          # External service adapters
│   ├── discord/       # Discord integration
│   ├── esi/           # EVE Online API
│   └── websocket/     # WebSocket connections
├── infrastructure/    # Technical infrastructure
│   ├── cache/         # Caching layer
│   ├── http/          # HTTP client
│   └── config/        # Configuration
├── interfaces/        # Behaviors and protocols
│   ├── behaviors/     # Behavior definitions
│   └── protocols/     # Protocol definitions
├── utils/             # Shared utilities
│   ├── logger/        # Logging utilities
│   └── error/         # Error handling
└── web/               # Web-specific code
    ├── controllers/   # Phoenix controllers
    └── channels/      # Phoenix channels
```

**Benefits**:
- Clear separation of concerns
- Easier to understand architecture
- Better organization for new developers

### Phase 5: Testing Enhancement (Low Priority)

#### 5.1 Property-Based Testing Expansion

**Problem**: Limited use of property-based testing

**Solution**:
Add property tests for critical functions:

```elixir
# test/wanderer_notifier/transform_property_test.exs
defmodule WandererNotifier.TransformPropertyTest do
  use ExUnit.Case
  use ExUnitProperties
  
  property "pipeline always returns ok or error tuple" do
    check all data <- term(),
              transforms <- list_of(one_of([
                constant(&Transform.parse_json/1),
                constant(&Transform.validate_schema(&1, SomeSchema))
              ])) do
      
      result = Transform.pipeline(data, transforms)
      assert match?({:ok, _} | {:error, _}, result)
    end
  end
  
  property "successful transformations are composable" do
    check all initial <- map_of(string(:alphanumeric), term()) do
      transforms = [
        fn data -> {:ok, Map.put(data, :step1, true)} end,
        fn data -> {:ok, Map.put(data, :step2, true)} end
      ]
      
      assert {:ok, result} = Transform.pipeline(initial, transforms)
      assert result[:step1] == true
      assert result[:step2] == true
    end
  end
end
```

Focus areas for property testing:
- Data transformation functions
- Cache key generation
- Configuration validation
- Message parsing

**Benefits**:
- Better edge case coverage
- Discover unexpected behaviors
- More confidence in critical functions

#### 5.2 Integration Test Suite

**Problem**: Limited integration testing between components

**Solution**:
Create comprehensive integration tests:

```elixir
# test/integration/killmail_flow_test.exs
defmodule Integration.KillmailFlowTest do
  use ExUnit.Case
  
  @moduletag :integration
  
  setup do
    # Start required services
    start_supervised!(WandererNotifier.Killmail.WebsocketClient)
    start_supervised!(WandererNotifier.Notifications.Discord)
    :ok
  end
  
  test "full killmail flow from websocket to discord notification" do
    # Simulate websocket message
    killmail_data = build_test_killmail()
    
    # Send through pipeline
    assert {:ok, notification} = KillmailContext.process_killmail(killmail_data)
    
    # Verify notification sent
    assert_receive {:discord_message_sent, message}
    assert message.embeds != []
  end
end
```

Use Docker for external dependencies:
```yaml
# docker-compose.test.yml
version: '3.8'
services:
  test_db:
    image: postgres:13
    environment:
      POSTGRES_PASSWORD: test
  
  mock_esi:
    image: mockserver/mockserver
    ports:
      - "1080:1080"
```

**Benefits**:
- Confidence in system integration
- Catch integration issues early
- Verify end-to-end workflows

### Phase 6: Documentation and Tooling (Low Priority)

#### 6.1 Module Documentation

**Problem**: Missing documentation in many modules

**Solution**:
Add comprehensive documentation:

```elixir
defmodule WandererNotifier.Killmail.Pipeline do
  @moduledoc """
  Processes killmail data through a series of transformations.
  
  ## Overview
  
  The pipeline consists of the following stages:
  
  1. **Validation** - Ensures killmail data meets schema requirements
  2. **Enrichment** - Adds additional data from ESI if needed
  3. **Notification Check** - Determines if notification should be sent
  4. **Formatting** - Prepares notification for delivery
  
  ## Usage
  
      iex> Pipeline.process(killmail_data)
      {:ok, %KillmailNotification{}}
  
  ## Configuration
  
  The pipeline behavior can be configured via:
  
  - `:skip_enrichment` - Skip ESI enrichment for pre-enriched data
  - `:priority_only` - Only process priority system kills
  """
  
  @doc """
  Process a killmail through the full pipeline.
  
  ## Parameters
  
  - `killmail_data` - Raw killmail data (map or JSON string)
  - `opts` - Processing options (optional)
  
  ## Returns
  
  - `{:ok, notification}` - Successfully processed
  - `{:error, reason}` - Processing failed
  
  ## Examples
  
      iex> Pipeline.process(%{killmail_id: 123})
      {:ok, %KillmailNotification{}}
      
      iex> Pipeline.process("invalid")
      {:error, :invalid_killmail_data}
  """
  @spec process(map() | String.t(), keyword()) :: {:ok, KillmailNotification.t()} | {:error, term()}
  def process(killmail_data, opts \\ []) do
    # Implementation
  end
end
```

**Benefits**:
- Easier onboarding for new developers
- Clear API documentation
- Better understanding of module purposes
- Auto-generated documentation

#### 6.2 Development Tooling

**Problem**: Limited static analysis and code quality tools

**Solution**:

1. **Add Credo for static analysis**:
```elixir
# .credo.exs
%{
  configs: [
    %{
      name: "default",
      checks: [
        {Credo.Check.Design.AliasUsage, priority: :low},
        {Credo.Check.Readability.ModuleDoc, priority: :high},
        {Credo.Check.Refactor.CyclomaticComplexity, max_complexity: 10}
      ]
    }
  ]
}
```

2. **Configure Dialyzer for type checking**:
```elixir
# mix.exs
defp deps do
  [
    {:dialyxir, "~> 1.0", only: [:dev], runtime: false}
  ]
end
```

3. **Set up pre-commit hooks**:
```bash
#!/bin/sh
# .git/hooks/pre-commit
mix format --check-formatted
mix credo --strict
mix dialyzer
```

4. **Add code coverage reporting**:
```elixir
# mix.exs
def project do
  [
    test_coverage: [tool: ExCoveralls],
    preferred_cli_env: [
      coveralls: :test,
      "coveralls.html": :test
    ]
  ]
end
```

**Benefits**:
- Consistent code quality
- Catch issues before commit
- Type safety improvements
- Visibility into test coverage

## Implementation Timeline

### Sprint 1-2: Phase 1 (Core Infrastructure)
- Week 1-2: HTTP client unification
- Week 3-4: Error handling standardization
- Week 5-6: Logging consolidation
- Week 7-8: Testing and migration

### Sprint 3-4: Phase 2 (Architecture Refactoring)
- Week 9-10: Application initialization extraction
- Week 11-12: Module boundary enforcement
- Week 13-14: Configuration management
- Week 15-16: Integration and testing

### Sprint 5-6: Phase 3 (Code Simplification)
- Week 17-18: Cache pattern unification
- Week 19-20: Data transformation pipeline
- Week 21-22: Notification protocol
- Week 23-24: Testing and documentation

### Sprint 7: Phase 4 (Module Organization)
- Week 25-26: Naming standardization
- Week 27-28: Directory restructuring

### Sprint 8: Phase 5-6 (Testing & Documentation)
- Week 29-30: Property testing expansion
- Week 31-32: Documentation and tooling

## Measurable Outcomes

### Code Quality Metrics
- **Lines of Code**: ~30% reduction through deduplication
- **Cyclomatic Complexity**: Average < 10 per function
- **Test Coverage**: Increase from current to 90%+
- **Credo Issues**: < 50 total issues

### Performance Metrics
- **Startup Time**: 20% faster through optimized initialization
- **Memory Usage**: 15% reduction through better caching
- **Response Time**: 10% improvement through unified HTTP client

### Developer Experience
- **Feature Development**: 2x faster with clearer architecture
- **Bug Resolution**: 50% faster with better error handling
- **Onboarding Time**: 50% reduction with better documentation

## Risk Mitigation

### Technical Risks
1. **Breaking Changes**
   - Mitigation: Maintain backwards compatibility during transition
   - Use feature flags for gradual rollout
   - Comprehensive test suite before changes

2. **Performance Regression**
   - Mitigation: Benchmark before and after changes
   - Monitor production metrics closely
   - Have rollback plan ready

3. **Integration Issues**
   - Mitigation: Extensive integration testing
   - Staged deployment approach
   - Keep old code paths available

### Process Risks
1. **Scope Creep**
   - Mitigation: Strict phase boundaries
   - Regular reviews and adjustments
   - Clear definition of done

2. **Team Bandwidth**
   - Mitigation: Incremental implementation
   - Parallel work streams where possible
   - Clear priorities

## Success Criteria

Each phase will be considered successful when:

1. **Phase 1**: All HTTP calls use unified client, error handling is consistent
2. **Phase 2**: Application starts faster, configuration is centralized
3. **Phase 3**: Code duplication reduced by 30%, clear patterns established
4. **Phase 4**: Consistent module naming and organization
5. **Phase 5**: 90%+ test coverage, property tests for critical paths
6. **Phase 6**: All public modules documented, tooling integrated

## Conclusion

This plan provides a systematic approach to improving the Wanderer Notifier codebase. By focusing on consolidation, standardization, and simplification, we can significantly improve maintainability while preserving the application's existing strengths.

The phased approach ensures that improvements can be made incrementally without disrupting ongoing development or operations. Each phase delivers independent value while building toward a more maintainable and robust system.