# Migrating from Extractor to Direct KillmailData Access

This guide provides instructions for migrating from the deprecated `Extractor` module to direct access patterns using the `KillmailData` struct.

## Overview

As part of our pipeline refactoring, we've standardized on a flattened `KillmailData` struct which makes the `Extractor` module unnecessary in most cases. The migration process is straightforward:

1. Use direct field access for simple data extraction
2. Use the `DataAccess` module for complex operations
3. Use pattern matching to maintain backward compatibility

## Simple Migrations

### Before (using Extractor)

```elixir
def process_killmail(killmail) do
  system_id = Extractor.get_system_id(killmail)
  victim_id = Extractor.get_victim_character_id(killmail)
  zkb_data = Extractor.get_zkb_data(killmail)
  
  # Process data...
end
```

### After (direct access)

```elixir
def process_killmail(%KillmailData{} = killmail) do
  system_id = killmail.solar_system_id
  victim_id = killmail.victim_id
  zkb_data = killmail.raw_zkb_data
  
  # Process data...
end
```

## Maintaining Backward Compatibility

To maintain backward compatibility with code that may still pass non-KillmailData structures:

```elixir
def process_killmail(%KillmailData{} = killmail) do
  # Modern implementation with direct field access
  system_id = killmail.solar_system_id
  victim_id = killmail.victim_id
  
  # Process with the direct access pattern
end

def process_killmail(killmail) when is_map(killmail) do
  # Convert legacy data to KillmailData first
  killmail_data = Transformer.to_killmail_data(killmail)
  
  # Then process using the modern implementation
  process_killmail(killmail_data)
end
```

## Using the DataAccess Module

For more complex data access patterns, use the `DataAccess` module:

### Before (using Extractor)

```elixir
def find_character(killmail, character_id) do
  victim = Extractor.get_victim(killmail)
  attackers = Extractor.get_attackers(killmail)
  
  victim_id = Map.get(victim, "character_id")
  
  if to_string(victim_id) == to_string(character_id) do
    {:victim, victim}
  else
    attacker = Enum.find(attackers, fn a -> 
      to_string(Map.get(a, "character_id")) == to_string(character_id)
    end)
    
    if attacker, do: {:attacker, attacker}, else: nil
  end
end
```

### After (using DataAccess)

```elixir
def find_character(%KillmailData{} = killmail, character_id) do
  DataAccess.character_involvement(killmail, character_id)
end
```

## Common Migration Patterns

| Extractor Function | Direct KillmailData Access | 
| --- | --- |
| `get_killmail_id(killmail)` | `killmail.killmail_id` |
| `get_system_id(killmail)` | `killmail.solar_system_id` |
| `get_system_name(killmail)` | `killmail.solar_system_name` |
| `get_victim_character_id(killmail)` | `killmail.victim_id` |
| `get_victim_character_name(killmail)` | `killmail.victim_name` |
| `get_victim_ship_id(killmail)` | `killmail.victim_ship_id` |
| `get_victim_ship_name(killmail)` | `killmail.victim_ship_name` |
| `get_kill_time(killmail)` | `killmail.kill_time` |
| `get_zkb_data(killmail)` | `killmail.raw_zkb_data` |
| `debug_data(killmail)` | `DataAccess.debug_info(killmail)` |
| Complex attacker operations | `DataAccess.find_attacker(killmail, character_id)` |
| Character involvement | `DataAccess.character_involvement(killmail, character_id)` |
| Get all character IDs | `DataAccess.all_character_ids(killmail)` |

## Benefits of Direct Access

1. **Performance**: Direct field access is faster than function calls and pattern matching
2. **Simplicity**: Direct access is more intuitive and requires less code
3. **Type Safety**: The struct definition provides clear type information
4. **Better IDE Integration**: Modern IDEs provide better autocompletion with structs

## Additional Resources

- See the `DataAccess` module documentation for additional helpers
- Review the KillmailData struct definition for all available fields
- Check the test suite for examples of using direct access patterns 