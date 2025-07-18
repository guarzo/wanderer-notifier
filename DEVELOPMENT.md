# Development Guide

This guide provides comprehensive information for developers working on WandererNotifier.

## Prerequisites

- **Elixir 1.18+** with OTP supervision trees
- **Erlang/OTP** (compatible version)
- **Docker** (recommended for development containers)
- **Git** for version control
- **VS Code** (recommended for dev container support)

## Quick Setup

### Option 1: Dev Container (Recommended)

The project includes a complete dev container configuration:

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

2. **Install Elixir dependencies:**
   ```bash
   make deps.get
   ```

3. **Setup environment:**
   ```bash
   cp .env.example .env
   # Edit .env with your configuration
   ```

4. **Compile the project:**
   ```bash
   make compile
   ```

## Development Commands

The project uses a Makefile for common development tasks:

### Core Commands
- `make compile` - Compile the project
- `make compile.strict` - Compile with warnings as errors
- `make clean` - Clean build artifacts
- `make deps.get` - Fetch dependencies
- `make deps.update` - Update all dependencies

### Testing
- `make test` - Run tests using custom script
- `make test.killmail` - Run specific module tests
- `make test.all` - Run all tests with trace
- `make test.watch` - Run tests in watch mode
- `make test.cover` - Run tests with coverage

### Development
- `make s` - Clean, compile, and start interactive shell
- `make format` - Format code using Mix format
- `make server-status` - Check web server connectivity

### Docker & Production
- `make docker.build` - Build Docker image
- `make docker.test` - Test Docker image
- `make release` - Build production release

## Code Organization

### Architecture Overview

WandererNotifier follows domain-driven design with clear separation of concerns:

```
lib/wanderer_notifier/
├── api/                    # Web API layer
├── cache/                  # Caching infrastructure
├── config/                 # Configuration management
├── core/                   # Core application services
├── discord/                # Discord bot infrastructure
├── esi/                    # EVE Swagger Interface
├── http/                   # HTTP client and utilities
├── killmail/               # Killmail processing
├── license/                # License management
├── logger/                 # Logging infrastructure
├── map/                    # Map integration (SSE)
├── notifications/          # Notification system
├── notifiers/              # Notification delivery
├── schedulers/             # Background tasks
└── utils/                  # Shared utilities
```

### Key Design Patterns

1. **Behavior-Driven Design**: All major components define behaviors for swappable implementations
2. **Dependency Injection**: Centralized through `WandererNotifier.Core.Dependencies`
3. **Real-Time Architecture**: WebSocket and SSE for live data streams
4. **Supervision Trees**: Robust fault tolerance with automatic recovery

## Testing Strategy

### Test Structure
- Tests mirror the implementation structure
- Heavy use of Mox for behavior-based mocking
- Fixture data in `test/support/fixtures/`
- Mock implementations in `test/support/mocks/`

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
# Use behavior-based mocking
defmodule MyServiceTest do
  use ExUnit.Case, async: true
  use WandererNotifier.Test.Support.TestHelpers
  
  import Mox
  
  setup do
    setup_mox_defaults()
    :ok
  end
  
  test "handles success case" do
    expect(MockService, :call, fn _ -> {:ok, "result"} end)
    
    assert {:ok, "result"} = MyService.call()
  end
end
```

## Configuration

### Environment Variables
All configuration is managed through environment variables. See `.env.example` for a complete list.

#### Required Variables
- `DISCORD_BOT_TOKEN` - Discord bot authentication
- `DISCORD_CHANNEL_ID` - Primary notification channel
- `MAP_URL`, `MAP_NAME`, `MAP_API_KEY` - Map API configuration
- `LICENSE_KEY` - License for premium features

#### Development-Specific
- `MIX_ENV=dev` - Development environment
- `PORT=4000` - Web server port
- `ENABLE_STATUS_MESSAGES=false` - Disable startup noise

### Feature Flags
Control functionality during development:
```bash
NOTIFICATIONS_ENABLED=true
KILL_NOTIFICATIONS_ENABLED=true
SYSTEM_NOTIFICATIONS_ENABLED=true
CHARACTER_NOTIFICATIONS_ENABLED=true
PRIORITY_SYSTEMS_ONLY=false
```

## Code Quality

### Formatting
```bash
make format
```

### Static Analysis
```bash
# Type checking with Dialyzer
mix dialyzer

# Code quality with Credo
mix credo
```

### Pre-commit Hooks
The project includes quality gates that run automatically. Ensure your code passes:
1. Compilation without warnings
2. All tests passing
3. Code formatting
4. Dialyzer type checking
5. Credo analysis

## Debugging

### Interactive Development
```bash
# Start interactive shell with application
make s

# In IEx:
iex> WandererNotifier.Config.discord_channel_id()
iex> :observer.start()  # GUI monitoring tool
```

### Logging
The application uses structured logging:
```elixir
# In your code
alias WandererNotifier.Logger.Logger, as: AppLogger

AppLogger.api_info("Processing killmail", killmail_id: 123)
AppLogger.config_error("Invalid configuration", setting: "discord_token")
```

### Common Debug Tasks
```bash
# Check configuration
iex> WandererNotifier.Config.validate_all()

# Inspect cache state
iex> Cachex.stats(:wanderer_cache)

# Check supervision tree
iex> WandererNotifier.Application.tree()
```

## Contributing

### Workflow
1. Create a feature branch from `main`
2. Make your changes following the existing patterns
3. Ensure all tests pass and code is formatted
4. Run quality checks (`mix dialyzer`, `mix credo`)
5. Create a pull request with clear description

### Code Style
- Follow existing Elixir conventions
- Use descriptive function and variable names
- Keep functions small and focused
- Document public APIs with `@doc`
- Use behaviors for external dependencies

### Pull Request Guidelines
- Include tests for new functionality
- Update documentation if needed
- Ensure CI passes
- Use conventional commit messages
- Link related issues

## Common Development Scenarios

### Adding a New Notification Type
1. Create formatter in `notifications/formatters/`
2. Add determiner logic in `notifications/determiner/`
3. Update notification dispatcher
4. Add tests and documentation

### Adding a New External Service
1. Define behavior in appropriate module
2. Implement client in dedicated module
3. Add to dependency injection system
4. Create mock for testing
5. Add configuration options

### Debugging WebSocket/SSE Issues
```bash
# Enable detailed logging
export LOG_LEVEL=debug

# Monitor connections
iex> GenServer.call(WandererNotifier.Killmail.WebSocketClient, :status)
iex> GenServer.call(WandererNotifier.Map.SSEClient, :status)
```

## Production Considerations

### Building Releases
```bash
# Local release build
make release

# Docker production image
make docker.build
```

### Health Checks
- `/health` - Basic application health
- `/ready` - Readiness including external services
- `/api/system/info` - System information

### Monitoring
The application includes comprehensive telemetry and logging for production monitoring.

## Resources

- [Elixir Documentation](https://elixir-lang.org/docs.html)
- [OTP Design Principles](https://erlang.org/doc/design_principles/users_guide.html)
- [Nostrum Discord Library](https://github.com/Kraigie/nostrum)
- [Phoenix Framework](https://phoenixframework.org/)

## Support

For development questions:
1. Check the documentation in `docs/`
2. Review existing code patterns
3. Check test examples
4. Open an issue for clarification

The codebase is well-documented and follows consistent patterns. Most questions can be answered by examining similar existing functionality.