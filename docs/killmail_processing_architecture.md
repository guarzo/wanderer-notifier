# Killmail Processing Architecture

This document describes the architecture of the killmail processing system after the refactoring.

## Overview

The killmail processing system is responsible for:

1. Receiving killmail data from various sources (zKillboard, ESI API)
2. Enriching the data with additional information
3. Validating the data for completeness and consistency
4. Persisting the data to the database when necessary
5. Determining if notifications should be sent
6. Sending notifications through various channels

## Key Components

### 1. KillmailData

A structured in-memory representation of killmail data during processing:

```elixir
%KillmailData{
  killmail_id: integer(),
  zkb_data: map(),
  esi_data: map(),
  solar_system_id: integer(),
  solar_system_name: string(),
  kill_time: DateTime.t(),
  victim: map(),
  attackers: list(map()),
  persisted: boolean(),
  metadata: map()
}
```

This structure provides a clear, consistent representation of killmail data throughout the processing pipeline, regardless of the source.

### 2. Extractor

Functions for extracting data from killmail structures of different types (KillmailData, KillmailResource, or raw maps):

```elixir
Extractor.get_killmail_id(killmail)
Extractor.get_system_id(killmail)
Extractor.get_system_name(killmail)
Extractor.get_victim(killmail)
Extractor.get_attackers(killmail)
Extractor.debug_data(killmail)
```

These functions use pattern matching to handle different killmail formats, ensuring consistent data access throughout the codebase.

### 3. KillmailQueries

Database query functions for killmails:

```elixir
KillmailQueries.exists?(killmail_id)
KillmailQueries.get(killmail_id)
KillmailQueries.get_involvements(killmail_id)
KillmailQueries.find_by_character(character_id, start_date, end_date, opts)
```

These functions abstract the database access details and provide a clean interface for working with killmail data.

### 4. Validator

Functions for validating killmail data:

```elixir
Validator.validate_complete_data(killmail)
```

Ensures that killmails have all required fields and data before proceeding with processing.

### 5. Pipeline

Orchestrates the killmail processing flow:

```elixir
Pipeline.process_killmail(zkb_data, ctx)
```

Key steps in the pipeline:

1. Create normalized killmail using KillmailData
2. Enrich killmail data (add system names, character names, etc.)
3. Validate killmail data for completeness
4. Persist to database if needed
5. Check if notification should be sent
6. Send notification if appropriate

## Data Flow

1. **Input**: Raw data from zKillboard or ESI API
2. **Normalization**: Convert to KillmailData structure
3. **Enrichment**: Add additional data from ESI API
4. **Validation**: Ensure data is complete and valid
5. **Persistence**: Save to database if needed
6. **Notification**: Send notifications if appropriate

## Code Organization

- `lib/wanderer_notifier/killmail_processing/killmail_data.ex`: KillmailData structure
- `lib/wanderer_notifier/killmail_processing/extractor.ex`: Data extraction functions
- `lib/wanderer_notifier/killmail_processing/killmail_queries.ex`: Database query functions
- `lib/wanderer_notifier/killmail_processing/validator.ex`: Validation functions
- `lib/wanderer_notifier/killmail_processing/pipeline.ex`: Processing pipeline

Supporting modules:

- `lib/wanderer_notifier/resources/killmail.ex`: Database entity
- `lib/wanderer_notifier/processing/killmail/enrichment.ex`: Enrichment logic
- `lib/wanderer_notifier/killmail.ex`: Legacy interface for backward compatibility

## Benefits of the New Architecture

1. **Explicit Structure**: Clear, well-defined KillmailData structure
2. **Type Safety**: Proper typespecs for better IDE support and Dialyzer usage
3. **Consistent Data Access**: Unified approach through the Extractor module
4. **Separation of Concerns**: Clear boundaries between different responsibilities
5. **Testability**: Easier to test individual components
6. **Backward Compatibility**: Legacy code continues to work through delegation

## Migration Path

1. New code should directly use the new modules in KillmailProcessing namespace
2. Existing code will continue to work through the legacy interface
3. Gradually refactor callers to use the new interfaces directly

## Example Usage

### Creating a KillmailData structure:

```elixir
zkb_data = %{"killmail_id" => 12345, "zkb" => %{"hash" => "abc123"}}
esi_data = %{"solar_system_id" => 30000142, "solar_system_name" => "Jita"}
killmail_data = KillmailData.from_zkb_and_esi(zkb_data, esi_data)
```

### Extracting data with Extractor:

```elixir
system_id = Extractor.get_system_id(killmail)
victim = Extractor.get_victim(killmail)
attackers = Extractor.get_attackers(killmail)
```

### Database queries with KillmailQueries:

```elixir
{:ok, killmail} = KillmailQueries.get(12345)
{:ok, involvements} = KillmailQueries.get_involvements(12345)
{:ok, character_kills} = KillmailQueries.find_by_character(character_id, start_date, end_date)
```

### Validating data with Validator:

```elixir
case Validator.validate_complete_data(killmail) do
  :ok -> # killmail is valid
  {:error, reason} -> # killmail is missing required data
end
```
