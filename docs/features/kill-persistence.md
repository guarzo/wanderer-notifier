# Kill Data Persistence Implementation Plan

## Overview

This document outlines the implementation plan for persisting killmail information related to tracked characters in the WandererNotifier application. This feature enables historical charting and analysis capabilities, and is now referred to as "Kill Charts".

## Goals

- Store killmail data related to tracked characters only
- Use PostgreSQL for efficient data storage
- Implement Ash Resources for a standardized data access layer
- Create a well-designed data model optimized for historical querying
- Enable killmail chart capabilities
- Make kill charts feature optional via environment variables

## Implementation Notes

### Removed Chart Types

As part of the consolidation of features, the following map-based chart types have been removed:

- `activity_timeline` - Activity trends over time (removed)
- `activity_distribution` - Distribution of activity types (removed)

The application now supports only the following chart types:

- `activity_summary` - Character Activity Summary
- `weekly_kills` - Weekly Character Kills

## Data Model

### Core Resources

#### 1. `TrackedCharacter`

```elixir
defmodule WandererNotifier.Resources.TrackedCharacter do
  use Ash.Resource,
    data_layer: Ash.DataLayer.Ets

  attributes do
    uuid_primary_key :id
    attribute :character_id, :integer, allow_nil?: false
    attribute :character_name, :string
    attribute :corporation_id, :integer
    attribute :corporation_name, :string
    attribute :alliance_id, :integer
    attribute :alliance_name, :string
    attribute :tracked_since, :utc_datetime_usec, default: &DateTime.utc_now/0
  end

  relationships do
    has_many :killmails, WandererNotifier.Resources.Killmail,
      destination_attribute: :related_character_id
  end
end
```

#### 2. `Killmail`

```elixir
defmodule WandererNotifier.Resources.Killmail do
  use Ash.Resource,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "killmails"
    repo WandererNotifier.Repo
  end

  attributes do
    uuid_primary_key :id
    attribute :killmail_id, :integer, allow_nil?: false
    attribute :kill_time, :utc_datetime_usec
    attribute :solar_system_id, :integer
    attribute :solar_system_name, :string
    attribute :region_id, :integer
    attribute :region_name, :string
    attribute :total_value, :decimal

    # Character was victim or attacker
    attribute :character_role, :atom, constraints: [one_of: [:attacker, :victim]]

    # Character details duplicated for query efficiency
    attribute :related_character_id, :integer, allow_nil?: false
    attribute :related_character_name, :string

    # Ship information
    attribute :ship_type_id, :integer
    attribute :ship_type_name, :string

    # JSON fields for additional data
    attribute :zkb_data, :map
    attribute :victim_data, :map
    attribute :attacker_data, :map

    # Metadata
    attribute :processed_at, :utc_datetime_usec, default: &DateTime.utc_now/0
  end

  relationships do
    belongs_to :character, WandererNotifier.Resources.TrackedCharacter,
      define_field?: false,
      destination_field: :character_id,
      source_field: :related_character_id
  end

  indexes do
    index [:killmail_id], unique: true
    index [:related_character_id, :kill_time]
    index [:solar_system_id, :kill_time]
    index [:character_role, :kill_time]
  end
end
```

### Supporting Resources

#### 3. `KillmailStatistic`

```elixir
defmodule WandererNotifier.Resources.KillmailStatistic do
  use Ash.Resource,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "killmail_statistics"
    repo WandererNotifier.Repo
  end

  attributes do
    uuid_primary_key :id

    # Aggregation period
    attribute :period_type, :atom, constraints: [one_of: [:daily, :weekly, :monthly]]
    attribute :period_start, :date
    attribute :period_end, :date

    # Character information
    attribute :character_id, :integer, allow_nil?: false
    attribute :character_name, :string

    # Statistics
    attribute :kills_count, :integer, default: 0
    attribute :deaths_count, :integer, default: 0
    attribute :isk_destroyed, :decimal, default: 0
    attribute :isk_lost, :decimal, default: 0

    # Activity breakdown by region
    attribute :region_activity, :map, default: %{}

    # Ship type usage
    attribute :ship_usage, :map, default: %{}

    # Additional statistics for reporting
    attribute :top_victim_corps, :map, default: %{}
    attribute :top_victim_ships, :map, default: %{}
    attribute :detailed_ship_usage, :map, default: %{}
  end

  indexes do
    index [:character_id, :period_type, :period_start], unique: true
  end
end
```

## Implementation Steps

### Phase 1: Database Setup and Configuration

1. **Add Database Dependencies**

   - Add Ecto, Ash, and AshPostgres to the project dependencies
   - Update configuration files for database connection

2. **Create Database Migration**

   - Create migrations for the Killmail and KillmailStatistic tables
   - Set up appropriate indexes for performance

3. **Configure Ash Registry**

   - Create Ash Registry for the application
   - Configure appropriate APIs for different resource groups

4. **Make Persistence Optional**
   - Update Docker configuration to make Postgres container optional
   - Add environment variable controls for persistence feature
   - Modify application startup to conditionally start the Repo
   - Update devcontainer configuration for development

### Phase 2: Core Implementation

5. **Implement Ash Resources**

   - Implement TrackedCharacter resource
   - Implement Killmail resource
   - Implement KillmailStatistic resource

6. **Create Killmail Persistence Service**

   - Create a service to handle killmail persistence logic
   - Implement filtering to save only tracked character killmails
   - Handle data transformation from existing Killmail struct to Ash resource

7. **Integrate with Existing Kill Processing Pipeline**
   - Modify the kill processor to persist killmails for tracked characters
   - Add feature flag for enabling/disabling persistence
   - Ensure error handling doesn't disrupt existing notification flow

### Phase 3: Data Management and Optimization

8. **Implement Data Retention Policies**

   - Create scheduled task for aggregating older killmail data
   - Implement data cleanup for old individual killmails
   - Configure retention periods through application config

9. **Create Aggregation Service**

   - Implement service to generate daily/weekly/monthly statistics
   - Create scheduled job to update statistics regularly

10. **Optimize Query Performance**
    - Analyze and optimize common query patterns
    - Add additional indexes if needed after real-world usage

### Phase 4: API and Monitoring

11. **Create API Endpoints for Historical Data**

    - Implement API controllers for retrieving killmail history
    - Add endpoints for statistics and aggregated data

12. **Add Monitoring and Metrics**
    - Track database size and growth
    - Monitor query performance
    - Add health check endpoints

## Development Environment

### Devcontainer Configuration

The devcontainer has been configured to support optional PostgreSQL persistence:

1. A Docker Compose configuration (`docker-compose.yml`) defines both the app container and an optional Postgres container with a profile.
2. The devcontainer.json file is configured to use this Docker Compose setup.
3. The Postgres container is only started when the `persistence` profile is activated.
4. Persistence can be enabled by uncommenting the `ENABLE_PERSISTENCE` environment variable in the devcontainer.json file.

### Using Persistence in Development

To enable persistence during development:

1. Edit `.devcontainer/devcontainer.json` and uncomment:
   ```json
   "containerEnv": {
     "ENABLE_PERSISTENCE": "true"
   }
   ```
2. Rebuild the devcontainer to start with Postgres enabled
3. Run database migrations:
   ```shell
   mix ecto.setup
   ```

For more details, see [Database Development Guide](../development/database.md).

## Killmail Persistence Service Implementation

### API Configuration Example

```elixir
defmodule WandererNotifier.Resources.Api do
  use Ash.Api

  resources do
    resource WandererNotifier.Resources.TrackedCharacter
    resource WandererNotifier.Resources.Killmail
    resource WandererNotifier.Resources.KillmailStatistic
  end
end
```

### Killmail Persistence Service

```elixir
defmodule WandererNotifier.Resources.KillmailPersistence do
  @moduledoc """
  Service for persisting killmail information related to tracked characters.
  Only killmails involving tracked characters are stored in the database.
  """

  require Logger
  alias WandererNotifier.Data.Killmail, as: KillmailStruct
  alias WandererNotifier.Resources.Api
  alias WandererNotifier.Resources.Killmail
  alias WandererNotifier.Data.Cache.Repository, as: CacheRepo

  @doc """
  Persists killmail data if it's related to a tracked character.

  ## Parameters
    - killmail: The killmail struct to persist

  ## Returns
    - {:ok, persisted_killmail} if successful
    - {:error, reason} if persistence fails
    - :ignored if the killmail is not related to a tracked character
  """
  def maybe_persist_killmail(%KillmailStruct{} = killmail) do
    # Check if persistence is enabled
    if persistence_enabled?() do
      # First check if the killmail involves any tracked characters
      with tracked_characters <- get_tracked_characters(),
           {character_id, character_name, role} <- find_tracked_character_in_killmail(killmail, tracked_characters),
           true <- not is_nil(character_id) do
        # We found a tracked character in the killmail, persist it
        Logger.debug("[KillmailPersistence] Persisting killmail #{killmail.killmail_id} for character #{character_id}")

        # Transform the killmail struct to the Ash resource format
        killmail_attrs = transform_killmail_to_resource(killmail, character_id, character_name, role)

        # Insert into database via Ash framework
        case create_killmail_record(killmail_attrs) do
          {:ok, record} ->
            Logger.info("[KillmailPersistence] Successfully persisted killmail #{killmail.killmail_id}")
            {:ok, record}

          {:error, error} ->
            Logger.error("[KillmailPersistence] Failed to persist killmail #{killmail.killmail_id}: #{inspect(error)}")
            {:error, error}
        end
      else
        _ ->
          # Killmail doesn't involve a tracked character, ignore it
          :ignored
      end
    else
      # Persistence disabled, skip
      :ignored
    end
  rescue
    exception ->
      Logger.error("[KillmailPersistence] Exception persisting killmail: #{Exception.message(exception)}")
      Logger.error(Exception.format_stacktrace())
      {:error, exception}
  end

  @doc """
  Gets all killmails for a specific character within a date range.

  ## Parameters
    - character_id: The character ID to get killmails for
    - from_date: Start date for the query (DateTime)
    - to_date: End date for the query (DateTime)
    - limit: Maximum number of results to return

  ## Returns
    - List of killmail records
  """
  def get_character_killmails(character_id, from_date, to_date, limit \\ 100) do
    try do
      Killmail.list_for_character(character_id, from_date, to_date, limit)
    rescue
      e ->
        Logger.error("[KillmailPersistence] Error fetching killmails: #{Exception.message(e)}")
        []
    end
  end

  # Gets list of tracked characters from the cache
  defp get_tracked_characters do
    CacheRepo.get("map:characters") || []
  end

  # Looks for tracked characters in the killmail
  # Returns {character_id, character_name, role} if found, nil otherwise
  defp find_tracked_character_in_killmail(%KillmailStruct{} = killmail, tracked_characters) do
    # Check if a tracked character is the victim
    victim = KillmailStruct.get_victim(killmail)
    victim_character_id = victim && Map.get(victim, "character_id")

    if victim_character_id && is_tracked_character?(victim_character_id, tracked_characters) do
      {victim_character_id, Map.get(victim, "character_name"), :victim}
    else
      # Check if a tracked character is among the attackers
      attackers = KillmailStruct.get(killmail, "attackers") || []

      Enum.find_value(attackers, fn attacker ->
        attacker_character_id = Map.get(attacker, "character_id")

        if attacker_character_id && is_tracked_character?(attacker_character_id, tracked_characters) do
          {attacker_character_id, Map.get(attacker, "character_name"), :attacker}
        else
          nil
        end
      end)
    end
  end

  # Checks if a character ID is in the list of tracked characters
  defp is_tracked_character?(character_id, tracked_characters) do
    Enum.any?(tracked_characters, fn tracked ->
      tracked["character_id"] == character_id ||
      to_string(tracked["character_id"]) == to_string(character_id)
    end)
  end

  # Transforms a killmail struct to the format needed for the Ash resource
  defp transform_killmail_to_resource(%KillmailStruct{} = killmail, character_id, character_name, role) do
    # Extract killmail data
    kill_time = get_kill_time(killmail)
    solar_system_id = KillmailStruct.get_system_id(killmail)
    solar_system_name = KillmailStruct.get(killmail, "solar_system_name")

    # Extract victim data
    victim = KillmailStruct.get_victim(killmail) || %{}

    # Get ZKB data
    zkb_data = killmail.zkb || %{}
    total_value = Map.get(zkb_data, "totalValue")

    # Get ship information depending on the character's role
    {ship_type_id, ship_type_name} =
      case role do
        :victim ->
          {
            Map.get(victim, "ship_type_id"),
            Map.get(victim, "ship_type_name")
          }
        :attacker ->
          attacker = find_attacker_by_character_id(killmail, character_id)
          {
            Map.get(attacker || %{}, "ship_type_id"),
            Map.get(attacker || %{}, "ship_type_name")
          }
      end

    # Build the resource attributes map
    %{
      killmail_id: parse_integer(killmail.killmail_id),
      kill_time: kill_time,
      solar_system_id: parse_integer(solar_system_id),
      solar_system_name: solar_system_name,
      total_value: parse_decimal(total_value),
      character_role: role,
      related_character_id: parse_integer(character_id),
      related_character_name: character_name,
      ship_type_id: parse_integer(ship_type_id),
      ship_type_name: ship_type_name,
      zkb_data: zkb_data,
      victim_data: victim,
      attacker_data: role == :attacker && find_attacker_by_character_id(killmail, character_id) || nil
    }
  end

  # Helper function to parse integer values, handling string inputs
  defp parse_integer(nil), do: nil
  defp parse_integer(value) when is_integer(value), do: value
  defp parse_integer(value) when is_binary(value) do
    case Integer.parse(value) do
      {int, _} -> int
      :error -> nil
    end
  end
  defp parse_integer(_), do: nil

  # Helper function to parse decimal values
  defp parse_decimal(nil), do: nil
  defp parse_decimal(value) when is_integer(value), do: Decimal.new(value)
  defp parse_decimal(value) when is_float(value), do: Decimal.from_float(value)
  defp parse_decimal(value) when is_binary(value) do
    case Decimal.parse(value) do
      {:ok, decimal} -> decimal
      _ -> nil
    end
  end
  defp parse_decimal(_), do: nil

  # Creates a new killmail record using Ash
  defp create_killmail_record(attrs) do
    Killmail.create(attrs)
  end

  # Extracts kill time from the killmail
  defp get_kill_time(%KillmailStruct{} = killmail) do
    case KillmailStruct.get(killmail, "killmail_time") do
      nil -> DateTime.utc_now()
      time when is_binary(time) ->
        case DateTime.from_iso8601(time) do
          {:ok, datetime, _} -> datetime
          _ -> DateTime.utc_now()
        end
      _ -> DateTime.utc_now()
    end
  end

  # Finds an attacker in the killmail by character ID
  defp find_attacker_by_character_id(%KillmailStruct{} = killmail, character_id) do
    attackers = KillmailStruct.get(killmail, "attackers") || []

    Enum.find(attackers, fn attacker ->
      attacker_id = Map.get(attacker, "character_id")
      to_string(attacker_id) == to_string(character_id)
    end)
  end

  # Check if persistence feature is enabled
  defp persistence_enabled? do
    Application.get_env(:wanderer_notifier, :persistence, [])
    |> Keyword.get(:enabled, false)
  end
end
```

## Docker Configuration

### Optional Postgres Container

Update the Docker Compose configuration to make the Postgres container optional using profiles:

```yaml
version: "3.8"
services:
  app:
    # Main application container
    build:
      context: .
      dockerfile: Dockerfile
    environment:
      - ENABLE_PERSISTENCE=${ENABLE_PERSISTENCE:-false}
      - POSTGRES_HOST=${POSTGRES_HOST:-postgres}
      - POSTGRES_USER=${POSTGRES_USER:-postgres}
      - POSTGRES_PASSWORD=${POSTGRES_PASSWORD:-postgres}
      - POSTGRES_DB=${POSTGRES_DB:-wanderer_notifier}
      - MIX_ENV=${MIX_ENV:-prod}
    ports:
      - "${PORT:-4000}:4000"
    depends_on:
      postgres:
        condition: service_started
        required: false
    volumes:
      - app_data:/app/data

  postgres:
    image: postgres:14
    profiles:
      - persistence
    environment:
      - POSTGRES_USER=${POSTGRES_USER:-postgres}
      - POSTGRES_PASSWORD=${POSTGRES_PASSWORD:-postgres}
      - POSTGRES_DB=${POSTGRES_DB:-wanderer_notifier}
    volumes:
      - postgres_data:/var/lib/postgresql/data
    ports:
      - "${POSTGRES_PORT:-5432}:5432"

volumes:
  app_data:
  postgres_data:
```

With this configuration, you can start the application with or without persistence:

- With persistence: `ENABLE_PERSISTENCE=true docker-compose --profile persistence up`
- Without persistence: `docker-compose up`

### Conditional Application Startup

Modify the application startup to conditionally include the Repo in the supervision tree:

```elixir
defmodule WandererNotifier.Application do
  # ...

  def start(_type, _args) do
    children = [
      # ... other children
    ]

    # Conditionally add Postgres repo to supervision tree
    children =
      if persistence_enabled?() do
        children ++ [WandererNotifier.Repo, []]
      else
        children
      end

    # ...
  end

  defp persistence_enabled? do
    Application.get_env(:wanderer_notifier, :persistence, [])
    |> Keyword.get(:enabled, false)
  end
end
```

## Database Setup Example

### Migration File Example

```elixir
defmodule WandererNotifier.Repo.Migrations.CreateKillmailsTables do
  use Ecto.Migration

  def change do
    create table(:killmails, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :killmail_id, :bigint, null: false
      add :kill_time, :utc_datetime_usec
      add :solar_system_id, :integer
      add :solar_system_name, :string
      add :region_id, :integer
      add :region_name, :string
      add :total_value, :decimal, precision: 20, scale: 2

      add :character_role, :string, null: false
      add :related_character_id, :integer, null: false
      add :related_character_name, :string

      add :ship_type_id, :integer
      add :ship_type_name, :string

      add :zkb_data, :map
      add :victim_data, :map
      add :attacker_data, :map

      add :processed_at, :utc_datetime_usec, null: false

      timestamps()
    end

    create unique_index(:killmails, [:killmail_id])
    create index(:killmails, [:related_character_id, :kill_time])
    create index(:killmails, [:solar_system_id, :kill_time])
    create index(:killmails, [:character_role, :kill_time])

    create table(:killmail_statistics, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :period_type, :string, null: false
      add :period_start, :date, null: false
      add :period_end, :date, null: false

      add :character_id, :integer, null: false
      add :character_name, :string

      add :kills_count, :integer, default: 0
      add :deaths_count, :integer, default: 0
      add :isk_destroyed, :decimal, precision: 20, scale: 2, default: 0
      add :isk_lost, :decimal, precision: 20, scale: 2, default: 0

      add :region_activity, :map
      add :ship_usage, :map
      add :top_victim_corps, :map
      add :top_victim_ships, :map
      add :detailed_ship_usage, :map

      timestamps()
    end

    create unique_index(:killmail_statistics, [:character_id, :period_type, :period_start])
  end
end
```

### Repo Setup

```elixir
defmodule WandererNotifier.Repo do
  use Ecto.Repo,
    otp_app: :wanderer_notifier,
    adapter: Ecto.Adapters.Postgres
end
```

### Runtime Configuration Example

Update the runtime configuration to conditionally set up the database connection:

```elixir
# In config/runtime.exs
persistence_enabled = String.to_existing_atom(System.get_env("ENABLE_PERSISTENCE", "false"))

if persistence_enabled do
  config :wanderer_notifier, WandererNotifier.Repo,
    username: System.get_env("POSTGRES_USER", "postgres"),
    password: System.get_env("POSTGRES_PASSWORD", "postgres"),
    hostname: System.get_env("POSTGRES_HOST", "localhost"),
    database: System.get_env("POSTGRES_DB", "wanderer_notifier_#{config_env()}"),
    port: String.to_integer(System.get_env("POSTGRES_PORT", "5432")),
    pool_size: String.to_integer(System.get_env("POSTGRES_POOL_SIZE", "10"))
end

# Configure the persistence feature
config :wanderer_notifier, :persistence,
  enabled: persistence_enabled,
  retention_period_days: String.to_integer(System.get_env("PERSISTENCE_RETENTION_DAYS", "180")),
  aggregation_schedule: System.get_env("PERSISTENCE_AGGREGATION_SCHEDULE", "0 0 * * *")

# Ash Registry Configuration
config :wanderer_notifier, :ash_apis, [
  WandererNotifier.Resources.Api
]
```

## Feature Flag Configuration

Add the following configuration options:

```elixir
config :wanderer_notifier, :persistence,
  enabled: true,
  retention_period_days: 180,
  aggregation_schedule: "0 0 * * *" # Daily at midnight
```

The kill charts feature can also be enabled directly with the newer feature flag:

```elixir
# Feature flags
ENABLE_KILL_CHARTS=true
```

## Migration and Data Backfill Strategy

1. Deploy database schema changes
2. Enable persistence with feature flag
3. Create backfill task to process historical data (optional)
4. Run initial aggregation job

## Testing Strategy

1. Unit tests for resource validation and business logic
2. Integration tests for persistence service
3. Performance tests for high-volume scenarios
4. End-to-end tests for API endpoints

## Integration with Existing Services

### KillProcessor Integration Example

```elixir
defmodule WandererNotifier.Services.KillProcessor do
  # ... existing code ...

  alias WandererNotifier.Resources.KillmailPersistence

  # In your process_new_kill function:
  defp process_new_kill(%Killmail{} = killmail, kill_id, state) do
    # Store the kill in the cache
    update_recent_kills(killmail)

    # Persist killmail if the feature is enabled and related to tracked character
    if persistence_enabled?() do
      KillmailPersistence.maybe_persist_killmail(killmail)
    end

    # Process the kill for notification (existing functionality)
    case enrich_and_notify(killmail) do
      :ok ->
        # Mark kill as processed in state
        Map.update(state, :processed_kill_ids, %{kill_id => :os.system_time(:second)}, fn ids ->
          Map.put(ids, kill_id, :os.system_time(:second))
        end)

      {:error, reason} ->
        Logger.error("Error processing kill #{kill_id}: #{reason}")
        state
    end
  end

  defp persistence_enabled? do
    Application.get_env(:wanderer_notifier, :persistence, [])
    |> Keyword.get(:enabled, false)
  end

  # ... existing code ...
end
```

## Killmail Charts

### Weekly Character Kill Charts

A new feature has been added to generate and send weekly charts showing the top 20 characters by number of kills. This feature builds on the kill persistence infrastructure and provides visual insights into character performance.

### Implementation Components

#### 1. `KillmailChartAdapter`

```elixir
defmodule WandererNotifier.ChartService.KillmailChartAdapter do
  @moduledoc """
  Adapter for generating charts from killmail data.

  This module provides functions to create and send charts based on killmail statistics,
  including weekly character performance charts.
  """

  require Logger
  alias WandererNotifier.ChartService.ChartService

  @doc """
  Generates a chart showing the top characters by kills for the past week.

  ## Parameters
    - options: Map of options including:
      - limit: Maximum number of characters to include (default: 20)

  ## Returns
    - {:ok, chart_url} if successful
    - {:error, reason} if chart generation fails
  """
  def generate_weekly_kills_chart(options \\ %{})

  @doc """
  Sends a weekly kills chart to Discord.

  ## Parameters
    - title: Chart title
    - description: Chart description
    - channel_id: Discord channel ID to send to (optional)
    - options: Additional options for chart generation

  ## Returns
    - {:ok, response} if successful
    - {:error, reason} if sending fails
  """
  def send_weekly_kills_chart_to_discord(title, description, channel_id, options \\ %{})
end
```

#### 2. `KillmailChartScheduler`

```elixir
defmodule WandererNotifier.Schedulers.KillmailChartScheduler do
  @moduledoc """
  Schedules and processes weekly killmail charts.

  This scheduler is responsible for generating and sending character kill charts
  at the end of each week. It uses the weekly aggregated statistics to generate
  a visual representation of character performance.
  """

  # Run weekly on Sunday (day 7) at 18:00 UTC
  @default_hour 18
  @default_minute 0

  # Only runs when persistence is enabled
  def persistence_enabled? do
    Application.get_env(:wanderer_notifier, :persistence, [])
    |> Keyword.get(:enabled, false)
  end
end
```

### User Experience

The weekly character kill charts provide a visual representation of character performance, showing:

- Top 20 characters by number of kills in the past week
- Clean bar chart visualization for easy comparison
- Weekly summary sent automatically to the configured Discord channel
- Charts are generated every Sunday at 18:00 UTC

### Configuration

The kill chart scheduler is automatically enabled when persistence is enabled. Additional configuration options:

```elixir
config :wanderer_notifier, :killmail_charts,
  discord_channel_id: "your_channel_id",
  limit: 20  # Number of characters to include in the chart
```

### Future Enhancements

Potential future enhancements for killmail charts include:

- Monthly summary charts
- Ship type distribution charts
- ISK efficiency charts (ISK destroyed vs lost)
- Region activity heatmaps
- Customizable chart scheduling and delivery options
