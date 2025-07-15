# Sprint 1: HTTP Infrastructure Consolidation

**Duration**: 2 weeks  
**Priority**: High  
**Goal**: Unified HTTP client with middleware architecture

## Week 1: Foundation & Design

### Task 1.1: Create HTTP Client Base Structure
**Estimated Time**: 2 days  
**Files to Create/Modify**:
- `lib/wanderer_notifier/http/client.ex`
- `lib/wanderer_notifier/http/middleware/middleware_behaviour.ex`

**Implementation Steps**:
1. Create base HTTP client module with configuration support
2. Define middleware behaviour with `call/2` callback
3. Implement request/response pipeline with middleware chain
4. Add basic error handling and logging
5. **Quality Gate**: Run `mix format`, `mix dialyzer`, `mix credo` - all must pass
6. **Commit**: "feat: add base HTTP client with middleware architecture"

```elixir
# Expected API design
WandererNotifier.Http.Client.request(:get, "https://api.example.com/data", headers: [], middlewares: [RetryMiddleware, LoggingMiddleware])
```

### Task 1.2: Implement Retry Middleware
**Estimated Time**: 2 days  
**Files to Create/Modify**:
- `lib/wanderer_notifier/http/middleware/retry.ex`
- `test/wanderer_notifier/http/middleware/retry_test.exs`

**Implementation Steps**:
1. Create retry middleware with exponential backoff
2. Add jitter to prevent thundering herd
3. Configure maximum retry attempts and timeout
4. Add retry condition logic (status codes, exceptions)
5. Create comprehensive test suite with mock scenarios
6. **Quality Gate**: Run `mix format`, `mix dialyzer`, `mix credo` - all must pass
7. **Commit**: "feat: add retry middleware with exponential backoff and jitter"

### Task 1.3: Implement Rate Limiting Middleware
**Estimated Time**: 2 days  
**Files to Create/Modify**:
- `lib/wanderer_notifier/http/middleware/rate_limiter.ex`
- `test/wanderer_notifier/http/middleware/rate_limiter_test.exs`

**Implementation Steps**:
1. Implement token bucket rate limiting algorithm
2. Add per-host rate limiting configuration
3. Integrate with existing HTTP client pipeline
4. Add rate limit headers handling (X-RateLimit-*)
5. Create test scenarios for rate limit scenarios
6. **Quality Gate**: Run `mix format`, `mix dialyzer`, `mix credo` - all must pass
7. **Commit**: "feat: add token bucket rate limiting middleware"

## Week 2: Advanced Features & Integration

### Task 1.4: Circuit Breaker Implementation
**Estimated Time**: 3 days  
**Files to Create/Modify**:
- `lib/wanderer_notifier/http/middleware/circuit_breaker.ex`
- `lib/wanderer_notifier/http/circuit_breaker_state.ex`
- `test/wanderer_notifier/http/middleware/circuit_breaker_test.exs`

**Implementation Steps**:
1. Implement circuit breaker with open/half-open/closed states
2. Add failure threshold and recovery time configuration
3. Create state persistence using ETS tables
4. Add health check mechanism for recovery
5. Integrate with HTTP client middleware chain
6. Create comprehensive test suite with state transitions
7. **Quality Gate**: Run `mix format`, `mix dialyzer`, `mix credo` - all must pass
8. **Commit**: "feat: add circuit breaker middleware with state management"

### Task 1.5: Telemetry Integration
**Estimated Time**: 2 days  
**Files to Create/Modify**:
- `lib/wanderer_notifier/http/middleware/telemetry.ex`
- `lib/wanderer_notifier/http/telemetry_events.ex`

**Implementation Steps**:
1. Add telemetry events for request lifecycle
2. Implement metrics collection (duration, status codes, errors)
3. Add request/response size tracking
4. Create telemetry event documentation
5. Integrate with existing stats collection system
6. **Quality Gate**: Run `mix format`, `mix dialyzer`, `mix credo` - all must pass
7. **Commit**: "feat: add comprehensive telemetry for HTTP operations"

### Task 1.6: Migration & Integration
**Estimated Time**: 3 days  
**Files to Modify**:
- `lib/wanderer_notifier/killmail/wanderer_kills_client.ex`
- `lib/wanderer_notifier/esi/client.ex`
- `lib/wanderer_notifier/http.ex`

**Implementation Steps**:
1. Migrate existing HTTP clients to use new unified client
2. Configure middleware chains for different service types
3. Update existing tests to use new HTTP client
4. Add configuration for different middleware combinations
5. Performance testing to ensure no regression
6. **Quality Gate**: Run `mix format`, `mix dialyzer`, `mix credo` - all must pass
7. **Commit**: "refactor: migrate all HTTP clients to unified client with middleware"

## Quality Assurance Checklist (Applied to Each Task)
- [ ] `mix format` passes with no formatting changes needed
- [ ] `mix dialyzer` passes with no type errors or warnings
- [ ] `mix credo` passes with no code quality warnings
- [ ] All tests pass (`mix test`)
- [ ] Test coverage maintained or improved
- [ ] Documentation updated for changes
- [ ] Performance benchmarks meet or exceed previous results
- [ ] Changes committed with descriptive message

## Success Criteria
- [ ] All HTTP operations use unified client with middleware
- [ ] Retry logic implemented with exponential backoff and jitter
- [ ] Rate limiting prevents API abuse
- [ ] Circuit breaker protects against cascading failures
- [ ] Telemetry provides visibility into HTTP operations
- [ ] Existing HTTP clients migrated successfully
- [ ] No performance regression from previous implementation

## Performance Targets
- **HTTP Client**: <200ms average response time
- **Retry Middleware**: <5s total retry time for failed requests
- **Rate Limiting**: Zero requests dropped for normal usage patterns
- **Circuit Breaker**: <1s failure detection time