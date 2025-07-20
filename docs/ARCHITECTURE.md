# WandererNotifier Architecture Overview

This document describes the simplified architecture implemented in Sprint 2 of the infrastructure consolidation effort.

## Table of Contents
- [Overview](#overview)
- [Core Components](#core-components)
- [HTTP Client Architecture](#http-client-architecture)
- [Cache Architecture](#cache-architecture)
- [Data Flow](#data-flow)
- [Configuration](#configuration)

## Overview

WandererNotifier is an Elixir/OTP application that monitors EVE Online killmail data and sends Discord notifications for significant in-game events. The application has been refactored to use a simplified, maintainable architecture with consolidated HTTP and cache subsystems.

## Core Components

### 1. Unified HTTP Client (`WandererNotifier.Infrastructure.Http`)

The application uses a single, unified HTTP client for all external API interactions:

```elixir
# Simple GET request
Http.get(url, headers, opts)

# POST with authentication
Http.post(url, body, headers, 
  service: :license, 
  auth: [type: :bearer, token: token]
)
```

**Key Features:**
- Service-specific configurations (ESI, WandererKills, License, Map, Streaming)
- Built-in authentication (Bearer, API Key, Basic)
- Middleware pipeline (Telemetry, RateLimiter, Retry, CircuitBreaker)
- Automatic JSON encoding/decoding
- Configurable timeouts and retry logic

### 2. Simplified Cache System

The cache system has been reduced from 15 modules to 3 core modules:

#### `WandererNotifier.Infrastructure.Cache`
Direct Cachex wrapper providing simple cache operations:

```elixir
# Core operations
Cache.get("key")
Cache.put("key", value, ttl)
Cache.delete("key")

# Domain helpers
Cache.get_character(character_id)
Cache.put_system(system_id, data)
```

#### `WandererNotifier.Infrastructure.Cache.ConfigSimple`
Simple TTL configuration:

```elixir
# TTL Configuration
character_ttl()    # 24 hours
system_ttl()       # 1 hour  
killmail_ttl()     # 30 minutes
```

#### `WandererNotifier.Infrastructure.Cache.KeysSimple`
Consistent key generation:

```elixir
Keys.character(123)      # "esi:character:123"
Keys.system(30000142)    # "esi:system:30000142"
Keys.killmail(456)       # "killmail:456"
```

## HTTP Client Architecture

### Service Configurations

Each external service has predefined configurations:

**ESI (EVE Swagger Interface)**
- Timeout: 30 seconds
- Retry: 3 attempts with 1s delay
- Rate limit: 20 req/s (burst: 40)
- Auto-retries on 429, 5xx errors

**WandererKills API**
- Timeout: 15 seconds  
- Retry: 2 attempts with 1s delay
- Rate limit: 10 req/s (burst: 20)

**License Service**
- Timeout: 10 seconds
- Retry: 1 attempt with 2s delay
- Rate limit: 1 req/s (burst: 2)

**Map API (Internal)**
- Timeout: 45 seconds
- Retry: 2 attempts with 500ms delay
- No rate limiting (internal service)

**Streaming (SSE/WebSocket)**
- Timeout: Infinity
- No retries
- No middleware (raw connection)

### Middleware Pipeline

```
Request → Telemetry → RateLimiter → Retry → CircuitBreaker → HTTP Client
```

1. **Telemetry**: Tracks request metrics and duration
2. **RateLimiter**: Enforces per-service rate limits using token bucket
3. **Retry**: Handles transient failures with exponential backoff
4. **CircuitBreaker**: Prevents cascading failures to external services

## Cache Architecture

### Cache Layers

1. **Application Cache** (Cachex)
   - In-memory cache with TTL support
   - LRU eviction policy
   - Size limits (10k entries, 50MB)
   - Statistics tracking

2. **Key Namespaces**
   - `esi:*` - ESI entity data (characters, corporations, systems)
   - `map:*` - Map API data (systems, characters)
   - `killmail:*` - Killmail data
   - `notification:dedup:*` - Notification deduplication
   - `license:*` - License validation

### Cache Strategy

- **Read-through**: Cache checks before API calls
- **Write-through**: Updates cache after successful API responses
- **TTL-based expiration**: Different TTLs per data type
- **No cache warming**: Data cached on-demand

## Data Flow

### Killmail Processing

```
WebSocket/ZKillboard → Killmail Pipeline → Enrichment → Notification Check → Discord
                                ↓               ↓
                             Cache ←────────────┘
```

1. Killmails received via WebSocket (pre-enriched) or ZKillboard
2. Pipeline processes and validates killmail data
3. ESI enrichment for legacy ZKillboard data (skipped for WebSocket)
4. Notification eligibility check
5. Discord notification sent if eligible

### Map Synchronization

```
SSE Stream → Event Handler → Cache Update → Notification Check → Discord
```

1. Real-time events from map API via SSE
2. Event handlers update local cache
3. Notification eligibility check
4. Discord notification for significant events

## Configuration

### Environment Variables

Core configuration via environment variables:

```bash
# API Endpoints
ESI_BASE_URL=https://esi.evetech.net
WANDERER_KILLS_URL=http://host.docker.internal:4004
MAP_URL=https://map.example.com

# Authentication
DISCORD_BOT_TOKEN=xxx
MAP_API_KEY=xxx
WANDERER_API_TOKEN=xxx

# Feature Flags
NOTIFICATIONS_ENABLED=true
KILL_NOTIFICATIONS_ENABLED=true
PRIORITY_SYSTEMS_ONLY=false

# Cache Configuration
CACHE_ADAPTER=Cachex
```

### Runtime Configuration

Configuration layers:
1. `config/config.exs` - Compile-time defaults
2. `config/runtime.exs` - Runtime overrides with env vars
3. `.env` file - Local development

## Benefits of Simplified Architecture

1. **Reduced Complexity**
   - HTTP: 8+ clients → 1 unified client
   - Cache: 15 modules → 3 modules
   - ~2,000 lines of code removed

2. **Improved Maintainability**
   - Single point of configuration for HTTP
   - Direct cache access without abstraction layers
   - Consistent patterns across codebase

3. **Better Performance**
   - Reduced function call overhead
   - Direct Cachex access
   - Optimized middleware pipeline

4. **Enhanced Testability**
   - Simplified mocking with single HTTP client
   - Predictable cache behavior
   - Comprehensive test coverage

## Migration Notes

When migrating from the old architecture:

1. **HTTP Clients**: Replace service-specific clients with `Http` module
2. **Cache Access**: Replace `Facade` with direct `Cache` module
3. **Key Generation**: Use `KeysSimple` instead of complex `Keys`
4. **Configuration**: Use `ConfigSimple` for TTL values

See migration guides in `/workspace/docs/migration/` for detailed instructions.