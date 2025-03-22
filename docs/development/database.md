# Database Development Guide

This document provides guidance on working with the PostgreSQL database for development in the WandererNotifier application.

## Overview

WandererNotifier uses PostgreSQL with Ash Framework for persistence of killmail data. The database is optional and can be enabled or disabled via environment variables.

## Setting Up Development Environment

### Enabling Persistence in Devcontainer

The development container is configured to support optional PostgreSQL persistence. To enable it:

1. Open the `.devcontainer/devcontainer.json` file
2. Find the `containerEnv` section and uncomment the `ENABLE_PERSISTENCE` line:

```json
"containerEnv": {
  "ENABLE_PERSISTENCE": "true"
}
```

3. Rebuild or restart the devcontainer to apply the changes

When persistence is enabled, the devcontainer will:

- Start a Postgres container (using the `persistence` profile in Docker Compose)
- Configure the application to connect to the database
- Start the Repo supervisor in the application

### Database Migrations

The database schema is defined in migration files in `priv/repo/migrations/`. To run migrations:

```shell
mix ecto.setup      # Creates the database and runs migrations
mix ecto.reset      # Drops and recreates the database
mix ecto.migrate    # Runs pending migrations
mix ecto.rollback   # Rolls back the last migration
```

### Creating New Migrations

To create a new migration:

```shell
mix ecto.gen.migration <migration_name>
```

This will create a new migration file in `priv/repo/migrations/` with a timestamp prefix.

## Working with Data

### Ash Resources

The application uses the following Ash Resources:

1. `WandererNotifier.Resources.TrackedCharacter` - In-memory ETS-based resource for tracked characters
2. `WandererNotifier.Resources.Killmail` - PostgreSQL-based resource for persisted killmails
3. `WandererNotifier.Resources.KillmailStatistic` - PostgreSQL-based resource for aggregated statistics

### Common Database Tasks

#### Querying Killmails

```elixir
# Get killmails for a specific character
alias WandererNotifier.Resources.Killmail
alias WandererNotifier.Resources.Api

# Last 7 days
from = DateTime.utc_now() |> DateTime.add(-7, :day)
to = DateTime.utc_now()

# Get the killmails
killmails = Killmail.list_for_character(character_id, from, to, 100)
```

#### Generating Statistics

```elixir
alias WandererNotifier.Resources.KillmailStatistic
alias WandererNotifier.Resources.Api

# Create or update statistics
attrs = %{
  period_type: :daily,
  period_start: ~D[2024-06-01],
  period_end: ~D[2024-06-01],
  character_id: 123456,
  character_name: "Character Name",
  kills_count: 10,
  deaths_count: 2
}

KillmailStatistic.create(attrs)
```

## Database Configuration

The database connection is configured in the following files:

- `config/config.exs` - Default configuration
- `config/runtime.exs` - Runtime configuration based on environment variables
- `config/dev.exs` - Development-specific configuration

### Environment Variables

The following environment variables control database behavior:

- `ENABLE_PERSISTENCE` - Set to "true" to enable persistence
- `POSTGRES_HOST` - Hostname of the PostgreSQL server (default: "postgres")
- `POSTGRES_PORT` - Port of the PostgreSQL server (default: "5432")
- `POSTGRES_USER` - Username for PostgreSQL (default: "postgres")
- `POSTGRES_PASSWORD` - Password for PostgreSQL (default: "postgres")
- `POSTGRES_DB` - Database name (default: "wanderer_notifier_dev" in development)
- `PERSISTENCE_RETENTION_DAYS` - Number of days to retain individual killmails (default: "180")

## Common Issues and Solutions

### Missing Database

If you encounter errors about the database not existing, run:

```shell
mix ecto.create
```

### Connection Errors

If you encounter connection errors, check:

1. The `ENABLE_PERSISTENCE` variable is set to "true"
2. The Postgres container is running (check with `docker ps`)
3. The connection details (host, port, username, password) are correct

### Database Not Starting

If the Postgres container doesn't start:

1. Check the Docker Compose logs: `docker-compose logs postgres`
2. Ensure the volume mounts are properly configured
3. Check if another service is already using port 5432

### Schema Changes

If your schema changes don't seem to be applied:

1. Make sure you've run `mix ecto.migrate`
2. Check the migration version to ensure it was run
3. Check the database schema directly using a tool like `psql` or using the `mix ecto.dump` command
