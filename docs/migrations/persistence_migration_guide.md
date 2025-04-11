# Migration Guide: KillmailPersistence → Processing.Killmail.Persistence

This guide provides instructions for migrating code from the deprecated `WandererNotifier.Resources.KillmailPersistence` module to the new `WandererNotifier.Processing.Killmail.Persistence` module.

## Overview

As part of our pipeline refactoring, we've created a new, more coherent persistence module with improved:

- Transaction handling
- Error reporting
- Data validation
- Atomic operations
- Clear API design

## Function Mapping

| Old (KillmailPersistence)                         | New (Processing.Killmail.Persistence)             |
| ------------------------------------------------- | ------------------------------------------------- |
| `persist_killmail(killmail)`                      | `persist_killmail(killmail, nil)`                 |
| `persist_killmail(killmail, character_id)`        | `persist_killmail(killmail, character_id)`        |
| `maybe_persist_killmail(killmail)`                | `persist_killmail(killmail, nil)`                 |
| `maybe_persist_killmail(killmail, character_id)`  | `persist_killmail(killmail, character_id)`        |
| `get_tracked_kills_stats()`                       | Use individual query functions                    |
| `get_killmails_for_character(character_id)`       | `get_killmails_for_character(character_id)`       |
| `get_killmails_for_system(system_id)`             | `get_killmails_for_system(system_id)`             |
| `get_character_killmails(character_id, from, to)` | `get_character_killmails(character_id, from, to)` |
| `exists?(killmail_id, character_id, role)`        | `exists?(killmail_id, character_id, role)`        |
| `count_total_killmails()`                         | `count_total_killmails()`                         |

## Return Value Changes

The new module uses more explicit return values:

| Function                 | Old Return Value                        | New Return Value                                    |
| ------------------------ | --------------------------------------- | --------------------------------------------------- |
| `persist_killmail`       | `:ok`, `:already_exists`, or `:error`   | `{:ok, killmail, true/false}` or `{:error, reason}` |
| `maybe_persist_killmail` | `{:ok, killmail}` or `{:error, reason}` | N/A (use `persist_killmail` instead)                |
| Query functions          | Varied formats                          | `{:ok, results}` or `{:error, reason}`              |

## Migration Examples

### Basic Persistence

**Before:**

```elixir
case KillmailPersistence.persist_killmail(killmail_data) do
  :ok ->
    Logger.info("Killmail persisted")
  :already_exists ->
    Logger.info("Killmail already exists")
  :error ->
    Logger.error("Failed to persist killmail")
end
```

**After:**

```elixir
case Persistence.persist_killmail(killmail_data, nil) do
  {:ok, persisted_killmail, true} ->
    Logger.info("Killmail persisted")
  {:ok, _, false} ->
    Logger.info("Killmail already exists")
  {:error, reason} ->
    Logger.error("Failed to persist killmail: #{inspect(reason)}")
end
```

### Character-Specific Persistence

**Before:**

```elixir
case KillmailPersistence.maybe_persist_killmail(killmail, character_id) do
  {:ok, _} ->
    Logger.info("Killmail persisted for character")
  {:error, reason} ->
    Logger.error("Failed to persist killmail: #{reason}")
end
```

**After:**

```elixir
case Persistence.persist_killmail(killmail, character_id) do
  {:ok, persisted_killmail, _created} ->
    Logger.info("Killmail persisted for character")
  {:error, reason} ->
    Logger.error("Failed to persist killmail: #{inspect(reason)}")
end
```

### Querying Killmails

**Before:**

```elixir
killmails = KillmailPersistence.get_character_killmails(character_id, from_date, to_date)
```

**After:**

```elixir
case Persistence.get_character_killmails(character_id, from_date, to_date) do
  {:ok, killmails} ->
    # Process killmails
  {:error, reason} ->
    Logger.error("Failed to get character killmails: #{inspect(reason)}")
end
```

## Implementation Timeline

1. **Phase 1**: Update all direct calls to use the new module
2. **Phase 2**: Update any error handling for the new return values
3. **Phase 3**: Remove any references to the deprecated module
4. **Phase 4**: Delete the deprecated module

## Testing

Be sure to test your changes thoroughly after migration, particularly:

- Error handling for new return values
- Transaction behavior for complex operations
- Performance for bulk operations
