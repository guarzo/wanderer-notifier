# Example Environment Files

This document provides example environment configurations for different deployment scenarios.

## Development Environment

```bash
# Database Configuration
WANDERER_DB_USERNAME=postgres
WANDERER_DB_PASSWORD=postgres
WANDERER_DB_HOSTNAME=localhost
WANDERER_DB_NAME=wanderer_notifier_dev
WANDERER_DB_PORT=5432
WANDERER_DB_POOL_SIZE=10

# Web Server Configuration
WANDERER_WEB_PORT=4000
WANDERER_WEB_HOST=localhost
WANDERER_PUBLIC_URL=http://localhost:4000

# API Settings
WANDERER_MAP_URL=https://map-api.example.com
WANDERER_MAP_TOKEN=your_map_token_here
WANDERER_NOTIFIER_API_TOKEN=your_notifier_token_here

# License Manager
WANDERER_LICENSE_MANAGER_URL=https://license-manager.example.com

# Discord Settings
WANDERER_DISCORD_MAIN_CHANNEL=1234567890123456789
WANDERER_DISCORD_KILL_CHANNEL=1234567890123456789
WANDERER_DISCORD_BOT_TOKEN=your_discord_bot_token

# Feature Flags
WANDERER_FEATURE_TRACK_KSPACE=true
WANDERER_FEATURE_KILL_NOTIFICATIONS=true
WANDERER_FEATURE_CHARACTER_TRACKING=true
WANDERER_FEATURE_SYSTEM_TRACKING=true

# Debug Settings
WANDERER_DEBUG_LOGGING=false
```

## Testing Environment

```bash
# Database Configuration (using a separate test database)
WANDERER_DB_USERNAME=postgres
WANDERER_DB_PASSWORD=postgres
WANDERER_DB_HOSTNAME=localhost
WANDERER_DB_NAME=wanderer_notifier_test
WANDERER_DB_PORT=5432
WANDERER_DB_POOL_SIZE=10

# Web Server Configuration
WANDERER_WEB_PORT=4001
WANDERER_WEB_HOST=localhost

# Feature Flags
WANDERER_FEATURE_TRACK_KSPACE=true
WANDERER_FEATURE_KILL_NOTIFICATIONS=true
WANDERER_FEATURE_CHARACTER_TRACKING=true

# Debug Settings
WANDERER_DEBUG_LOGGING=false
```

## Production Environment

```bash
# Database Configuration
WANDERER_DB_USERNAME=production_user
WANDERER_DB_PASSWORD=strong_production_password
WANDERER_DB_HOSTNAME=production-db.internal
WANDERER_DB_NAME=wanderer_notifier_prod
WANDERER_DB_PORT=5432
WANDERER_DB_POOL_SIZE=20

# Web Server Configuration
WANDERER_WEB_PORT=4000
WANDERER_WEB_HOST=0.0.0.0
WANDERER_PUBLIC_URL=https://your-production-domain.com

# API Settings
WANDERER_MAP_URL=https://map-api.production.com
WANDERER_MAP_TOKEN=your_production_map_token
WANDERER_NOTIFIER_API_TOKEN=your_production_notifier_token

# License Manager
WANDERER_LICENSE_MANAGER_URL=https://license-manager.production.com

# Discord Settings
WANDERER_DISCORD_MAIN_CHANNEL=1234567890123456789
WANDERER_DISCORD_KILL_CHANNEL=1234567890123456789
WANDERER_DISCORD_BOT_TOKEN=your_production_discord_bot_token

# Feature Flags
WANDERER_FEATURE_TRACK_KSPACE=true
WANDERER_FEATURE_KILL_NOTIFICATIONS=true
WANDERER_FEATURE_CHARACTER_TRACKING=true
WANDERER_FEATURE_SYSTEM_TRACKING=true

# Debug Settings (disabled in production)
WANDERER_DEBUG_LOGGING=false

# SSL Configuration (when using direct SSL, not behind a proxy)
WANDERER_SSL_KEY_PATH=/path/to/ssl/key.pem
WANDERER_SSL_CERT_PATH=/path/to/ssl/cert.pem
```

## Docker-Compose Environment

```yaml
version: "3"
services:
  app:
    image: wanderer-notifier:latest
    ports:
      - "4000:4000"
    environment:
      # Database Configuration
      - WANDERER_DB_USERNAME=postgres
      - WANDERER_DB_PASSWORD=postgres
      - WANDERER_DB_HOSTNAME=db
      - WANDERER_DB_NAME=wanderer_notifier
      - WANDERER_DB_PORT=5432
      - WANDERER_DB_POOL_SIZE=10

      # Web Server Configuration
      - WANDERER_WEB_PORT=4000
      - WANDERER_WEB_HOST=0.0.0.0
      - WANDERER_PUBLIC_URL=http://localhost:4000

      # API Settings
      - WANDERER_MAP_URL=https://map-api.example.com
      - WANDERER_MAP_TOKEN=your_map_token_here
      - WANDERER_NOTIFIER_API_TOKEN=your_notifier_token_here

      # License Manager
      - WANDERER_LICENSE_MANAGER_URL=https://license-manager.example.com

      # Discord Settings
      - WANDERER_DISCORD_MAIN_CHANNEL=1234567890123456789
      - WANDERER_DISCORD_KILL_CHANNEL=1234567890123456789
      - WANDERER_DISCORD_BOT_TOKEN=your_discord_bot_token

      # Feature Flags
      - WANDERER_FEATURE_TRACK_KSPACE=true
      - WANDERER_FEATURE_KILL_NOTIFICATIONS=true
      - WANDERER_FEATURE_CHARACTER_TRACKING=true
      - WANDERER_FEATURE_SYSTEM_TRACKING=true

    depends_on:
      - db

  db:
    image: postgres:14
    environment:
      - POSTGRES_USER=postgres
      - POSTGRES_PASSWORD=postgres
      - POSTGRES_DB=wanderer_notifier
    volumes:
      - postgres_data:/var/lib/postgresql/data

volumes:
  postgres_data:
```

## Configuration Tips

1. **Security**: In production, use environment variables from a secure source like Kubernetes secrets or a secrets manager
2. **Documentation**: Keep an up-to-date record of all environment variables used in the application
3. **Validation**: The application validates configurations on startup and will warn about missing or invalid values
4. **Deprecation**: Legacy environment variables are still supported but will display deprecation warnings
5. **Docker**: When using Docker, use environment files or Docker secrets for sensitive data
