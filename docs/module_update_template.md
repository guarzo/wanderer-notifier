# Module Update Template

This template provides guidance on how to update a module from using the old Killmail interface to using the new specialized modules directly.

## Step 1: Update Imports

### Before:

```elixir
alias WandererNotifier.Killmail
```

### After:

```elixir
alias WandererNotifier.KillmailProcessing.{
  Extractor,      # For data extraction functions
  KillmailData,   # For the data structure
  KillmailQueries, # For database operations
  Validator       # For validation functions
}
```

## Step 2: Update Data Extraction

### Before:

```elixir
system_id = Killmail.get_system_id(killmail)
victim = Killmail.get_victim(killmail)
```

### After:

```elixir
system_id = Extractor.get_system_id(killmail)
victim = Extractor.get_victim(killmail)
```

## Step 3: Update Validation

### Before:

```elixir
case Killmail.validate_complete_data(killmail) do
  :ok -> # Process killmail
  {:error, reason} -> # Handle error
end
```

### After:

```elixir
case Validator.validate_complete_data(killmail) do
  :ok -> # Process killmail
  {:error, reason} -> # Handle error
end
```

## Step 4: Update Database Operations

### Before:

```elixir
if Killmail.exists?(killmail_id) do
  {:ok, killmail} = Killmail.get(killmail_id)
  # Process killmail
end
```

### After:

```elixir
if KillmailQueries.exists?(killmail_id) do
  {:ok, killmail} = KillmailQueries.get(killmail_id)
  # Process killmail
end
```

## Step 5: Use KillmailData for In-Memory Processing

### Before:

```elixir
enriched_killmail = %{
  killmail_id: killmail_id,
  solar_system_id: system_id,
  victim: victim_data
}
```

### After:

```elixir
enriched_killmail = %KillmailData{
  killmail_id: killmail_id,
  solar_system_id: system_id,
  solar_system_name: system_name,
  victim: victim_data,
  metadata: %{source: :manual_enrichment}
}
```

## Step 6: Update Tests

Ensure all tests are updated to use the new modules and KillmailData structure:

```elixir
# Create a test killmail
test_killmail = %KillmailData{
  killmail_id: 12345,
  solar_system_id: 30000142,
  solar_system_name: "Jita",
  victim: %{"character_id" => 123456}
}

# Test extraction
assert Extractor.get_system_id(test_killmail) == 30000142

# Test validation
assert Validator.validate_complete_data(test_killmail) == :ok
```

## Common Patterns

### Debugging

#### Before:

```elixir
debug_data = %{
  killmail_id: killmail_id,
  system_name: system_name
}
Logger.debug("Processing killmail", debug_data)
```

#### After:

```elixir
debug_data = Extractor.debug_data(killmail)
Logger.debug("Processing killmail", debug_data)
```

### Field Access

#### Before:

```elixir
value = Killmail.get(killmail, "field_name", default_value)
```

#### After:

```elixir
# For simple field access, use pattern matching when possible
%{field_name: value} = killmail
# Or for safe access with defaults
value = Map.get(killmail, :field_name, default_value)
```

## Verification Checklist

After updating a module, verify:

- [ ] All imports are updated to use the new modules
- [ ] All direct function calls to `Killmail` are replaced
- [ ] Tests are updated and passing
- [ ] Logging provides the same or better information
- [ ] Error handling is improved or maintained
- [ ] Documentation is updated with new module references
