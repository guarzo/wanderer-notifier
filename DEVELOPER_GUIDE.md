# WandererNotifier Developer Guide

Comprehensive guide for developers working on WandererNotifier, covering setup, architecture, and operations.

## Table of Contents

- [Overview](#overview)
- [Quick Setup](#quick-setup)
- [Architecture](#architecture)
- [Development Workflow](#development-workflow)
- [Discord Bot Setup](#discord-bot-setup)
- [System Commands](#system-commands)
- [Production Deployment](#production-deployment)
- [Testing](#testing)
- [Contributing](#contributing)

## Overview

WandererNotifier is an Elixir/OTP application that monitors EVE Online killmail data and sends Discord notifications for significant in-game events. It integrates with external services via WebSocket for real-time killmail data, SSE for map synchronization, and Discord for notifications.

## Quick Setup

### Prerequisites

- **Elixir 1.18+** with OTP supervision trees
- **Erlang/OTP** (compatible version)
- **Docker** (recommended for development containers)
- **Git** for version control
- **VS Code** (recommended for dev container support)

### Option 1: Dev Container (Recommended)

1. Install [Remote - Containers extension](https://marketplace.visualstudio.com/items?itemName=ms-vscode-remote.remote-containers)
2. Open the repository in VS Code
3. When prompted, reopen the project in the container
4. All dependencies and tools are pre-configured

### Option 2: Local Development

1. **Clone the repository:**
   ```bash
   git clone https://github.com/yourusername/wanderer-notifier.git
   cd wanderer-notifier
   ```

2. **Install dependencies:**
   ```bash
   make deps.get
   ```

3. **Setup environment:**
   ```bash
   cp .env.example .env
   # Edit .env with your configuration
   ```

4. **Compile and start:**
   ```bash
   make compile
   make s  # Interactive shell
   ```

## Architecture

### Simplified Architecture (Post-Sprint 2)

WandererNotifier follows a refactored, domain-driven design with simplified infrastructure:

```
lib/wanderer_notifier/
├── domains/                      # Business logic domains
│   ├── killmail/                 # Killmail processing domain
│   ├── notifications/            # Notification handling domain
│   ├── license/                  # License management domain
│   └── character_tracking/       # Character tracking domain
├── infrastructure/               # Shared infrastructure
│   ├── adapters/                 # External service adapters (ESI)
│   ├── cache/                    # Unified caching system (3 modules)
│   ├── http/                     # Centralized HTTP client
│   └── messaging/                # Event handling infrastructure
├── map/                          # Map tracking via SSE
├── schedulers/                   # Background task scheduling
├── shared/                       # Shared utilities and services
└── contexts/                     # Application context layer
```

### Core Components

#### 1. Unified HTTP Client (`WandererNotifier.Infrastructure.Http`)

Single HTTP client for all external API interactions:

```elixir
# Simple GET with service configuration
Http.get(url, [], service: :esi)

# POST with authentication
Http.post(url, body, [], 
  service: :license,
  auth: [type: :bearer, token: api_token]
)
```

**Key Features:**
- Service-specific configurations (ESI, WandererKills, License, Map, Streaming)
- Built-in authentication (Bearer, API Key, Basic)
- Middleware pipeline (Telemetry, RateLimiter, Retry, CircuitBreaker)
- Automatic JSON encoding/decoding

#### 2. Simplified Cache System

Reduced from 15 modules to 3 core modules:

```elixir
# Direct cache access
Cache.get("esi:character:123")
Cache.put("esi:system:30000142", system_data, :timer.hours(1))

# Domain-specific helpers
Cache.get_character(character_id)
Cache.put_system(system_id, system_data)
```

#### 3. Real-Time Data Flow

```
WebSocket Client → Killmail Pipeline → Enrichment → Notification → Discord
SSE Client      → Event Parser     → Cache Update → Notification → Discord
```

### Service Configurations

- **ESI**: 30s timeout, 3 retries, 20 req/s rate limit
- **WandererKills**: 15s timeout, 2 retries, 10 req/s rate limit  
- **License**: 10s timeout, 1 retry, 1 req/s rate limit
- **Map API**: 45s timeout, 2 retries, no rate limit
- **Streaming**: Infinite timeout, no retries, no middleware

## Development Workflow

### Common Commands

The project uses a Makefile for development tasks:

```bash
# Core Development
make compile           # Compile the project
make compile.strict    # Compile with warnings as errors
make s                 # Clean, compile, and start interactive shell
make format            # Format code using Mix format
make clean             # Clean build artifacts

# Dependencies
make deps.get          # Fetch dependencies
make deps.update       # Update all dependencies

# Testing
make test              # Run tests using custom script
make test.killmail     # Run specific module tests
make test.all          # Run all tests with trace
make test.watch        # Run tests in watch mode
make test.cover        # Run tests with coverage

# Docker & Production
make docker.build      # Build Docker image
make docker.test       # Test Docker image
make release           # Build production release
```

### Configuration

#### Required Environment Variables
```bash
# Discord Configuration
DISCORD_BOT_TOKEN="your_bot_token"
DISCORD_APPLICATION_ID="your_application_id" 
DISCORD_CHANNEL_ID="your_default_channel"

# Map Configuration
MAP_URL="https://wanderer.example.com"
MAP_NAME="your-map-name"
MAP_API_KEY="your_map_api_key"

# License Configuration
LICENSE_KEY="your_license_key"
```

#### Feature Flags
```bash
NOTIFICATIONS_ENABLED=true
KILL_NOTIFICATIONS_ENABLED=true
SYSTEM_NOTIFICATIONS_ENABLED=true
CHARACTER_NOTIFICATIONS_ENABLED=true
PRIORITY_SYSTEMS_ONLY=false
TRACK_KSPACE_ENABLED=true
```

### Debugging

```bash
# Interactive Development
make s

# In IEx:
iex> WandererNotifier.Config.discord_channel_id()
iex> :observer.start()  # GUI monitoring tool

# Check configuration
iex> WandererNotifier.Config.validate_all()

# Inspect cache state
iex> Cachex.stats(:wanderer_cache)

# Monitor connections
iex> GenServer.call(WandererNotifier.Killmail.WebSocketClient, :status)
iex> GenServer.call(WandererNotifier.Map.SSEClient, :status)
```

## Discord Bot Setup

### Bot Configuration Requirements

1. **Discord Bot**: You need a Discord bot token and application ID
2. **Environment**: Elixir 1.18+ and the WandererNotifier application
3. **Permissions**: Bot needs slash command permissions in your Discord server

### Bot Permissions Required

- Send Messages
- Use Slash Commands 
- Mention Everyone (for @here notifications)
- Embed Links
- Attach Files

### Quick Bot Setup

1. **Set environment variables:**
   ```bash
   export DISCORD_BOT_TOKEN="your_bot_token_here"
   export DISCORD_APPLICATION_ID="your_application_id_here"
   export DISCORD_CHANNEL_ID="your_default_channel_id"
   ```

2. **Start the application:**
   ```bash
   mix run --no-halt
   ```

3. **Verify bot is online:**
   - Check Discord - your bot should show as online
   - Check logs for "Successfully registered Discord slash commands"

4. **Test slash commands in Discord:**
   ```
   /notifier status
   /notifier system Jita action:add-priority
   ```

## System Commands

The WandererNotifier Discord bot includes comprehensive system command functionality with priority management and flexible notification controls.

### Available Commands

#### `/notifier status`
Displays comprehensive bot status:
- Priority systems count
- Priority-only mode setting
- Command usage statistics
- Notification feature toggles
- System tracking features

#### `/notifier system <system_name>`
Manages system tracking with actions:
- **`add-priority`** - Adds to priority list (@here notifications)
- **`remove-priority`** - Removes from priority list  
- **`track`** - Basic tracking acknowledgment
- **`untrack`** - Stop tracking acknowledgment

### Priority System Logic

#### Normal Mode (default)
- ✅ **Notifications Enabled + Priority System**: @here notification  
- ✅ **Notifications Enabled + Regular System**: Normal notification
- ✅ **Notifications Disabled + Priority System**: @here notification (overrides disabled setting)
- ❌ **Notifications Disabled + Regular System**: No notification

#### Priority-Only Mode (`PRIORITY_SYSTEMS_ONLY=true`)
- ✅ **Priority System**: @here notification (always)
- ❌ **Regular System**: No notification (regardless of system notifications setting)

### Data Persistence

The bot persists data between restarts:
- **Priority Systems**: Stored in `priv/persistent_values.bin`
- **Command History**: Stored in `priv/command_log.bin`
- **Files are created automatically** in the application's priv directory

### Testing Commands

```bash
# Test basic functionality
/notifier status

# Test priority system management
/notifier system TestSystem action:add-priority
/notifier system TestSystem action:remove-priority

# Verify persistence (restart app and check)
/notifier status
```

## Production Deployment

### Pre-Deployment Checklist

#### Environment Variables Validation
```bash
# Required variables
DISCORD_BOT_TOKEN
DISCORD_APPLICATION_ID
DISCORD_CHANNEL_ID
MAP_URL
MAP_NAME
MAP_API_KEY
LICENSE_KEY

# Production settings
MIX_ENV=prod
PORT=4000
ENABLE_STATUS_MESSAGES=false
LOG_LEVEL=info
```

### Docker Deployment

```bash
# Build and deploy
make docker.build
docker-compose up -d

# Verify deployment
docker-compose ps
docker-compose logs -f wanderer-notifier
```

### Health Checks

```bash
# Application health endpoints
curl http://localhost:4000/health
curl http://localhost:4000/ready
curl http://localhost:4000/api/system/info
```

### Production Verification

Run the included verification script:
```bash
chmod +x scripts/production_deployment_verification.sh
./scripts/production_deployment_verification.sh
```

### Monitoring

Watch for these log messages:
```bash
# Successful startup
[info] Discord consumer ready, registering slash commands
[info] Successfully registered Discord slash commands

# Command usage
[info] Discord command executed (type: system, param: Jita)
[info] Added priority system (system: Jita, hash: 40432253)

# Notifications
[info] Sending system notification (system: Jita, priority: true)
```

## Testing

### Test Structure
- Tests mirror the implementation structure
- Heavy use of Mox for behavior-based mocking
- Fixture data in `test/support/fixtures/`
- Consolidated mock implementations in `test/support/consolidated_mocks.ex`

### Running Tests
```bash
# Run all tests
make test

# Run specific module tests
make test.killmail

# Run with coverage
make test.cover

# Watch mode for development
make test.watch
```

### Writing Tests
```elixir
defmodule MyServiceTest do
  use ExUnit.Case, async: true
  use WandererNotifier.Test.Support.ConsolidatedMocks
  
  import Mox
  
  setup do
    setup_default_stubs()
    :ok
  end
  
  test "handles success case" do
    expect(MockService, :call, fn _ -> {:ok, "result"} end)
    
    assert {:ok, "result"} = MyService.call()
  end
end
```

### Test Coverage Progress
- Significantly improved from 19.5% to comprehensive coverage
- Test failures reduced from 185 → 10 (94.6% improvement)
- Complete infrastructure testing (HTTP client, cache system, license service)
- Full integration tests from WebSocket/SSE to Discord delivery

## Contributing

### Development Workflow

1. Create a feature branch from `main`
2. Make your changes following existing patterns
3. Ensure all tests pass and code is formatted
4. Run quality checks (`mix dialyzer`, `mix credo`)
5. Create a pull request with clear description

### Code Quality Tools

```bash
# Formatting
make format

# Type checking with Dialyzer
mix dialyzer

# Code quality with Credo
mix credo
```

### Code Style Guidelines

- Follow existing Elixir conventions
- Use descriptive function and variable names
- Keep functions small and focused
- Document public APIs with `@doc`
- Use behaviors for external dependencies
- Follow domain-driven design patterns

### Key Design Patterns

1. **Behavior-Driven Design**: Major components define behaviors for swappable implementations
2. **Dependency Injection**: Centralized through configuration
3. **Real-Time Architecture**: WebSocket and SSE for live data streams
4. **Supervision Trees**: Robust fault tolerance with automatic recovery
5. **Domain-Driven Design**: Clear separation of business logic

### Adding New Features

#### Adding a New Notification Type
1. Create formatter in `domains/notifications/formatters/`
2. Add determiner logic in `domains/notifications/determiner/`
3. Update notification dispatcher
4. Add tests and documentation

#### Adding a New External Service
1. Define service configuration in HTTP client
2. Implement adapter in `infrastructure/adapters/`
3. Add to dependency injection system
4. Create mock for testing
5. Add configuration options

### Common Development Scenarios

#### Debugging WebSocket/SSE Issues
```bash
# Enable detailed logging
export LOG_LEVEL=debug

# Monitor connections
iex> GenServer.call(WandererNotifier.Killmail.WebSocketClient, :status)
iex> GenServer.call(WandererNotifier.Map.SSEClient, :status)
```

#### Cache Issues
```bash
# Inspect cache state
iex> Cachex.stats(:wanderer_cache)
iex> Cachex.stream(:wanderer_cache) |> Enum.take(10)
```

#### Configuration Issues
```bash
# Validate configuration
iex> WandererNotifier.Shared.Config.EnvConfig.validate_required()
iex> WandererNotifier.Shared.Config.get_all_config()
```

## Resources

- [Elixir Documentation](https://elixir-lang.org/docs.html)
- [OTP Design Principles](https://erlang.org/doc/design_principles/users_guide.html)
- [Nostrum Discord Library](https://github.com/Kraigie/nostrum)
- [Phoenix Framework](https://phoenixframework.org/)
- [Cachex Documentation](https://hexdocs.pm/cachex/)

## Support

For development questions:
1. Check this developer guide
2. Review existing code patterns
3. Check test examples
4. Review architecture documentation in `docs/ARCHITECTURE.md`
5. Open an issue for clarification

---

*This guide consolidates information from DEVELOPMENT.md, SYSTEM_COMMANDS_SUMMARY.md, DISCORD_SETUP_GUIDE.md, PRODUCTION_DEPLOYMENT_CHECKLIST.md, and other documentation files for a comprehensive developer resource.*