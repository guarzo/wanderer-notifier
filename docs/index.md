# WandererNotifier Documentation

This documentation provides a comprehensive overview of the WandererNotifier application, designed to bring EVE Online notification services to Discord.

## Table of Contents

### Architecture

- [Overview](architecture/overview.md) - High-level architecture of the WandererNotifier system
- [Components](architecture/components.md) - Detailed information about the main components
- [Data Flow](architecture/data-flow.md) - How data flows through the application

### Features

- [System Notifications](features/system-notifications.md) - Notifications for solar system events
- [Character Notifications](features/character-notifications.md) - Notifications for character movements
- [Kill Notifications](features/kill-notifications.md) - Notifications for player kills
- [WebSocket Processing](features/websocket-processing.md) - How real-time data is processed
- [Notifications](features/notifications.md) - General notification system overview
- [Discord Formatting](features/discord-formatting.md) - How messages are formatted for Discord

### Configuration

- [Environment Variables](configuration/environment-variables.md) - Reference for all environment variables
- [Feature Flags](configuration/feature-flags.md) - Feature flag system documentation

### Development

- [Code Style](development/code-style.md) - Coding standards for the project
- [Error Handling](development/error-handling.md) - Error handling strategy and implementation

### Deployment

- [Docker Deployment](deployment/docker-deployment.md) - Guide to deploying with Docker

### Utilities

- [Caching](utilities/caching.md) - Documentation on the caching system and best practices
- [Logging](utilities/logging.md) - Guide to the logging system, categories, and best practices

## Getting Started

To get started with WandererNotifier, we recommend:

1. Read the [Architecture Overview](architecture/overview.md) to understand the system
2. Review the [Environment Variables](configuration/environment-variables.md) for configuration
3. Follow the [Docker Deployment](deployment/docker-deployment.md) guide to set up the system

## Contributing

Please see the [Code Style](development/code-style.md) guide for contribution guidelines.

## Support

If you encounter issues or have questions, please refer to the [Error Handling](development/error-handling.md) document for common solutions.

---

This documentation is maintained by the WandererNotifier development team. For questions or suggestions, please open an issue on the project repository.
