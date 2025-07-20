# ADR-001: HTTP Client Consolidation

## Status

Accepted

## Context

The original codebase had multiple HTTP client implementations scattered across different modules:
- ESI client with its own retry logic and rate limiting
- WandererKills client with different error handling patterns
- Map API client with separate timeout configurations
- Various service-specific clients with overlapping functionality

This led to:
- Duplicated HTTP handling logic across modules
- Inconsistent error handling and retry patterns
- Difficult maintenance and testing
- Scattered telemetry and logging implementations
- Different rate limiting strategies per service

## Decision

We consolidated all HTTP clients into a unified HTTP infrastructure (`lib/wanderer_notifier/infrastructure/http/`) with:

1. **Single HTTP Client Module** (`WandererNotifier.Infrastructure.Http`)
   - Centralized request/response handling
   - Unified interface for all HTTP operations
   - Service-specific configurations

2. **Service Configuration System**
   - Predefined service configurations (`:esi`, `:wanderer_kills`, `:map_api`)
   - Service-specific timeouts, retry policies, and rate limits
   - Easy to add new services

3. **Middleware Pipeline**
   - Retry middleware with exponential backoff
   - Rate limiting middleware with per-service limits
   - Telemetry middleware for comprehensive monitoring
   - Response handling middleware for consistent error processing

4. **Response Handler System**
   - Standardized response processing
   - Custom error handlers per service type
   - Consistent success/error tuple patterns

## Consequences

### Positive
- **Reduced Complexity**: Single place for HTTP logic maintenance
- **Consistent Error Handling**: All services use same error patterns
- **Better Testing**: Easier to mock and test HTTP interactions
- **Improved Telemetry**: Unified monitoring across all HTTP calls
- **Simplified Configuration**: Service-specific configs in one place
- **Better Rate Limiting**: Per-service rate limits prevent API abuse

### Negative
- **Less Flexibility**: Service-specific customizations are more constrained
- **Migration Effort**: All existing clients needed updating
- **Shared Dependencies**: HTTP failures affect multiple services

### Neutral
- **Learning Curve**: Developers need to understand the new unified system
- **Configuration Changes**: Service configurations moved to centralized location

## Implementation Notes

### Before
```elixir
# Each service had its own client
EsiClient.get_character(id)
WandererKillsClient.get_systems()
MapClient.get_characters()
```

### After
```elixir
# Unified interface with service specification
Http.get(url, headers, service: :esi)
Http.get(url, headers, service: :wanderer_kills)
Http.get(url, headers, service: :map_api)
```

### Service Configuration Example
```elixir
%{
  esi: %{
    timeout: 30_000,
    retry_options: [max_attempts: 3, base_backoff: 1000],
    rate_limit_options: [requests_per_second: 20, burst_capacity: 40],
    telemetry_metadata: %{service: "esi"}
  }
}
```

## Alternatives Considered

1. **Keep Separate Clients**: Rejected due to maintenance overhead
2. **HTTP Library Wrapper**: Rejected as too thin an abstraction
3. **Behavior-Based Approach**: Rejected as overly complex for our needs

## References

- Sprint 2 refactoring documentation
- HTTP client performance benchmarks
- Service configuration patterns in Elixir applications