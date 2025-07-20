# ADR-003: Domain-Driven Module Organization

## Status

Accepted

## Context

The original codebase had a flat module structure that made it difficult to understand boundaries and responsibilities:
- Mixed business logic with infrastructure concerns
- No clear separation between domains
- Shared utilities scattered throughout the codebase
- Difficult to locate related functionality
- Unclear ownership and boundaries for different concerns

The structure looked like:
```
lib/wanderer_notifier/
├── killmail/           # Mixed business + infrastructure
├── notifications/      # Some business logic
├── esi/               # Infrastructure but looked like domain
├── cache/             # Infrastructure scattered
├── http/              # HTTP clients mixed with logic
└── various utilities scattered everywhere
```

This made it hard to:
- Understand the application's core domains
- Separate business logic from infrastructure
- Test components in isolation
- Maintain clear boundaries between concerns

## Decision

We reorganized the codebase following Domain-Driven Design principles with clear separation of concerns:

```
lib/wanderer_notifier/
├── domains/                          # Business logic domains
│   ├── killmail/                     # Killmail processing domain
│   ├── notifications/                # Notification handling domain
│   └── license/                      # License management domain
├── infrastructure/                   # Shared infrastructure
│   ├── adapters/                     # External service adapters
│   ├── cache/                        # Caching infrastructure
│   ├── http/                         # HTTP client infrastructure
│   └── messaging/                    # Event handling infrastructure
├── map/                              # Map tracking domain (SSE-specific)
├── schedulers/                       # Background task scheduling
├── shared/                           # Shared utilities and services
│   ├── config/                       # Configuration management
│   ├── logger/                       # Logging infrastructure
│   └── utils/                        # Common utilities
└── contexts/                         # Application context layer
```

### Key Principles Applied

1. **Domain Separation**: Each business domain has its own directory
2. **Infrastructure Isolation**: All infrastructure concerns are separated
3. **Shared Services**: Common utilities in dedicated shared directory
4. **Clear Boundaries**: Each directory has a specific, well-defined purpose
5. **Dependency Direction**: Domains depend on infrastructure, not vice versa

## Consequences

### Positive
- **Clear Mental Model**: Easy to understand what goes where
- **Better Testability**: Isolated domains are easier to test
- **Improved Maintainability**: Related code is co-located
- **Clearer Dependencies**: Infrastructure dependencies are explicit
- **Better Onboarding**: New developers can quickly understand structure
- **Domain Focus**: Business logic is separated from technical concerns

### Negative
- **More Directories**: Deeper directory structure
- **Migration Effort**: Significant refactoring required
- **Import Path Changes**: All module references needed updating

### Neutral
- **File Movement**: Many files moved but functionality preserved
- **New Conventions**: Team needs to learn new organization patterns

## Implementation Details

### Domain Modules
Each domain contains:
- **Core Logic**: Business rules and processes
- **Domain Services**: Domain-specific services
- **Behaviors**: Contracts for domain operations
- **Schemas**: Domain data structures

Example - Killmail Domain:
```
domains/killmail/
├── websocket_client.ex    # Real-time data ingestion
├── fallback_handler.ex    # Failover logic
├── pipeline.ex            # Processing pipeline
└── wanderer_kills_api.ex  # External API client
```

### Infrastructure Modules
Infrastructure provides:
- **Adapters**: Interfaces to external systems
- **Cache**: Shared caching functionality
- **HTTP**: Unified HTTP client
- **Messaging**: Event handling systems

### Shared Modules
Shared utilities include:
- **Config**: Application configuration
- **Logger**: Structured logging
- **Utils**: Common helper functions

## Migration Notes

### File Movements
- `lib/wanderer_notifier/killmail/*` → `lib/wanderer_notifier/domains/killmail/`
- `lib/wanderer_notifier/esi/*` → `lib/wanderer_notifier/infrastructure/adapters/`
- `lib/wanderer_notifier/cache/*` → `lib/wanderer_notifier/infrastructure/cache/`
- Various utilities → `lib/wanderer_notifier/shared/`

### Import Updates
All module references were updated to reflect new paths:
```elixir
# Before
alias WandererNotifier.Killmail.Pipeline

# After  
alias WandererNotifier.Domains.Killmail.Pipeline
```

## Alternatives Considered

1. **Flat Structure**: Rejected due to scalability and clarity issues
2. **Layer-based Organization**: Rejected as it mixes domains
3. **Feature-based Organization**: Considered but rejected for this domain-centric application
4. **Hexagonal Architecture**: Too complex for current needs

## Benefits Realized

- **Faster Development**: Developers know exactly where to find/add code
- **Better Testing**: Domain isolation makes testing more focused
- **Clearer Reviews**: Pull requests are easier to review with clear boundaries
- **Reduced Coupling**: Infrastructure changes don't affect domain logic
- **Domain Clarity**: Business rules are clearly separated from technical concerns

## References

- Domain-Driven Design by Eric Evans
- Clean Architecture by Robert Martin
- Elixir community organization patterns
- Sprint 2 refactoring documentation