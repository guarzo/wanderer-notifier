# Wanderer Notifier - Architecture Improvement Ideas

> **Project**: EVE Online Killmail Monitoring & Discord Notifications  
> **Status**: Production Elixir/OTP Application  
> **Last Analysis**: 2025-01-14  
> **Codebase**: Comprehensive review of current implementation

## Executive Summary

The Wanderer Notifier application demonstrates strong architectural foundations with clear domain separation, robust error handling, and comprehensive testing. This document outlines targeted improvements to enhance maintainability, scalability, and developer experience while preserving existing strengths.

## 📊 Current Architecture Overview

```
lib/wanderer_notifier/
├── api/                    # HTTP controllers, health checks, dashboard
├── killmail/              # WebSocket client, pipeline, processing
├── map/                   # SSE client, system/character tracking
├── notifications/         # Discord integration, formatters
├── esi/                   # EVE Swagger Interface client
├── cache/                 # Cachex wrapper, key management
├── core/                  # Stats, configuration, shared utilities
├── http/                  # Centralized HTTP client with retry logic
└── web/                   # Plug-based web server
```

### Key Data Flows
1. **Real-time Killmail Processing**: WandererKills WebSocket → Pipeline → Notification → Discord
2. **Map Tracking**: Map API SSE → Character/System Updates → Cache
3. **Legacy Enrichment**: ZKillboard → ESI API → Cache → Notification
4. **Health Monitoring**: Stats Collection → Dashboard → Real-time Web Interface

## 🏆 Current Strengths to Preserve

- **Domain Separation**: Well-organized modules under `lib/wanderer_notifier/`
- **Real-time Processing**: Robust WebSocket (`killmail/websocket_client.ex`) and SSE (`map/sse_client.ex`) implementations
- **HTTP Infrastructure**: Centralized `WandererNotifier.Http` with retry logic and rate limiting
- **Caching Strategy**: Comprehensive Cachex usage with TTL management (`cache/`)
- **Testing Excellence**: Extensive Mox-based behavior mocking with 80%+ coverage
- **Configuration Management**: Strong environment-based config with feature flags
- **Error Handling**: Consistent `{:ok, result}` | `{:error, reason}` patterns
- **Observability**: Structured logging and metrics collection

## 🎯 High-Impact Improvement Areas

### 1. **Consolidate HTTP Utilities** *(Priority: High)*

**Current State**: Multiple HTTP-related modules with some overlap
- `lib/wanderer_notifier/http.ex` - Main HTTP client
- `lib/wanderer_notifier/killmail/wanderer_kills_client.ex` - Specialized client
- Retry logic distributed across modules

**Improvements**:
- Create unified `WandererNotifier.Http.Client` with pluggable middleware
- Consolidate retry strategies and rate limiting
- Add circuit breaker pattern for external APIs
- Implement request/response logging pipeline

```elixir
# Proposed structure
lib/wanderer_notifier/http/
├── client.ex              # Unified HTTP client
├── middleware/
│   ├── retry.ex          # Exponential backoff with jitter
│   ├── rate_limiter.ex   # Token bucket rate limiting
│   ├── circuit_breaker.ex # Fault tolerance
│   └── telemetry.ex      # Request/response metrics
└── adapters/
    ├── esi_adapter.ex    # ESI-specific logic
    └── wanderer_adapter.ex # WandererKills-specific logic
```

### 2. **Enhance Caching Architecture** *(Priority: High)*

**Current State**: Good Cachex implementation but could be more unified
- `cache/config.ex` - Cache configuration
- `cache/keys.ex` - Key generation utilities
- Distributed cache logic across modules

**Improvements**:
- Create `WandererNotifier.Cache.Facade` to abstract Cachex operations
- Implement cache warming strategies for critical data
- Add cache versioning for deployment invalidation
- Create cache performance monitoring

```elixir
# Proposed API
WandererNotifier.Cache.get_character(character_id)
WandererNotifier.Cache.get_system(system_id) 
WandererNotifier.Cache.warm_critical_data()
WandererNotifier.Cache.invalidate_version(version)
```

### 3. **Optimize Real-time Data Processing** *(Priority: Medium)*

**Current State**: Solid WebSocket and SSE implementations
- `killmail/websocket_client.ex` - WandererKills WebSocket connection
- `map/sse_client.ex` - Map API SSE connection
- Individual connection management

**Enhancements**:
- Add connection health monitoring and metrics
- Implement message deduplication across sources
- Add backpressure handling for high-volume periods
- Create unified event sourcing pattern

**Implementation Example**:
```elixir
defmodule WandererNotifier.EventSourcing.Pipeline do
  # Unified event processing for WebSocket and SSE events
  def process_event(%Event{source: :websocket, type: :killmail} = event) do
    event
    |> validate_event()
    |> deduplicate()
    |> enrich_if_needed()
    |> route_to_notifications()
  end
end
```

### 4. **Strengthen Configuration Management** *(Priority: Medium)*

**Current State**: Good environment-based configuration in `config.ex`
- Feature flags with `_ENABLED` pattern
- Runtime configuration via `config/runtime.exs`

**Improvements**:
- Runtime configuration validation with detailed error messages
- Configuration hot-reloading for non-critical settings
- Configuration audit logging
- Environment-specific validation rules

### 5. **Add Monitoring & Observability** *(Priority: Medium)*

**Current State**: Basic health checks and dashboard
- Health endpoints in `api/controllers/health_controller.ex`
- Dashboard in `api/controllers/dashboard_controller.ex`
- Stats collection in `core/stats.ex`

**Enhancements**:
- Structured metrics (Prometheus/StatsD integration)
- Distributed tracing for request flows
- Performance monitoring for cache hit rates
- Alert thresholds for critical metrics

## 🚀 Implementation Roadmap (6 Weeks)

### **Phase 1: Foundation** *(Weeks 1-2)*
- [ ] Consolidate HTTP utilities into unified client
- [ ] Create caching facade with performance monitoring
- [ ] Add structured metrics collection
- [ ] Strengthen CI/CD with quality gates

### **Phase 2: Optimization** *(Weeks 3-4)*
- [ ] Implement real-time processing optimizations
- [ ] Add configuration management enhancements
- [ ] Create monitoring dashboards
- [ ] Add circuit breaker patterns

### **Phase 3: Resilience** *(Weeks 5-6)*
- [ ] Implement comprehensive error recovery
- [ ] Add performance benchmarking
- [ ] Create operational runbooks
- [ ] Enhance testing infrastructure

## 📋 Quality Assurance Strategy

### CI/CD Pipeline Enhancements
```yaml
# .github/workflows/ci.yml additions
- name: Code Quality Gates
  run: |
    mix format --check-formatted
    mix credo --strict
    mix dialyzer
    mix test --cover --min-coverage 80
    mix deps.audit
```

### Documentation Requirements
- [ ] Architecture Decision Records (ADRs) for major changes
- [ ] Data flow diagrams for killmail and map processing
- [ ] Configuration documentation with examples
- [ ] Troubleshooting guides for common scenarios
- [ ] API documentation for internal modules

### Code Quality Standards
- [ ] Pre-commit hooks for formatting and basic checks
- [ ] Performance regression testing for critical paths
- [ ] Code review checklists by change type
- [ ] Dependency vulnerability scanning

## 🚀 Strategic Architecture Migration: Phoenix + Ecto

### Migration Rationale

**Decision**: Migrate to Phoenix/Ecto to address current pain points and leverage ecosystem benefits

**Key Drivers**:
1. **Ecto Embedded Schemas**: Simplify complex struct handling without adding abstraction layers
2. **Phoenix Channels**: Replace custom WebSocket code with battle-tested channel implementation
3. **Mint + Mint.SSE**: Solve current SSE pain points with robust stream handling
4. **Ecosystem Benefits**: Enhanced tooling, telemetry, and development experience

### Current Pain Points to Address

**Complex Struct Management**:
- Manual validation and transformation logic scattered across modules
- Inconsistent error handling patterns for data parsing
- Complex nested data structures in killmail and map domains

**WebSocket Implementation**:
- Custom connection management and message routing
- Manual heartbeat and reconnection logic
- Limited scalability for multiple concurrent connections

**SSE Client Issues**:
- Stream parsing and reconnection challenges
- Backpressure handling complexity
- Event replay and buffering limitations

## 📋 Phoenix Migration Plan (4-Week Timeline)

### **Phase 1: Foundation Setup** *(Week 1)*

#### Add Dependencies
```elixir
# mix.exs
defp deps do
  [
    {:phoenix, "~> 1.8"},
    {:phoenix_pubsub, "~> 2.1"},
    {:ecto, "~> 3.10"},
    {:mint, "~> 1.5"},
    {:mint_sse, "~> 0.1"},
    # ... existing deps
  ]
end
```

#### Generate Phoenix Structure
```bash
# Generate minimal Phoenix app (no HTML, assets, or Ecto repo)
mix phx.new . --no-html --no-assets --no-webpack --no-ecto
```

#### Preserve Existing Modules
- Keep current business logic intact during migration
- Maintain existing HTTP client and caching systems
- Preserve notification and processing pipelines

### **Phase 2: Ecto Schema Migration** *(Week 1-2)*

#### Replace Complex Structs with Embedded Schemas

**Killmail Domain**:
```elixir
# lib/wanderer_notifier/killmail/schemas/killmail_data.ex
defmodule WandererNotifier.Killmail.Schemas.KillmailData do
  use Ecto.Schema
  import Ecto.Changeset
  
  @primary_key false
  embedded_schema do
    field :killmail_id, :integer
    field :killmail_time, :utc_datetime
    field :solar_system_id, :integer
    
    embeds_one :victim, Victim do
      field :character_id, :integer
      field :corporation_id, :integer
      field :alliance_id, :integer
      field :ship_type_id, :integer
      field :damage_taken, :integer
    end
    
    embeds_many :attackers, Attacker do
      field :character_id, :integer
      field :corporation_id, :integer
      field :ship_type_id, :integer
      field :weapon_type_id, :integer
      field :damage_done, :integer
      field :final_blow, :boolean
    end
  end
  
  def changeset(killmail, attrs) do
    killmail
    |> cast(attrs, [:killmail_id, :killmail_time, :solar_system_id])
    |> cast_embed(:victim, required: true)
    |> cast_embed(:attackers, required: true)
    |> validate_required([:killmail_id, :killmail_time, :solar_system_id])
    |> validate_attackers_present()
  end
  
  defp validate_attackers_present(changeset) do
    attackers = get_field(changeset, :attackers, [])
    if length(attackers) > 0 do
      changeset
    else
      add_error(changeset, :attackers, "must have at least one attacker")
    end
  end
end
```

**Map/Character Domain**:
```elixir
# lib/wanderer_notifier/map/schemas/character_location.ex
defmodule WandererNotifier.Map.Schemas.CharacterLocation do
  use Ecto.Schema
  import Ecto.Changeset
  
  @primary_key false
  embedded_schema do
    field :character_id, :integer
    field :character_name, :string
    field :corporation_id, :integer
    field :alliance_id, :integer
    field :solar_system_id, :integer
    field :ship_type_id, :integer
    field :location_timestamp, :utc_datetime
  end
  
  def changeset(location, attrs) do
    location
    |> cast(attrs, [:character_id, :character_name, :corporation_id, 
                    :alliance_id, :solar_system_id, :ship_type_id, :location_timestamp])
    |> validate_required([:character_id, :solar_system_id, :location_timestamp])
    |> validate_number(:character_id, greater_than: 0)
    |> validate_number(:solar_system_id, greater_than: 0)
  end
end
```

### **Phase 3: Phoenix Channels Implementation** *(Week 2-3)*

#### Replace WebSocket Client with Phoenix Channels

**Channel Definition**:
```elixir
# lib/wanderer_notifier_web/channels/killmail_channel.ex
defmodule WandererNotifierWeb.KillmailChannel do
  use Phoenix.Channel
  require Logger
  
  alias WandererNotifier.Killmail.Pipeline
  alias WandererNotifier.Killmail.Schemas.KillmailData
  
  @impl true
  def join("killmails:stream", _params, socket) do
    # Subscribe to external WandererKills WebSocket
    case start_external_stream() do
      {:ok, _pid} -> 
        send(self(), :after_join)
        {:ok, socket}
      {:error, reason} -> 
        {:error, %{reason: "Failed to connect to stream: #{reason}"}}
    end
  end
  
  @impl true
  def handle_info(:after_join, socket) do
    Logger.info("Client joined killmail stream")
    push(socket, "connected", %{status: "ready"})
    {:noreply, socket}
  end
  
  @impl true
  def handle_info({:external_killmail, raw_data}, socket) do
    case process_external_killmail(raw_data) do
      {:ok, killmail} ->
        broadcast!(socket, "new_killmail", %{killmail: killmail})
        {:noreply, socket}
      {:error, reason} ->
        Logger.error("Failed to process killmail: #{inspect(reason)}")
        {:noreply, socket}
    end
  end
  
  defp start_external_stream do
    # Start supervised process to handle external WebSocket connection
    DynamicSupervisor.start_child(
      WandererNotifier.StreamSupervisor,
      {WandererNotifier.Killmail.ExternalWebSocketClient, [channel_pid: self()]}
    )
  end
  
  defp process_external_killmail(raw_data) do
    with {:ok, parsed} <- Jason.decode(raw_data),
         changeset <- KillmailData.changeset(%KillmailData{}, parsed),
         true <- changeset.valid? do
      killmail = Ecto.Changeset.apply_changes(changeset)
      Pipeline.process_killmail(killmail)
    else
      {:error, %Jason.DecodeError{}} -> {:error, :invalid_json}
      false -> {:error, :invalid_data}
      error -> error
    end
  end
end
```

**External WebSocket Client** (Supervised Process):
```elixir
# lib/wanderer_notifier/killmail/external_websocket_client.ex
defmodule WandererNotifier.Killmail.ExternalWebSocketClient do
  use GenServer
  require Logger
  
  alias WandererNotifier.Config
  
  def start_link(opts) do
    channel_pid = Keyword.fetch!(opts, :channel_pid)
    GenServer.start_link(__MODULE__, %{channel_pid: channel_pid})
  end
  
  @impl true
  def init(%{channel_pid: channel_pid}) do
    websocket_url = Config.websocket_url()
    
    # Use existing WebSocket connection logic but send to channel
    case connect_to_websocket(websocket_url) do
      {:ok, conn} -> 
        {:ok, %{conn: conn, channel_pid: channel_pid}}
      {:error, reason} -> 
        {:stop, reason}
    end
  end
  
  @impl true
  def handle_info({:websocket, _conn, {:text, message}}, state) do
    # Forward to Phoenix Channel instead of direct processing
    send(state.channel_pid, {:external_killmail, message})
    {:noreply, state}
  end
  
  # ... existing WebSocket connection and heartbeat logic
end
```

### **Phase 4: Mint.SSE Migration** *(Week 3-4)*

#### Replace Custom SSE Client

```elixir
# lib/wanderer_notifier/map/mint_sse_client.ex
defmodule WandererNotifier.Map.MintSSEClient do
  use GenServer
  require Logger
  
  alias Mint.HTTP
  alias Mint.SSE
  alias WandererNotifier.Map.Schemas.CharacterLocation
  
  @map_api_url Application.compile_env(:wanderer_notifier, :map_url)
  
  def start_link(_opts) do
    GenServer.start_link(__MODULE__, nil, name: __MODULE__)
  end
  
  @impl true
  def init(_) do
    {:ok, %{conn: nil, sse_state: nil}, {:continue, :connect}}
  end
  
  @impl true
  def handle_continue(:connect, state) do
    case establish_sse_connection() do
      {:ok, conn, sse_state} ->
        Logger.info("Connected to Map API SSE stream")
        {:noreply, %{state | conn: conn, sse_state: sse_state}}
      {:error, reason} ->
        Logger.error("Failed to connect to SSE: #{inspect(reason)}")
        schedule_reconnect()
        {:noreply, state}
    end
  end
  
  @impl true
  def handle_info({:tcp, _socket, data}, %{conn: conn, sse_state: sse_state} = state) do
    case HTTP.stream(conn, data) do
      {:ok, conn, responses} ->
        {sse_state, events} = SSE.parse(sse_state, responses)
        
        # Process events with proper error handling
        Enum.each(events, &process_sse_event/1)
        
        {:noreply, %{state | conn: conn, sse_state: sse_state}}
      {:error, conn, reason} ->
        Logger.error("SSE stream error: #{inspect(reason)}")
        handle_connection_error(conn, reason, state)
    end
  end
  
  @impl true
  def handle_info({:tcp_closed, _socket}, state) do
    Logger.warn("SSE connection closed, reconnecting...")
    schedule_reconnect()
    {:noreply, %{state | conn: nil, sse_state: nil}}
  end
  
  defp establish_sse_connection do
    uri = URI.parse(@map_api_url)
    
    with {:ok, conn} <- HTTP.connect(:https, uri.host, uri.port || 443),
         {:ok, conn, _request_ref} <- HTTP.request(
           conn, "GET", uri.path, 
           [{"accept", "text/event-stream"}, {"cache-control", "no-cache"}],
           nil
         ) do
      sse_state = SSE.init()
      {:ok, conn, sse_state}
    end
  end
  
  defp process_sse_event(%{data: data, event: event_type}) do
    case Jason.decode(data) do
      {:ok, parsed_data} ->
        handle_map_event(event_type, parsed_data)
      {:error, reason} ->
        Logger.error("Failed to parse SSE event data: #{inspect(reason)}")
    end
  end
  
  defp handle_map_event("character_location", data) do
    case CharacterLocation.changeset(%CharacterLocation{}, data) do
      %{valid?: true} = changeset ->
        location = Ecto.Changeset.apply_changes(changeset)
        WandererNotifier.Map.Pipeline.process_character_location(location)
      changeset ->
        Logger.error("Invalid character location data: #{inspect(changeset.errors)}")
    end
  end
  
  defp schedule_reconnect do
    Process.send_after(self(), {:reconnect}, 5_000)
  end
end
```

### **Phase 5: Integration & Testing** *(Week 4)*

#### Update Application Supervision Tree
```elixir
# lib/wanderer_notifier/application.ex
defmodule WandererNotifier.Application do
  def start(_type, _args) do
    children = [
      # Phoenix components
      WandererNotifierWeb.Telemetry,
      {Phoenix.PubSub, name: WandererNotifier.PubSub},
      WandererNotifierWeb.Endpoint,
      
      # Dynamic supervisor for WebSocket clients
      {DynamicSupervisor, strategy: :one_for_one, name: WandererNotifier.StreamSupervisor},
      
      # Mint.SSE client
      WandererNotifier.Map.MintSSEClient,
      
      # Existing components
      WandererNotifier.Core.Stats,
      WandererNotifier.Cache.Supervisor,
      # ... other existing children
    ]
    
    opts = [strategy: :one_for_one, name: WandererNotifier.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
```

## 🎯 Migration Benefits

### **Ecto Embedded Schemas**
- **Simplified Validation**: Built-in changeset validation replaces manual struct validation
- **Type Safety**: Compile-time field validation and transformation
- **Error Handling**: Consistent error patterns across all data processing
- **Documentation**: Schema definitions serve as living documentation

### **Phoenix Channels**
- **Battle-Tested**: Proven WebSocket implementation with built-in features
- **Scalability**: Built-in support for horizontal scaling and connection management
- **Telemetry**: Automatic metrics and monitoring for channel operations
- **Client Libraries**: Rich ecosystem of client-side channel implementations

### **Mint.SSE**
- **Robust Parsing**: Proper SSE frame parsing and event handling
- **Connection Management**: Built-in reconnection and error recovery
- **Backpressure**: Automatic handling of high-volume event streams
- **Memory Efficiency**: Minimal overhead per connection

## 📊 Risk Mitigation

### **Incremental Migration**
- Maintain existing functionality during transition
- Run new and old systems in parallel during testing
- Gradual cutover with rollback capability

### **Testing Strategy**
- Comprehensive integration tests for schema migrations
- Channel connection and message flow testing
- SSE stream processing validation
- Performance benchmarking against current implementation

This migration plan addresses your specific goals while maintaining the application's reliability and avoiding unnecessary abstraction layers.

## 📈 Success Metrics

### Performance Targets
- Cache hit rate: >95% for character/corporation/alliance data
- WebSocket connection uptime: >99.5%
- Notification delivery time: <5 seconds from killmail receipt
- API response time: <200ms for health checks

### Quality Targets
- Test coverage: >85%
- Credo warnings: 0
- Dialyzer errors: 0
- Security vulnerabilities: 0

### Operational Targets
- Application uptime: >99.9%
- Memory usage growth: <5% per week
- Error rate: <0.1% for critical paths
- Log noise: Minimal INFO-level logging in production

## 🎯 Conclusion

The Wanderer Notifier codebase demonstrates excellent engineering practices with strong foundations for scalability and maintainability. These recommendations focus on evolutionary improvements that enhance the existing architecture while maintaining its proven reliability and performance characteristics.

**Key Focus Areas**:
1. Consolidate and optimize existing patterns
2. Enhance observability and monitoring
3. Strengthen error handling and resilience
4. Maintain high code quality standards

**Timeline**: 6-week incremental implementation with continuous delivery
**Risk**: Low - changes build upon existing patterns
**ROI**: High - improved maintainability, reliability, and developer productivity