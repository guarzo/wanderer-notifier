# Environment Variables

This document provides a comprehensive reference for all environment variables used by the WandererNotifier application. Use this as a guide when configuring your deployment.

## Required Core Configuration

| Variable             | Description                               | Default | Required |
| -------------------- | ----------------------------------------- | ------- | -------- |
| `DISCORD_BOT_TOKEN`  | Discord bot token (without "Bot" prefix)  | -       | Yes      |
| `LICENSE_KEY`        | License key for the application           | -       | Yes      |
| `DISCORD_CHANNEL_ID` | Main Discord channel ID for notifications | -       | Yes      |

## Map Configuration

| Variable            | Description                         | Default | Required                                |
| ------------------- | ----------------------------------- | ------- | --------------------------------------- |
| `MAP_URL`           | URL of your Wanderer map            | -       | Yes (if MAP_URL_WITH_NAME not set)      |
| `MAP_NAME`          | Wanderer map name/slug              | -       | Yes (if MAP_URL_WITH_NAME not set)      |
| `MAP_URL_WITH_NAME` | Full map URL including name         | -       | Yes (alternative to MAP_URL + MAP_NAME) |
| `MAP_TOKEN`         | Authentication token for map access | -       | Yes                                     |
| `MAP_CSRF_TOKEN`    | Optional CSRF token for map access  | -       | No                                      |

## Feature Enablement Flags

| Variable                         | Description                                  | Default |
| -------------------------------- | -------------------------------------------- | ------- |
| `ENABLE_NOTIFICATIONS`           | Master switch for all notifications          | `true`  |
| `ENABLE_KILL_NOTIFICATIONS`      | Enable kill notifications                    | `true`  |
| `ENABLE_SYSTEM_NOTIFICATIONS`    | Enable system tracking notifications         | `true`  |
| `ENABLE_CHARACTER_NOTIFICATIONS` | Enable character tracking notifications      | `true`  |
| `ENABLE_CHARTS`                  | Enable chart generation                      | `false` |
| `ENABLE_TPS_CHARTS`              | Enable TPS charts                            | `false` |
| `ENABLE_MAP_CHARTS`              | Enable map charts                            | `false` |
| `TRACK_ALL_SYSTEMS`              | Track all systems instead of specific ones   | `false` |
| `PROCESS_ALL_KILLS`              | Process kills from all systems (for testing) | `false` |

## Discord Channel Configuration

| Variable                        | Description                                  | Default Fallback |
| ------------------------------- | -------------------------------------------- | ---------------- |
| `DISCORD_CHANNEL_ID`            | Main Discord channel ID                      | - (required)     |
| `DISCORD_KILL_CHANNEL_ID`       | Channel for kill notifications               | Main channel     |
| `DISCORD_SYSTEM_CHANNEL_ID`     | Channel for system tracking notifications    | Main channel     |
| `DISCORD_CHARACTER_CHANNEL_ID`  | Channel for character tracking notifications | Main channel     |
| `DISCORD_CHARTS_CHANNEL_ID`     | Channel for general chart notifications      | Main channel     |
| `DISCORD_TPS_CHARTS_CHANNEL_ID` | Channel for TPS chart notifications          | Main channel     |
| `DISCORD_MAP_CHARTS_CHANNEL_ID` | Channel for map chart notifications          | Main channel     |

## Slack Webhook Configuration

| Variable                       | Description                                  | Default Fallback |
| ------------------------------ | -------------------------------------------- | ---------------- |
| `SLACK_WEBHOOK_URL`            | Main Slack webhook URL                       | - (optional)     |
| `SLACK_KILL_WEBHOOK_URL`       | Webhook for kill notifications               | Main webhook     |
| `SLACK_SYSTEM_WEBHOOK_URL`     | Webhook for system tracking notifications    | Main webhook     |
| `SLACK_CHARACTER_WEBHOOK_URL`  | Webhook for character tracking notifications | Main webhook     |
| `SLACK_CHARTS_WEBHOOK_URL`     | Webhook for general chart notifications      | Main webhook     |
| `SLACK_TPS_CHARTS_WEBHOOK_URL` | Webhook for TPS chart notifications          | Main webhook     |
| `SLACK_MAP_CHARTS_WEBHOOK_URL` | Webhook for map chart notifications          | Main webhook     |

## API URLs

| Variable               | Description                 | Default                          |
| ---------------------- | --------------------------- | -------------------------------- |
| `ZKILL_BASE_URL`       | ZKillboard API base URL     | `https://zkillboard.com`         |
| `ESI_BASE_URL`         | ESI API base URL            | `https://esi.evetech.net/latest` |
| `CORP_TOOLS_API_URL`   | Corporation tools API URL   | -                                |
| `CORP_TOOLS_API_TOKEN` | Corporation tools API token | -                                |

## Development Configuration

| Variable                   | Description                           | Default                   |
| -------------------------- | ------------------------------------- | ------------------------- |
| `LICENSE_MANAGER_API_URL`  | License manager API URL               | `https://lm.wanderer.ltd` |
| `LICENSE_MANAGER_AUTH_KEY` | License manager authentication key    | -                         |
| `NOTIFIER_API_TOKEN`       | Notifier API token for authentication | -                         |
| `BOT_REGISTRATION_TOKEN`   | Optional bot registration token       | -                         |
| `MIX_ENV`                  | Elixir environment (dev, test, prod)  | `prod`                    |

## Application Configuration

| Variable             | Description                    | Default                                 |
| -------------------- | ------------------------------ | --------------------------------------- |
| `CHART_SERVICE_PORT` | Port for the chart service     | `3001`                                  |
| `PORT`               | Port for the web interface     | `4000`                                  |
| `PUBLIC_URL`         | Public URL for the application | Constructed from host, port, and scheme |
| `HOST`               | Application host               | `localhost`                             |
| `SCHEME`             | HTTP scheme (http/https)       | `http`                                  |

## Environment-Specific Configuration

The following configuration options are used in specific environments:

| Variable            | Description                          | Default |
| ------------------- | ------------------------------------ | ------- |
| `DEBUG_PANEL`       | Enable debug panel in development    | `false` |
| `ENABLE_CHARTS`     | Enable chart generation capabilities | `false` |
| `TRACK_ALL_SYSTEMS` | Track all systems (for testing)      | `false` |
| `PROCESS_ALL_KILLS` | Process all kills (for testing)      | `false` |

## Cache Configuration

| Variable                | Description                                  | Default            |
| ----------------------- | -------------------------------------------- | ------------------ |
| `SYSTEMS_CACHE_TTL`     | Cache time-to-live for system data (seconds) | `86400` (24 hours) |
| `STATIC_INFO_CACHE_TTL` | Cache time-to-live for static info (seconds) | `604800` (7 days)  |

## Implementation Details

1. Each feature has a dedicated configuration structure with:

   - `enabled_var`: Environment variable that controls whether the feature is enabled
   - `channel_var`: Environment variable for the Discord channel for that feature
   - `default_enabled`: Default enablement status if the environment variable is not set
   - `description`: Human-readable description of the feature

2. Feature enablement logic:

   - The `feature_enabled?/1` function checks if a specific feature is enabled
   - For each feature, a shorthand helper function exists (e.g., `kill_notifications_enabled?`)
   - Default values are used when environment variables are not set

3. Channel resolution strategy:

   - Each notification checks for a feature-specific channel first
   - If not found, it falls back to the main channel defined by `DISCORD_CHANNEL_ID`
   - The `discord_channel_id_for/1` function encapsulates this logic

4. Slack webhook resolution:
   - Each feature can have a dedicated Slack webhook URL
   - If a feature-specific webhook is not found, it falls back to the main webhook
   - The logic is similar to the Discord channel resolution

# Port Configuration

The application uses the following ports which can be configured via environment variables:

| Variable             | Description        | Default |
| -------------------- | ------------------ | ------- |
| `PORT`               | Web server port    | `4000`  |
| `CHART_SERVICE_PORT` | Chart service port | `3001`  |

Note that while these ports are exposed in the Docker container (EXPOSE 4000 3001), the actual
ports used by the application are determined by these environment variables. If you change
these values, you'll need to map the corresponding ports when running the container.

Example:

```bash
# Running with custom ports
docker run -e PORT=8080 -e CHART_SERVICE_PORT=8081 -p 8080:8080 -p 8081:8081 guarzo/wanderer-notifier:latest
```
