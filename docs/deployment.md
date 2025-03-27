# Wanderer Notifier Deployment Guide

## Deployment Options

Wanderer Notifier can be deployed in two main configurations:

1. **Basic Deployment**: Without database features (no kill charts)
2. **Full Deployment**: With database features (includes kill charts)

## Environment Variables

Wanderer Notifier uses a standardized environment variable naming convention with the `WANDERER_` prefix.
All environment variables are optional if they have defaults, or required as indicated below.

### Required Environment Variables

| Variable Name                 | Description                          | Example                                                 |
| ----------------------------- | ------------------------------------ | ------------------------------------------------------- |
| `WANDERER_DISCORD_BOT_TOKEN`  | Discord bot token                    | `MTMyNDg3ODM1NDc5NjY0NjQ1MQ.GrhZfw.x90wac-uZPO9bwIT...` |
| `WANDERER_DISCORD_CHANNEL_ID` | Discord channel ID for notifications | `971101320138350603`                                    |
| `WANDERER_LICENSE_KEY`        | License key for Wanderer Notifier    | `42e0c37b-6a9c-42aa-9fcd-ca5931710454`                  |
| `WANDERER_MAP_URL`            | URL to the Wanderer map              | `https://wanderer.example.com/your-map-name`            |
| `WANDERER_MAP_TOKEN`          | Token for Wanderer map access        | `f8e4a6cc-e432-49aa-a3e8-29ee25d2a9da`                  |

### Optional Environment Variables

| Variable Name                   | Description                | Default     |
| ------------------------------- | -------------------------- | ----------- |
| `WANDERER_PORT`                 | Port for the web server    | `4000`      |
| `WANDERER_HOST`                 | Host for the web server    | `localhost` |
| `WANDERER_SCHEME`               | URL scheme (http/https)    | `http`      |
| `WANDERER_FEATURE_KILL_CHARTS`  | Enable kill charts feature | `false`     |
| `WANDERER_FEATURE_MAP_CHARTS`   | Enable map charts feature  | `false`     |
| `WANDERER_FEATURE_TRACK_KSPACE` | Track K-space systems      | `true`      |

### Database Configuration (when using kill charts)

| Variable Name          | Description       | Default             |
| ---------------------- | ----------------- | ------------------- |
| `WANDERER_DB_USER`     | Database username | `postgres`          |
| `WANDERER_DB_PASSWORD` | Database password | `postgres`          |
| `WANDERER_DB_HOST`     | Database hostname | `postgres`          |
| `WANDERER_DB_NAME`     | Database name     | `wanderer_notifier` |
| `WANDERER_DB_PORT`     | Database port     | `5432`              |

## Basic Deployment (No Database)

For a simple deployment without kill charts and database functionality:

```bash
# Create a .env file with your configuration
cp .env.template .env
# Edit the .env file with your values
nano .env

# Start the application
docker-compose up -d
```

## Full Deployment (With Database)

For a deployment with kill charts and database functionality:

```bash
# Create a .env file with your configuration
cp .env.template .env
# Edit the .env file with your values
nano .env

# Start the application with database
docker-compose -f docker-compose-db.yml up -d
```

## Database Operations

The following database operations are available when using the database deployment:

### Database Backup

Create a backup of the database:

```bash
docker-compose -f docker-compose-db.yml --profile backup up -d db_backup
```

The backup will be stored in the `/app/data/backups` directory within the container, which is mapped to the `wanderer_data` volume.

### Manual Database Operations

Run custom database operations using the `db_operations.sh` script:

```bash
# Initialize database
docker-compose -f docker-compose-db.yml exec wanderer_notifier /app/bin/db_operations.sh init

# Run migrations
docker-compose -f docker-compose-db.yml exec wanderer_notifier /app/bin/db_operations.sh migrate

# Verify database connectivity
docker-compose -f docker-compose-db.yml exec wanderer_notifier /app/bin/db_operations.sh verify
```

## Legacy Environment Variables

For backward compatibility, the application still supports legacy environment variable names without the `WANDERER_` prefix.
However, it's recommended to use the new naming convention for all new deployments.
