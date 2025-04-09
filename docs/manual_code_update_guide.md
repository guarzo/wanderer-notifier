# Guide for Manually Updating Code to Use the New KillmailProcessing Modules

This guide provides instructions for manually updating your code to use the new KillmailProcessing modules instead of the legacy Killmail module.

## Why Update Your Code?

The new KillmailProcessing modules offer several advantages:

1. **Clear, explicit data structures** with KillmailData
2. **Better type safety** with proper typespecs
3. **More consistent data access** through the Extractor module
4. **Improved separation of concerns** with specialized modules
5. **Better testability** with focused functionality

## Step-by-Step Update Process

### 1. Identify the Type of Usage

First, identify how your code is using the Killmail module:

- **Data extraction**: Getting data from killmail structures (system_id, victim, etc.)
- **Validation**: Checking if killmail data is complete and valid
- **Database operations**: Checking if killmails exist or retrieving them
- **Mixed usage**: Combination of the above

### 2. Update the Imports

Replace:

```elixir
alias WandererNotifier.Killmail
```

With the specific modules you need:

```elixir
alias WandererNotifier.KillmailProcessing.{
  Extractor,      # If you need to extract data
  KillmailData,   # If you need to create or manipulate killmail data
  KillmailQueries, # If you need to query the database
  Validator       # If you need to validate killmail data
}
```

### 3. Update Function Calls

#### Data Extraction Functions

| Old Function                         | New Function                          |
| ------------------------------------ | ------------------------------------- |
| `Killmail.get_system_id(killmail)`   | `Extractor.get_system_id(killmail)`   |
| `Killmail.get_system_name(killmail)` | `Extractor.get_system_name(killmail)` |
| `Killmail.get_victim(killmail)`      | `Extractor.get_victim(killmail)`      |
| `Killmail.get_attacker(killmail)`    | `Extractor.get_attackers(killmail)`   |
| `Killmail.debug_data(killmail)`      | `Extractor.debug_data(killmail)`      |

#### Database Query Functions

| Old Function                             | New Function                                    |
| ---------------------------------------- | ----------------------------------------------- |
| `Killmail.exists?(killmail_id)`          | `KillmailQueries.exists?(killmail_id)`          |
| `Killmail.get(killmail_id)`              | `KillmailQueries.get(killmail_id)`              |
| `Killmail.get_involvements(killmail_id)` | `KillmailQueries.get_involvements(killmail_id)` |
| `Killmail.find_by_character(...)`        | `KillmailQueries.find_by_character(...)`        |

#### Validation Functions

| Old Function                                | New Function                                 |
| ------------------------------------------- | -------------------------------------------- |
| `Killmail.validate_complete_data(killmail)` | `Validator.validate_complete_data(killmail)` |

### 4. Use the KillmailData Struct

If your code is creating or manipulating killmail data, use the KillmailData struct:

```elixir
# Replace this:
killmail = %{
  killmail_id: 12345,
  solar_system_id: 30000142,
  solar_system_name: "Jita"
}

# With this:
killmail = %KillmailData{
  killmail_id: 12345,
  solar_system_id: 30000142,
  solar_system_name: "Jita"
}
```

### 5. Test Your Changes

After updating your code:

1. Run the tests to ensure everything works as expected
2. Check for compile warnings or errors
3. Manually test the functionality if possible

## Example: Complete Update

### Before:

```elixir
defmodule MyModule do
  alias WandererNotifier.Killmail

  def process_killmail(killmail_id) do
    if Killmail.exists?(killmail_id) do
      {:ok, killmail} = Killmail.get(killmail_id)

      system_id = Killmail.get_system_id(killmail)
      victim = Killmail.get_victim(killmail)

      case Killmail.validate_complete_data(killmail) do
        :ok ->
          # Process the killmail
          {:ok, system_id}
        {:error, reason} ->
          {:error, reason}
      end
    else
      {:error, :not_found}
    end
  end
end
```

### After:

```elixir
defmodule MyModule do
  alias WandererNotifier.KillmailProcessing.{
    Extractor,
    KillmailQueries,
    Validator
  }

  def process_killmail(killmail_id) do
    if KillmailQueries.exists?(killmail_id) do
      {:ok, killmail} = KillmailQueries.get(killmail_id)

      system_id = Extractor.get_system_id(killmail)
      victim = Extractor.get_victim(killmail)

      case Validator.validate_complete_data(killmail) do
        :ok ->
          # Process the killmail
          {:ok, system_id}
        {:error, reason} ->
          {:error, reason}
      end
    else
      {:error, :not_found}
    end
  end
end
```

## Common Gotchas

1. **Function name changes**: Note that `get_attacker` is now `get_attackers` (plural)
2. **Return types**: Some functions may have slightly different return types, check the typespecs
3. **Module scoping**: Make sure you're using the correct module scope (e.g., `KillmailProcessing.Extractor` not just `Extractor`)
4. **Test data**: If your tests create mock killmail data, they should use KillmailData structs

## Getting Help

If you run into issues updating your code, you can:

1. Check the documentation in the module files
2. Refer to the tests for examples of how to use the new modules
3. Read the architecture documentation in `docs/killmail_processing_architecture.md`
