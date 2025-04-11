# Migration Guide: Extractor → Direct KillmailData Access

This guide provides instructions for migrating code from using the `Extractor` module to using direct struct access with the new flattened `KillmailData` structure.

## Motivation

As part of our killmail pipeline refactoring, we've:

1. Standardized on a flattened `KillmailData` struct throughout the processing pipeline
2. Made all important fields available at the top level
3. Created a simpler `DataAccess` module for complex access patterns

This eliminates the need for the complex, pattern-matching-heavy `Extractor` module in most cases.

## Mapping Common Extractor Calls to Direct Access

### Basic Fields

| Old (Extractor)                                 | New (Direct Access)          |
| ----------------------------------------------- | ---------------------------- |
| `Extractor.get_killmail_id(killmail)`           | `killmail.killmail_id`       |
| `Extractor.get_system_id(killmail)`             | `killmail.solar_system_id`   |
| `Extractor.get_system_name(killmail)`           | `killmail.solar_system_name` |
| `Extractor.get_kill_time(killmail)`             | `killmail.kill_time`         |
| `Extractor.get_victim_character_id(killmail)`   | `killmail.victim_id`         |
| `Extractor.get_victim_character_name(killmail)` | `killmail.victim_name`       |
| `Extractor.get_victim_ship_type_id(killmail)`   | `killmail.victim_ship_id`    |
| `Extractor.get_victim_ship_type_name(killmail)` | `killmail.victim_ship_name`  |

### Complex Access Patterns

For more complex access patterns, use the new `DataAccess` module:

| Old (Extractor)                                             | New (DataAccess)                                      |
| ----------------------------------------------------------- | ----------------------------------------------------- |
| `Extractor.debug_data(killmail)`                            | `DataAccess.debug_info(killmail)`                     |
| `Extractor.find_field(killmail, field, char_id, :attacker)` | `DataAccess.find_attacker(killmail, char_id)`         |
| Complex victim/attacker role checks                         | `DataAccess.character_involvement(killmail, char_id)` |

### Raw Data Access

The `KillmailData` struct still contains raw data for special cases:

```elixir
# If you need raw zkb data
zkb_data = killmail.raw_zkb_data

# If you need raw ESI data
esi_data = killmail.raw_esi_data
```

## Step-by-Step Migration Process

1. **Ensure you have a KillmailData struct**: First make sure your function is receiving a `KillmailData` struct:

   ```elixir
   # Add a guard clause to ensure you're working with KillmailData
   def my_function(%KillmailData{} = killmail) do
     # Now you can safely use direct access
   end
   ```

2. **Replace Extractor calls with direct access**:

   ```elixir
   # Before
   system_id = Extractor.get_system_id(killmail)
   victim_id = Extractor.get_victim_character_id(killmail)

   # After
   system_id = killmail.solar_system_id
   victim_id = killmail.victim_id
   ```

3. **For complex patterns, use DataAccess**:

   ```elixir
   # Before
   attacker = Enum.find(Extractor.get_attackers(killmail), fn a ->
     Map.get(a, "character_id") == character_id
   end)

   # After
   attacker = DataAccess.find_attacker(killmail, character_id)
   ```

4. **Update function parameters if needed**:

   ```elixir
   # Before
   def process_kill(killmail, system_id \\ nil) do
     system_id = system_id || Extractor.get_system_id(killmail)
     # ...
   end

   # After
   def process_kill(%KillmailData{} = killmail, system_id \\ nil) do
     system_id = system_id || killmail.solar_system_id
     # ...
   end
   ```

## Common Gotchas

1. **Nested maps vs. direct fields**:

   - Remember that `attackers` is still a list of maps, not a list of structs
   - The attacker maps still use string keys, not atoms

2. **Standardized nullability**:

   - All fields in `KillmailData` can be `nil`
   - Use `||` or pattern matching to handle nil values

3. **ESI/ZKB Raw Data**:
   - Use `raw_esi_data` and `raw_zkb_data` only when absolutely necessary
   - These fields may not be populated in all contexts

## Testing Your Changes

After migrating, run the full test suite to ensure everything still works as expected. Pay special attention to:

1. Edge cases with missing data
2. Code that might be processing different killmail formats
3. Any error-handling code that expects specific error patterns

## Need Help?

If you encounter any issues during migration, refer to:

1. The `KillmailData` module documentation
2. The `DataAccess` module for complex access patterns
3. The test files for examples of proper usage

## Timeline

- **Phase 1 (Current)**: Create DataAccess module and documentation
- **Phase 2**: Update high-priority modules to use direct access
- **Phase 3**: Deprecate Extractor module
- **Phase 4**: Remove Extractor module entirely
