# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Wanderer Notifier is an Elixir/OTP application that monitors EVE Online killmail data and sends Discord notifications for significant in-game events. It integrates with an external WandererKills service via WebSocket for real-time pre-enriched killmail data, EVE Swagger Interface (ESI) for additional data enrichment when needed, and Wanderer map APIs via Server-Sent Events (SSE) to track wormhole systems and character activities in real-time.

## Common Development Commands

### Build & Compile

```bash
make compile           # Compile the project
make compile.strict    # Compile with warnings as errors
make deps.get         # Fetch dependencies
make deps.update      # Update all dependencies
make clean            # Clean build artifacts
```

### Testing

```bash
make test             # Run tests using custom script
make test.killmail    # Run specific module tests (replace 'killmail' with module name)
make test.all         # Run all tests with trace
make test.watch       # Run tests in watch mode
make test.cover       # Run tests with coverage
```

### Development

```bash
make s                # Clean, compile, and start interactive shell
make format           # Format code using Mix format
make server-status    # Check web server connectivity
```

### Docker & Production

```bash
make docker.build     # Build Docker image
make docker.test      # Test Docker image
make release          # Build production release
docker-compose up -d  # Run locally with Docker
```

## Architecture

The application follows domain-driven design. See [docs/references/architecture.md](docs/references/architecture.md) for the full module structure, data flow, file naming standards, and infrastructure components.

Key domains: `killmail/`, `tracking/`, `notifications/`, `license/` under `lib/wanderer_notifier/domains/`.

## Development Standards

### Quality Gates (Mandatory)

Every code change must pass these quality checks before committing:
1. **`make compile`** - No compilation errors allowed
2. **`make test`** - All tests must pass (100%)
3. **`mix credo --strict`** - No credo issues allowed
4. **`mix dialyzer`** - No dialyzer warnings allowed

Run all at once: `./scripts/validate-quality.sh`

### Commit Standards
- **Message format**: `[Sprint X.Y] Description of change`
- **Quality first**: Fix all quality issues before continuing to next task

### Testing Approach
- Heavy use of Mox for behavior-based mocking
- Test modules follow the same structure as implementation modules
- Mock implementations in `test/support/mocks/`
- Fixture data in `test/support/fixtures/`

## Important Patterns

See [docs/references/patterns.md](docs/references/patterns.md) for error handling, HTTP client usage, and caching strategy details.

Key rules:
- Functions return `{:ok, result}` or `{:error, reason}` tuples
- All HTTP requests go through `WandererNotifier.Infrastructure.Http`
- Cache access via `WandererNotifier.Infrastructure.Cache`
- Boolean predicates (functions ending in `?`) may return `boolean()` directly

## Configuration

See [docs/references/configuration.md](docs/references/configuration.md) for environment variables, feature flags, corporation kill focus, and notification timing.

Key points:
- Environment variables loaded without the WANDERER_ prefix
- Configuration layers: `config/config.exs` (compile-time) -> `config/runtime.exs` (runtime)
- Local development uses `.env` file via Dotenvy
- Features toggled via `_ENABLED` environment variables

## Skills

- **Quality check**: `.claude/skills/quality-check/SKILL.md` — Run all 4 quality gates
- **Release**: `.claude/skills/release/SKILL.md` — Version bump and deployment workflow
