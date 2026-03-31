# Code Patterns Reference

## Error Handling

- Functions return `{:ok, result}` or `{:error, reason}` tuples
- Use pattern matching for control flow
- Errors are logged via centralized Logger module
- **Exception**: Simple boolean predicates (functions ending in `?`) may return `boolean()` directly for straightforward validation checks. Examples: `license_key_present?/0`, `bot_token_assigned?/0`

## HTTP Client Usage (Unified Infrastructure)

All HTTP requests go through `WandererNotifier.Infrastructure.Http`:

```elixir
# Http.request(method, url, body, headers, opts)
Http.request(:get, url, nil, [], service: :esi)
Http.request(:post, url, body, [], service: :wanderer_kills, auth: [type: :bearer, token: token])

# Convenience methods
Http.get(url, [], service: :esi)

# POST with authentication
Http.post(url, body, [],
  service: :license,
  auth: [type: :bearer, token: api_token]
)

# With custom options
Http.get(url, [], [
  service: :wanderer_kills,
  timeout: 20_000,
  retry_count: 5
])
```

Service configurations:
- `:esi` - 30s timeout, 3 retries, 20 req/s rate limit
- `:wanderer_kills` - 15s timeout, 2 retries, 10 req/s rate limit
- `:license` - 10s timeout, 1 retry, 1 req/s rate limit
- `:map` - 45s timeout, 2 retries, no rate limit
- `:streaming` - Infinite timeout, no retries, no middleware

## Caching Strategy

Direct cache access via `WandererNotifier.Infrastructure.Cache`:

```elixir
# Domain-specific helpers with automatic key generation
Cache.get_character(character_id)
Cache.put_system(system_id, system_data)
Cache.get_killmail(killmail_id)

# Generic operations with TTL
Cache.get("custom:key")
Cache.put("custom:key", value, :timer.hours(1))

# Key generation via Cache.Keys module
Cache.Keys.character(character_id)  # => "esi:character:123"
Cache.Keys.system(system_id)        # => "esi:system:456"
```

Default TTL values (configurable via TtlConfig):
- Character/corporation/alliance data: 24-hour TTL
- System information: 1-hour TTL
- Notification deduplication: 30-minute window
