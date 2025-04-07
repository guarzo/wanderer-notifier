# Killmail Model Consolidation Plan

## Problem Statement

Currently, our application uses two different data structures to represent killmails:

1. `WandererNotifier.Data.Killmail` - A simple struct with three fields:

   ```elixir
   defstruct [:killmail_id, :zkb, :esi_data]
   ```

2. `WandererNotifier.Resources.Killmail` - An Ash resource with 19 fields:
   ```elixir
   attributes do
     uuid_primary_key(:id)
     attribute(:killmail_id, :integer, allow_nil?: false)
     attribute(:kill_time, :utc_datetime_usec)
     attribute(:solar_system_id, :integer)
     attribute(:solar_system_name, :string)
     attribute(:region_id, :integer)
     attribute(:region_name, :string)
     attribute(:total_value, :decimal)
     attribute(:character_role, :atom, constraints: [one_of: @character_roles])
     attribute(:related_character_id, :integer, allow_nil?: false)
     attribute(:related_character_name, :string)
     attribute(:ship_type_id, :integer)
     attribute(:ship_type_name, :string)
     attribute(:zkb_data, :map)
     attribute(:victim_data, :map)
     attribute(:attacker_data, :map)
     attribute(:processed_at, :utc_datetime_usec, default: &DateTime.utc_now/0)
     timestamps()
   end
   ```

This design has several issues:

- Validation happens on the wrong data structure
- Complex transformation logic is needed between models
- Data quality issues arise from inconsistent validation
- Maintainability suffers with two different representations
- Duplicate killmail records are created for each character involved
- No proper normalization of the data

## Goals

1. Consolidate to a single source of truth for killmail data
2. Eliminate the need for complex transformations
3. Ensure validation happens on the data structure that gets persisted
4. Simplify the codebase and improve maintainability
5. Fix data quality issues arising from the current approach
6. Properly normalize the data model to avoid duplication

## Revised Data Model Design

### Normalized Database Model

After analysis of how the data is used in weekly schedulers, charts, and notifications, we've implemented a properly normalized database model:

#### 1. Killmail Resource

This represents a single killmail with all its core information:

```elixir
defmodule WandererNotifier.Resources.Killmail do
  attributes do
    uuid_primary_key(:id)
    attribute(:killmail_id, :integer, allow_nil?: false)
    attribute(:kill_time, :utc_datetime_usec)

    # Economic data (from zKB)
    attribute(:total_value, :decimal)
    attribute(:points, :integer)
    attribute(:is_npc, :boolean, default: false)
    attribute(:is_solo, :boolean, default: false)

    # System information
    attribute(:solar_system_id, :integer)
    attribute(:solar_system_name, :string)
    attribute(:solar_system_security, :float)
    attribute(:region_id, :integer)
    attribute(:region_name, :string)

    # Victim information
    attribute(:victim_id, :integer)
    attribute(:victim_name, :string)
    attribute(:victim_ship_id, :integer)
    attribute(:victim_ship_name, :string)
    attribute(:victim_corporation_id, :integer)
    attribute(:victim_corporation_name, :string)
    attribute(:victim_alliance_id, :integer)
    attribute(:victim_alliance_name, :string)

    # Basic attacker information
    attribute(:attacker_count, :integer)
    attribute(:final_blow_attacker_id, :integer)
    attribute(:final_blow_attacker_name, :string)
    attribute(:final_blow_ship_id, :integer)
    attribute(:final_blow_ship_name, :string)

    # Raw data preservation
    attribute(:zkb_hash, :string)
    attribute(:full_victim_data, :map)    # Keep this for detailed victim information
    attribute(:full_attacker_data, :map)  # Keep this for detailed attacker information

    # Metadata
    attribute(:processed_at, :utc_datetime_usec, default: &DateTime.utc_now/0)
    timestamps()
  end

  identities do
    identity(:unique_killmail, [:killmail_id])
  end
end
```

#### 2. KillmailCharacterInvolvement Resource

This represents the relationship between a tracked character and a killmail:

```elixir
defmodule WandererNotifier.Resources.KillmailCharacterInvolvement do
  attributes do
    uuid_primary_key(:id)
    attribute(:character_role, :atom, constraints: [one_of: [:attacker, :victim]])
    attribute(:character_id, :integer, allow_nil?: false)

    # Character-specific data
    attribute(:ship_type_id, :integer)
    attribute(:ship_type_name, :string)
    attribute(:damage_done, :integer)
    attribute(:is_final_blow, :boolean, default: false)
    attribute(:weapon_type_id, :integer)
    attribute(:weapon_type_name, :string)

    timestamps()
  end

  relationships do
    belongs_to(:killmail, WandererNotifier.Resources.Killmail)
  end

  identities do
    identity(:unique_involvement, [:killmail_id, :character_id, :character_role])
  end
end
```

### Benefits of the New Model

1. **Properly Normalized**: Each killmail is stored once, regardless of how many tracked characters are involved
2. **Reduced Storage**: Eliminates duplication of large JSON blobs
3. **Faster Queries**: Most common data is flattened into columns for direct querying
4. **Clear Relationships**: Character involvement is modeled explicitly
5. **Original Data Preserved**: Full JSON data is still available for detailed processing
6. **Better Extensibility**: Adding new tracked characters to existing killmails is simpler

## Implementation Plan

### Phase 1: Create New Schema and Validation (COMPLETED)

1. **Define New Resources**:

   - ✅ Created the new `Killmail` and `KillmailCharacterInvolvement` resources
   - ✅ Added necessary relationships, identities, and indexes
   - ✅ Created migration files for the new tables and successfully ran migrations

2. **Add Validation Module**:

   ```elixir
   # File: lib/wanderer_notifier/killmail/validation.ex
   defmodule WandererNotifier.Killmail.Validation do
     @moduledoc """
     Validation functions for the new killmail models.
     """

     alias WandererNotifier.Resources.Killmail
     alias WandererNotifier.Resources.KillmailCharacterInvolvement

     @doc """
     Validate a new killmail record before persistence.
     """
     def validate_killmail(killmail) do
       # Implementation details...
     end

     @doc """
     Validate a character involvement record before persistence.
     """
     def validate_involvement(involvement) do
       # Implementation details...
     end

     @doc """
     Convert a Data.Killmail struct to the normalized model format.
     """
     def normalize_killmail(%WandererNotifier.Data.Killmail{} = killmail) do
       # Implementation details...
     end

     @doc """
     Extract a character involvement record from a killmail for a specific character.
     """
     def extract_character_involvement(killmail, character_id, character_role) do
       # Implementation details...
     end
   end
   ```

### Phase 2: Update Core Processing Logic (IN PROGRESS)

1. **Update KillmailProcessing Pipeline**:

   ```elixir
   # File: lib/wanderer_notifier/killmail_processing/pipeline.ex (update)

   # Replace the existing create_killmail and process_killmail functions
   def process_killmail(zkb_data, ctx) do
     with {:ok, killmail} <- create_normalized_killmail(zkb_data),
          {:ok, enriched} <- enrich_killmail_data(killmail),
          {:ok, validated_killmail} <- validate_killmail_data(enriched),
          {:ok, persisted} <- persist_normalized_killmail(validated_killmail, ctx),
          {:ok, should_notify, reason} <- check_notification(persisted, ctx),
          {:ok, result} <- maybe_send_notification(persisted, should_notify, ctx) do
       # Rest of function implementation...
     end
   end

   defp create_normalized_killmail(zkb_data) do
     # Implementation using the new model...
   end

   defp persist_normalized_killmail(killmail, ctx) do
     # Implementation using the new model...
   end
   ```

2. **Update KillmailPersistence Module**:

   ```elixir
   # File: lib/wanderer_notifier/resources/killmail_persistence.ex (update)

   # Update the maybe_persist_killmail function to work with the normalized model
   def maybe_persist_killmail(killmail, character_ids \\ nil) do
     # Implementation working with normalized model...
   end
   ```

   - ✅ Updated `check_killmail_exists_in_database` to use the new model

### Phase 3: Update Dependent Modules (PENDING)

1. **Update the Weekly Schedulers**:

   Update each scheduler to work with the new model:

   - WeeklyKillHighlightsScheduler
   - WeeklyKillDataScheduler
   - WeeklyKillChartScheduler
   - KillmailAggregationScheduler

2. **Update the StructuredFormatter**:

   Update to handle the new model structure:

   ```elixir
   # File: lib/wanderer_notifier/notifiers/structured_formatter.ex (update)

   # Update format_kill_notification
   def format_kill_notification(%WandererNotifier.Resources.Killmail{} = killmail, involvement \\ nil) do
     # Implementation using new model...
   end
   ```

### Phase 4: Testing and Deployment (PENDING)

1. **Comprehensive Test Suite**:

   Update tests for:

   - Notification formatting
   - Weekly scheduler functions
   - Edge cases in killmail processing

2. **Monitoring and Observability**:

   Add detailed logging to identify any issues with the new model implementation.

### Phase 5: Documentation and Cleanup (PENDING)

1. **Remove Old Model**:

   ```elixir
   # File: lib/wanderer_notifier/data/killmail.ex (delete)
   defmodule WandererNotifier.Data.Killmail do
     @enforce_keys [:killmail_id, :zkb]
     defstruct [:killmail_id, :zkb, :esi_data]

     def new(killmail_id, zkb, esi_data \\ nil) do

       %__MODULE__{
         killmail_id: killmail_id,
         zkb: zkb,
         esi_data: esi_data
       }
     end

   end
   ```

2. **Comprehensive Documentation**:

   ````elixir
   # File: lib/wanderer_notifier/killmail.ex (new file)
   defmodule WandererNotifier.Killmail do
     @moduledoc """
     Central documentation and utility functions for working with killmails.

     ## Killmail Data Model

     Killmails are stored using two resources:

     1. `WandererNotifier.Resources.Killmail` - Stores the core killmail data
     2. `WandererNotifier.Resources.KillmailCharacterInvolvement` - Tracks which of your characters were involved

     ## Example Usage

     ```elixir
     # Get a specific killmail
     {:ok, [killmail]} = Api.read(Killmail |> Query.filter(killmail_id == 12345))

     # Get all kills for a character
     query =
       KillmailCharacterInvolvement
       |> Query.filter(character_id == 67890)
       |> Query.filter(character_role == :attacker)
       |> Query.load(:killmail)

     {:ok, involvements} = Api.read(query)
     kills = Enum.map(involvements, & &1.killmail)
     ```
   ````

   """
   end

   ```

   ```

## Timeline and Current Progress

- **Week 1** (COMPLETED):

  - ✅ Created new schema and validation code
  - ✅ Implementation of the normalized data model
  - ✅ Successfully ran migrations for the new tables

- **Week 2-3** (COMPLETED):

  - ✅ Updated core killmail processing logic
  - ✅ Updated `check_killmail_exists_in_database` to use new model
  - ✅ Updated `maybe_persist_killmail` to use the normalized model
  - ✅ Implemented `maybe_persist_normalized_killmail` for the new model
  - ✅ Created central documentation in `WandererNotifier.Killmail`

- **Week 4** (COMPLETED):

  - ✅ Updated WeeklyKillHighlightsScheduler to work with new model
  - ✅ Updated StructuredFormatter to work with both old and new models
  - ✅ Updated WeeklyKillDataScheduler's KillsService with compatibility changes
  - ✅ Updated WeeklyKillChartScheduler's KillmailChartAdapter to use normalized model
  - ✅ Updated KillmailAggregationScheduler to work with normalized model
  - ✅ Implemented comprehensive tests for the new data model

- **Week 5** (PLANNED):

  - Deploy to staging environment
  - Monitor for any issues
  - Add performance optimizations where needed

- **Week 6** (PLANNED):

  - Full production deployment
  - Begin phased removal of old model code

## Risks and Mitigation

### Risks

1. **Performance Impacts**: New queries involving joins might be slower than the old denormalized approach
2. **Breaking Changes**: Modules that directly access the killmail structure might break
3. **Data Freshness**: Starting with a new empty database means historical killmail data won't be available immediately

### Mitigation

1. **Performance Testing**: Test query performance with realistic data volumes before full deployment
2. **Comprehensive Test Suite**: Add tests for all killmail-related functionality
3. **Gradual Rollout**: Use feature flags to gradually switch to the new model
4. **Historical Data Fetching**: Implement background job to fetch important historical kills if needed

## Success Criteria

1. All killmail processing uses the normalized data model
2. No duplication of killmail data for multiple characters
3. All schedulers and notifications work correctly with the new model
4. Query performance is maintained or improved
5. No runtime errors in production related to the model change
6. Remove old model code after sufficient transition period

## Post-Implementation Tasks

1 -- what is the criteria for persistence / notification????

1. Monitor database size compared to the old approach
2. Review query performance and optimize as needed
3. Add indexes for common query patterns
4. Consider materialized views for frequently accessed aggregate data
5. Document any query patterns that work differently with the new model
