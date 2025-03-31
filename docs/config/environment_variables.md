# Environment Variables Inventory

This document provides a comprehensive list of all environment variables used in the Wanderer Notifier application, including both legacy variables and their new `WANDERER_` prefixed counterparts.

## Variables by Category

### Discord/Notification Configuration

| Legacy Variable                 | New Variable                            | Default  | Description                               | Used In                              |
| ------------------------------- | --------------------------------------- | -------- | ----------------------------------------- | ------------------------------------ |
| `DISCORD_BOT_TOKEN`             | `WANDERER_DISCORD_BOT_TOKEN`            | Required | Discord bot token for API access          | runtime.exs, core/license.ex         |
| `DISCORD_CHANNEL_ID`            | `WANDERER_DISCORD_CHANNEL_ID`           | None     | Primary Discord channel for notifications | runtime.exs, config/notifications.ex |
| `DISCORD_KILL_CHANNEL_ID`       | `WANDERER_DISCORD_KILL_CHANNEL_ID`      | None     | Channel for kill notifications            | runtime.exs, config/notifications.ex |
| `DISCORD_SYSTEM_CHANNEL_ID`     | `WANDERER_DISCORD_SYSTEM_CHANNEL_ID`    | None     | Channel for system notifications          | runtime.exs, config/notifications.ex |
| `DISCORD_CHARACTER_CHANNEL_ID`  | `WANDERER_DISCORD_CHARACTER_CHANNEL_ID` | None     | Channel for character notifications       | runtime.exs, config/notifications.ex |
| `DISCORD_MAP_CHARTS_CHANNEL_ID` | `WANDERER_DISCORD_CHARTS_CHANNEL_ID`    | None     | Channel for chart notifications           | runtime.exs, config/notifications.ex |

### Map/API Configuration

| Legacy Variable           | New Variable                   | Default                        | Description                      | Used In                        |
| ------------------------- | ------------------------------ | ------------------------------ | -------------------------------- | ------------------------------ |
| `MAP_URL_WITH_NAME`       | `WANDERER_MAP_URL`             | None                           | Combined map URL and name        | runtime.exs, debug.ex          |
| `MAP_TOKEN`               | `WANDERER_MAP_TOKEN`           | None                           | Authentication token for map API | runtime.exs, debug.ex          |
| `MAP_URL`                 | None                           | Derived from MAP_URL_WITH_NAME | Base URL for map API             | debug.ex                       |
| `MAP_NAME`                | None                           | Derived from MAP_URL_WITH_NAME | Map name identifier              | debug.ex                       |
| `NOTIFIER_API_TOKEN`      | `WANDERER_NOTIFIER_API_TOKEN`  | None                           | API token for the notifier       | runtime.exs                    |
| `LICENSE_MANAGER_API_URL` | `WANDERER_LICENSE_MANAGER_URL` | "https://lm.wanderer.ltd"      | URL for license validation       | runtime.exs, config/license.ex |

### Feature Flags

| Legacy Variable               | New Variable                                        | Default | Description                                | Used In                                                                     |
| ----------------------------- | --------------------------------------------------- | ------- | ------------------------------------------ | --------------------------------------------------------------------------- |
| `ENABLE_KILL_CHARTS`          | `WANDERER_FEATURE_KILL_CHARTS`                      | "true"  | Enable kill chart feature                  | runtime.exs, config/features.ex                                             |
| `ENABLE_MAP_CHARTS`           | `WANDERER_FEATURE_MAP_CHARTS`                       | "true"  | Enable map chart feature                   | runtime.exs, config/features.ex                                             |
| `ENABLE_TRACK_KSPACE_SYSTEMS` | `WANDERER_FEATURE_TRACK_KSPACE`                     | "true"  | Enable kspace system tracking              | runtime.exs, services/notification_determiner.ex, api/map/systems_client.ex |
| `FEATURE_ACTIVITY_CHARTS`     | `WANDERER_FEATURE_ACTIVITY_CHARTS`                  | "true"  | Enable activity chart feature              | runtime.exs, config/features.ex                                             |
| `FEATURE_MAP_TOOLS`           |Should be removed                                    | "true"  | Enable map tools                           | runtime.exs                                                                 | 
| None                          | `WANDERER_NOTIFICATIONS_ENABLED`                    | "true"  | Master toggle for all notifications        | runtime.exs                                                                 |
| None                          | `WANDERER_CHARACTER_NOTIFICATIONS_ENABLED`          | "true"  | Toggle for character notifications         | runtime.exs                                                                 |
| None                          | `WANDERER_SYSTEM_NOTIFICATIONS_ENABLED`             | "true"  | Toggle for system notifications            | runtime.exs                                                                 |
| None                          | `WANDERER_KILL_NOTIFICATIONS_ENABLED`               | "true"  | Toggle for kill notifications              | runtime.exs                                                                 |
| None                          | `WANDERER_CHARACTER_TRACKING_ENABLED`               | "true"  | Toggle for character tracking              | runtime.exs                                                                 |
| None                          | `WANDERER_SYSTEM_TRACKING_ENABLED`                  | "true"  | Toggle for system tracking                 | runtime.exs                                                                 |
| None                          | `WANDERER_TRACKED_SYSTEMS_NOTIFICATIONS_ENABLED`    | "true"  | Toggle for tracked system notifications    | runtime.exs                                                                 |
| None                          | `WANDERER_TRACKED_CHARACTERS_NOTIFICATIONS_ENABLED` | "true"  | Toggle for tracked character notifications | runtime.exs                                                                 |
| `WANDERER_DEBUG_LOGGING`      | None                                                | "false" | Enable debug logging                       | logger.ex, web/controllers/debug_controller.ex                              |

### Database Configuration

| Legacy Variable      | New Variable            | Default                             | Description                   | Used In     |
| -------------------- | ----------------------- | ----------------------------------- | ----------------------------- | ----------- |
| `POSTGRES_USER`      | `WANDERER_DB_USER`      | "postgres"                          | Database username             | runtime.exs |
| `POSTGRES_PASSWORD`  | `WANDERER_DB_PASSWORD`  | "postgres"                          | Database password             | runtime.exs |
| `POSTGRES_HOST`      | `WANDERER_DB_HOST`      | "postgres"                          | Database hostname             | runtime.exs |
| `POSTGRES_DB`        | `WANDERER_DB_NAME`      | "wanderer*notifier*#{config_env()}" | Database name                 | runtime.exs |
| `POSTGRES_PORT`      | `WANDERER_DB_PORT`      | "5432"                              | Database port                 | runtime.exs |
| `POSTGRES_POOL_SIZE` | `WANDERER_DB_POOL_SIZE` | "10"                                | Database connection pool size | runtime.exs |

### Web Server Configuration

| Legacy Variable | New Variable          | Default     | Description                | Used In     |
| --------------- | --------------------- | ----------- | -------------------------- | ----------- |
| `PORT`          | `WANDERER_PORT`       | "4000"      | Web server port            | runtime.exs |
| `HOST`          | `WANDERER_HOST`       | "localhost" | Web server hostname        | runtime.exs |
| `SCHEME`        | `WANDERER_SCHEME`     | "http"      | Web server protocol scheme | runtime.exs |
| `PUBLIC_URL`    | `WANDERER_PUBLIC_URL` | None        | Public URL for assets      | runtime.exs |

### Websocket Configuration

| Legacy Variable | New Variable                          | Default                           | Description                           | Used In                          |
| --------------- | ------------------------------------- | --------------------------------- | ------------------------------------- | -------------------------------- |
| None            | `WANDERER_WEBSOCKET_ENABLED`          | "true"                            | Enable websocket functionality        | runtime.exs, services/service.ex |
| None            | this shouldn't exist -- can't be changed         | "wss://zkillboard.com/websocket/" | Websocket endpoint URL                | runtime.exs                      |
| None            | `WANDERER_WEBSOCKET_RECONNECT_DELAY`  | "5000"                            | Delay before reconnection attempts    | runtime.exs                      |
| None            | `WANDERER_WEBSOCKET_MAX_RECONNECTS`   | "20"                              | Maximum reconnection attempts         | runtime.exs                      |
| None            | `WANDERER_WEBSOCKET_RECONNECT_WINDOW` | "3600"                            | Time window for reconnection attempts | runtime.exs                      |

### Persistence and Caching

| Legacy Variable                    | New Variable                                | Default           | Description                        | Used In     |
| ---------------------------------- | ------------------------------------------- | ----------------- | ---------------------------------- | ----------- |
| `PERSISTENCE_RETENTION_DAYS`       | `WANDERER_PERSISTENCE_RETENTION_DAYS`       | "180"             | Days to retain persistent data     | runtime.exs |
| `PERSISTENCE_AGGREGATION_SCHEDULE` | `WANDERER_PERSISTENCE_AGGREGATION_SCHEDULE` | "0 0 \* \* \*"    | Cron schedule for data aggregation | runtime.exs |
| `CACHE_DIR`                        | `WANDERER_CACHE_DIR`                        | "/app/data/cache" | Directory for cache storage        | runtime.exs |

### License and Versioning

| Legacy Variable | New Variable           | Default  | Description                    | Used In                           |
| --------------- | ---------------------- | -------- | ------------------------------ | --------------------------------- |
| `LICENSE_KEY`   | `WANDERER_LICENSE_KEY` | Required | License key for application    | runtime.exs, core/license.ex      |
| `APP_VERSION`   | this should be set at config time | None     | Application version identifier | notifiers/structured_formatter.ex |

## Inconsistencies and Issues

1. **Multiple access patterns**: Variables are accessed through both direct `System.get_env` calls and `Application.get_env` configuration.

2. **Redundant variables**: Some features have multiple environment variables controlling the same functionality (e.g., `ENABLE_TRACK_KSPACE_SYSTEMS` and `WANDERER_FEATURE_TRACK_KSPACE`).

3. **Inconsistent naming**: Feature flags use a mix of naming patterns (`ENABLE_*`, `FEATURE_*`, `WANDERER_FEATURE_*`).

4. **Direct access in code**: Many modules access environment variables directly instead of through config modules.

5. **Minimal validation**: Limited validation of environment variable values.

## Next Steps

- Replace direct access to legacy variables with config module functions
- Standardize naming conventions across all variables
- Implement proper validation for all configuration values
- Add comprehensive documentation for each variable
