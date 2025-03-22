# Kill Data Persistence Implementation Plan

## Overview

This document outlines the implementation plan for persisting killmail information related to tracked characters in the WandererNotifier application. This feature will enable historical charting and analysis capabilities.

## Goals

- Store killmail data related to tracked characters only
- Use PostgreSQL for efficient data storage
- Implement Ash Resources for a standardized data access layer
- Create a well-designed data model optimized for historical querying
- Enable future historical charting capabilities
- Make persistence feature optional via environment variables

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
    attribute :related_character_id, :integer
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
      attribute_writable?: true,
      define_field?: false,
      source_attribute: :related_character_id,
      destination_attribute: :character_id
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
    attribute :region_activity, :map

    # Ship type usage
    attribute :ship_usage, :map
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
  rescue
    exception ->
      Logger.error("[KillmailPersistence] Exception persisting killmail: #{Exception.message(exception)}")
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
    Killmail
    |> Ash.Query.filter(related_character_id == ^character_id and
                       kill_time >= ^from_date and
                       kill_time <= ^to_date)
    |> Ash.Query.sort(kill_time: :desc)
    |> Ash.Query.limit(^limit)
    |> Api.read!()
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
      killmail_id: killmail.killmail_id,
      kill_time: kill_time,
      solar_system_id: solar_system_id,
      solar_system_name: solar_system_name,
      total_value: total_value,
      character_role: role,
      related_character_id: character_id,
      related_character_name: character_name,
      ship_type_id: ship_type_id,
      ship_type_name: ship_type_name,
      zkb_data: zkb_data,
      victim_data: victim,
      attacker_data: role == :attacker && find_attacker_by_character_id(killmail, character_id) || nil
    }
  end

  # Creates a new killmail record using Ash
  defp create_killmail_record(attrs) do
    Killmail
    |> Ash.Changeset.for_create(:create, attrs)
    |> Api.create()
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
    image: wanderer-notifier
    environment:
      - ENABLE_PERSISTENCE=${ENABLE_PERSISTENCE:-false}
      - POSTGRES_HOST=${POSTGRES_HOST:-postgres}
      - POSTGRES_USER=${POSTGRES_USER:-postgres}
      - POSTGRES_PASSWORD=${POSTGRES_PASSWORD:-postgres}
      - POSTGRES_DB=${POSTGRES_DB:-wanderer_notifier}
    depends_on:
      postgres:
        condition: service_started
        required: false

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

volumes:
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
        children ++ [WandererNotifier.Repo]
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
