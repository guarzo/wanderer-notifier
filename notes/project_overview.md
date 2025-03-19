# WandererNotifier Project Overview

## Project Description
WandererNotifier is an Elixir application that connects to zKillboard's WebSocket API to receive real-time notifications about EVE Online events. It tracks systems and characters on a Pathfinder mapping tool and sends notifications to Discord.

## Features
- Real-time killmail notifications from zKillboard
- System tracking from Pathfinder mapping tool
- Character tracking and notifications
- Discord and Slack integration
- Web dashboard for statistics and management
- EVE Corp Tools integration for TPS charts and statistics
- License validation and feature management

## Architecture
The application follows a modular design with clear separation of concerns through namespaces:

### Core Components
- **Core**: Fundamental functionality like configuration, license management, and feature flags
- **Services**: Business logic for tracking systems, characters, and processing killmails
- **API**: External API clients for zKillboard, ESI, and mapping tools
- **Data**: Data structures, storage, and cache management
- **Notifiers**: Notification services for Discord and Slack
- **Web**: Web server and controllers for dashboard

### Design Patterns
- **Proxy Pattern**: Used for backward compatibility during refactoring
- **Factory Pattern**: Used for notification dispatching
- **Repository Pattern**: Used for cache and data access
- **Observer Pattern**: Used for event handling and notifications

## Technical Stack
- **Elixir/OTP**: Core language and runtime
- **GenServer**: For stateful processes and services
- **Cachex**: For caching data
- **WebSockex**: For WebSocket communication
- **Phoenix/Plug**: For web server functionality
- **Discord/Slack APIs**: For notifications

## Deployment
The application is designed to run as a standalone OTP application or Docker container.

### Requirements
- Elixir 1.14+
- Erlang/OTP 25+
- Docker (optional)

### Configuration
Configuration is managed through environment variables and application config:
- Discord bot token and channel ID
- Map URL and authentication
- License key and validation
- Cache settings and timeouts

## Development Workflow
1. Create feature branches off the main development branch
2. Follow the established namespacing and module organization
3. Use proxy modules for backward compatibility
4. Maintain test coverage
5. Document all changes

## Performance Considerations
- **Caching**: Extensive caching is used for map data, EVE information, and killmails
- **Batch Operations**: Batch processing is used for efficient cache operations
- **Memory Management**: Periodic cache purging is implemented to control memory usage
- **Error Handling**: Robust error handling with retry mechanisms for external dependencies

## Future Direction
- Complete migration to new namespace organization
- Remove proxy modules once all external references are updated
- Enhance web dashboard with more features
- Add more notification channels
- Improve analytics and statistics 