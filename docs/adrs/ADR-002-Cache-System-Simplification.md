# ADR-002: Cache System Simplification

## Status

Accepted

## Context

The original caching system was overly complex with multiple layers:
- Multiple cache backends (Cachex, ETS, Redis considerations)
- Complex facade patterns with specialized cache helpers
- Scattered key generation logic across modules
- Different TTL strategies per cache type
- Analytics and usage tracking adding complexity
- Inconsistent cache access patterns

This complexity made the system:
- Difficult to reason about cache behavior
- Hard to test and mock cache interactions
- Prone to cache inconsistencies
- Overly abstracted for the actual use cases
- Performance bottlenecks due to multiple layers

## Decision

We simplified the cache system to a unified, straightforward approach:

1. **Single Cache Backend**: Standardized on Cachex as the primary cache
   - Removed multiple backend abstractions
   - ETS fallback only for critical failures
   - Eliminated Redis complexity

2. **Unified Cache Interface** (`WandererNotifier.Infrastructure.Cache`)
   - Simple `get/1`, `put/3`, `delete/1` operations
   - Direct cache access without complex facades
   - Consistent error handling across all cache operations

3. **Centralized Key Management** (`WandererNotifier.Infrastructure.Cache.Keys`)
   - All cache keys generated in one module
   - Standardized key format: `prefix:entity_type:id`
   - Easy to audit and manage cache keys

4. **Simplified TTL Strategy**
   - Standard TTLs: 1 hour (systems), 24 hours (entities), 30 minutes (dedup)
   - TTL configured at put-time with sensible defaults
   - No complex TTL calculation logic

5. **Removed Complex Features**
   - Eliminated cache analytics and usage tracking
   - Removed complex cache warming strategies
   - Simplified cache clearing to basic operations

## Consequences

### Positive
- **Easier to Understand**: Single cache backend with simple interface
- **Better Performance**: Fewer abstraction layers
- **Simpler Testing**: Easy to mock cache operations
- **Reduced Memory Usage**: No complex tracking overhead
- **Faster Development**: Straightforward cache usage patterns
- **Better Reliability**: Fewer moving parts means fewer failure points

### Negative
- **Less Flexibility**: Cannot easily switch cache backends
- **Limited Analytics**: No built-in cache usage metrics
- **Simpler Strategies**: Less sophisticated cache warming/invalidation

### Neutral
- **Migration Required**: All cache usage needed updating
- **Configuration Changes**: Simplified cache configuration

## Implementation Notes

### Before (Complex)
```elixir
# Multiple cache helpers with complex facades
CacheHelper.fetch_with_cache(key, module, function, args, ttl, opts)
Cache.Facade.get_character_with_fallback(id, opts)
Analytics.track_cache_usage(operation, key, result)
```

### After (Simplified)
```elixir
# Direct cache operations with unified interface
Cache.get(CacheKeys.character(id))
Cache.put(CacheKeys.system(id), data, ttl: :timer.hours(1))
Cache.delete(CacheKeys.dedup_kill(kill_id))
```

### Key Generation Examples
```elixir
# Centralized in CacheKeys module
CacheKeys.character(1234567890)     # => "esi:character:1234567890"
CacheKeys.system(30000142)          # => "map:system:30000142"
CacheKeys.dedup_kill(kill_id)       # => "dedup:killmail:123456"
```

### Cache Configuration
```elixir
# Simple Cachex configuration
config :wanderer_notifier, :cache,
  backend: :cachex,
  name: :wanderer_cache,
  limit: 10_000,
  default_ttl: :timer.hours(1)
```

## Alternatives Considered

1. **Keep Complex System**: Rejected due to maintenance overhead
2. **GenServer-based Cache**: Rejected as Cachex provides needed functionality
3. **Multiple Specialized Caches**: Rejected to avoid cache coordination issues
4. **No Caching**: Rejected due to API rate limiting requirements

## Migration Notes

- All cache operations were migrated to the new interface
- Cache keys were standardized using the new key generation system
- TTL values were simplified and standardized
- Complex cache helpers were removed and replaced with direct cache calls

## References

- Cache performance benchmarks
- Cachex documentation and best practices
- Sprint 2 infrastructure simplification goals