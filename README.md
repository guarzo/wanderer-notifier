# Wanderer Notifier

**Real-time EVE Online killmail monitoring and Discord notifications for wormhole space.**

Wanderer Notifier is an Elixir/OTP application that monitors EVE Online killmail data and sends rich Discord notifications for significant in-game events. It integrates with the Wanderer map via Server-Sent Events (SSE) for real-time system and character tracking.

---

## Table of Contents

- [Features](#features)
- [Quick Start](#quick-start)
- [Notification Types](#notification-types)
- [Discord Commands](#discord-commands)
- [License Tiers](#license-tiers)
- [Configuration](#configuration)
- [Development](#development)
- [Architecture](#architecture)
- [Support](#support)

---

## Features

| Category | Features |
|----------|----------|
| **Real-Time Monitoring** | WebSocket killmail feed, SSE map synchronization, instant notifications |
| **Rich Notifications** | Discord embeds with ship thumbnails, portraits, kill values, zKillboard links |
| **Smart Tracking** | Character tracking, system tracking, rally point alerts |
| **Multi-Channel** | Route kills, characters, and systems to separate Discord channels |
| **Discord Integration** | Slash commands for managing priority systems and bot status |
| **Voice Targeting** | Notify only users in voice channels instead of @here |
| **Priority Systems** | Mark critical systems for special notifications with mentions |
| **Production Ready** | OTP supervision trees, health checks, telemetry, Docker deployment |

---

## Quick Start

### Using Docker (Recommended)

```bash
# Clone the repository
git clone https://github.com/yourusername/wanderer-notifier.git
cd wanderer-notifier

# Configure environment
cp .env.example .env
# Edit .env with your Discord bot token and map API credentials

# Start the application
docker-compose up -d

# View logs
docker-compose logs -f
```

### Manual Installation

```bash
# Clone and enter directory
git clone https://github.com/yourusername/wanderer-notifier.git
cd wanderer-notifier

# Create configuration
cp .env.example .env
# Edit .env with your credentials

# Install dependencies and run
mix deps.get
mix compile
mix run --no-halt
```

### Requirements

- Elixir >= 1.18
- Erlang/OTP (compatible version)
- Docker (recommended for deployment)
- Discord Bot Token with proper permissions
- Wanderer map access and API token

---

## Notification Types

### Kill Notifications

Real-time alerts for ship destructions in tracked systems.

- **System kills** → `DISCORD_SYSTEM_KILL_CHANNEL_ID`
- **Character kills** → `DISCORD_CHARACTER_KILL_CHANNEL_ID`
  - Green border: tracked character got a kill
  - Red border: tracked character was killed

Each notification includes:
- System location and ISK value
- Victim details (character, corporation, ship)
- Final blow attacker
- Top damage dealer (if different)
- Ship thumbnails and corp icons
- Direct zKillboard link

### System Notifications

Alerts when new systems are added to tracking. Orange color scheme for easy identification.

### Character Notifications

Notifications for newly tracked characters with portraits and corporation affiliations. Green color scheme.

### Rally Point Notifications

Instant alerts when players create rally points in tracked systems with character info and location details.

### Status Updates

Optional startup confirmations, connection monitoring, and diagnostic information.

---

## Discord Commands

Manage notifications directly from Discord with slash commands.

### `/notifier status`

Shows current bot status:
- Priority systems count
- Feature status (systems, characters, kills)
- Tracking statistics
- Usage metrics

### `/notifier system <system_name> [action]`

Manage system tracking and priority:

| Action | Description |
|--------|-------------|
| `add-priority` | Add system to priority list for @here mentions |
| `remove-priority` | Remove system from priority list |
| `track` | Start tracking a system (coming soon) |
| `untrack` | Stop tracking a system (coming soon) |

### Priority Systems

Priority systems receive special treatment:
- Notifications include targeted mentions (@here or voice participants)
- Ensures critical systems get immediate attention
- Status persists between bot restarts
- Use `PRIORITY_SYSTEMS_ONLY=true` to only notify for priority systems

---

## License Tiers

### Free Tier

All core functionality with one limitation:

- **5 rich embeds per notification type**, then switches to text format
- All notification types (kills, characters, systems, rally points)
- Unlimited tracking
- All Discord commands
- All configuration options

### Premium

- **Unlimited rich embed notifications**
- Ship thumbnails, character portraits, corporation icons
- Formatted details in every notification

### How It Works

1. License validated on startup
2. Refreshed periodically (default: hourly)
3. Free tier limits apply if validation fails
4. Full features enabled in development/test environments

---

## Configuration

All configuration is managed through environment variables. See **[CONFIGURATION.md](CONFIGURATION.md)** for the complete reference.

### Essential Variables

```bash
# Required
DISCORD_BOT_TOKEN=your_bot_token
DISCORD_CHANNEL_ID=123456789012345678
MAP_URL=https://wanderer.ltd
MAP_NAME=your-map-name
MAP_API_KEY=your_api_key

# Recommended
DISCORD_APPLICATION_ID=your_app_id  # For slash commands
LICENSE_KEY=your_license_key        # For unlimited rich embeds
```

### Common Feature Flags

| Variable | Default | Description |
|----------|---------|-------------|
| `NOTIFICATIONS_ENABLED` | `true` | Master switch for all notifications |
| `KILL_NOTIFICATIONS_ENABLED` | `true` | Enable kill notifications |
| `SYSTEM_NOTIFICATIONS_ENABLED` | `true` | Enable system notifications |
| `CHARACTER_NOTIFICATIONS_ENABLED` | `true` | Enable character notifications |
| `PRIORITY_SYSTEMS_ONLY` | `false` | Only notify for priority systems |

See [CONFIGURATION.md](CONFIGURATION.md) for all options including:
- Notification channel routing
- Voice participant targeting
- Corporation filtering
- Timing configuration

---

## Development

### Dev Container (Recommended)

1. Install [Remote - Containers extension](https://marketplace.visualstudio.com/items?itemName=ms-vscode-remote.remote-containers)
2. Open repository in VS Code
3. Reopen in container when prompted

### Makefile Commands

| Command | Description |
|---------|-------------|
| `make compile` | Compile the project |
| `make compile.strict` | Compile with warnings as errors |
| `make test` | Run test suite |
| `make test.cover` | Run tests with coverage |
| `make format` | Format code |
| `make s` | Clean, compile, and start shell |
| `make deps.get` | Fetch dependencies |
| `make deps.update` | Update dependencies |

### Quality Gates

Every change must pass:

```bash
make compile          # No compilation errors
make test             # All tests pass
mix credo --strict    # No credo issues
mix dialyzer          # No dialyzer warnings
```

### Interactive Development

```bash
make s
# In IEx:
iex> WandererNotifier.Config.discord_channel_id()
iex> :observer.start()  # GUI monitoring
```

---

## Architecture

Wanderer Notifier follows a domain-driven architecture built on Elixir/OTP principles.

### Core Principles

- **Domain-Driven Design** - Clear separation between killmail, notifications, tracking, and license domains
- **Event-Driven** - Real-time WebSocket and SSE connections for immediate data processing
- **Unified Infrastructure** - Single HTTP client and cache module with service-specific configs
- **Multi-Phase Initialization** - Sophisticated startup ensuring reliable system initialization
- **OTP Supervision** - Fault-tolerant supervision trees with automatic recovery

### Data Flow

```
┌─────────────────┐     ┌─────────────────┐
│  WandererKills  │────▶│  WebSocket      │
│  (Killmails)    │     │  Client         │
└─────────────────┘     └────────┬────────┘
                                 │
┌─────────────────┐     ┌────────▼────────┐     ┌─────────────────┐
│  Wanderer Map   │────▶│  Processing     │────▶│  Discord        │
│  (SSE Events)   │     │  Pipeline       │     │  Notifications  │
└─────────────────┘     └────────┬────────┘     └─────────────────┘
                                 │
                        ┌────────▼────────┐
                        │  Notification   │
                        │  Determiner     │
                        └─────────────────┘
```

### Module Structure

```
lib/wanderer_notifier/
├── application/           # Coordination & initialization
├── domains/               # Business logic (DDD)
│   ├── killmail/          # Killmail processing
│   ├── notifications/     # Notification handling
│   ├── tracking/          # Character & system tracking
│   └── license/           # License management
├── infrastructure/        # HTTP, cache, adapters
├── map/                   # SSE client & connection monitoring
└── shared/                # Config, utils, telemetry
```

### Technology Stack

| Component | Technology |
|-----------|------------|
| Runtime | Elixir 1.18+, OTP |
| Discord | Nostrum |
| HTTP | HTTPoison/Req with middleware |
| Cache | Cachex/ETS |
| JSON | Jason |
| WebSocket | WebSockex |
| Testing | ExUnit, Mox |
| Deployment | Docker |

---

## Support

- **Issues:** [GitHub Issues](https://github.com/yourusername/wanderer-notifier/issues)
- **Configuration Help:** See [CONFIGURATION.md](CONFIGURATION.md)

---

## License

This project is licensed according to the terms in the LICENSE file.
