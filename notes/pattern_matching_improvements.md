# Pattern Matching Improvement Opportunities

This document outlines specific areas in the codebase where we can improve readability and maintainability by replacing conditional logic with pattern matching.

## 1. Character Data Extraction

### Current Implementation (in `formatter.ex`):

```elixir
def extract_character_id(character) when is_map(character) do
  # Extract character ID - only accept numeric IDs
  cond do
    # Check top level character_id
    is_binary(character["character_id"]) && is_valid_numeric_id?(character["character_id"]) ->
      character["character_id"]
      
    # Check top level eve_id
    is_binary(character["eve_id"]) && is_valid_numeric_id?(character["eve_id"]) ->
      character["eve_id"]
      
    # Check nested character object
    is_map(character["character"]) && is_binary(character["character"]["eve_id"]) &&
        is_valid_numeric_id?(character["character"]["eve_id"]) ->
      character["character"]["eve_id"]
      
    is_map(character["character"]) && is_binary(character["character"]["character_id"]) &&
        is_valid_numeric_id?(character["character"]["character_id"]) ->
      character["character"]["character_id"]
      
    is_map(character["character"]) && is_binary(character["character"]["id"]) &&
        is_valid_numeric_id?(character["character"]["id"]) ->
      character["character"]["id"]
      
    # No valid numeric ID found
    true ->
      Logger.error(
        "No valid numeric EVE ID found for character: #{inspect(character, pretty: true, limit: 500)}"
      )
      
      nil
  end
end
```

### Improved Implementation Using Pattern Matching:

```elixir
def extract_character_id(%{"character_id" => id}) when is_binary(id) and is_valid_numeric_id?(id), do: id
def extract_character_id(%{"eve_id" => id}) when is_binary(id) and is_valid_numeric_id?(id), do: id
def extract_character_id(%{"character" => %{"eve_id" => id}}) when is_binary(id) and is_valid_numeric_id?(id), do: id
def extract_character_id(%{"character" => %{"character_id" => id}}) when is_binary(id) and is_valid_numeric_id?(id), do: id
def extract_character_id(%{"character" => %{"id" => id}}) when is_binary(id) and is_valid_numeric_id?(id), do: id
def extract_character_id(character) when is_map(character) do
  Logger.error("No valid numeric EVE ID found for character: #{inspect(character, pretty: true, limit: 500)}")
  nil
end
```

Similar improvements can be made to `extract_character_name` and `extract_corporation_name`.

## 2. System Data Extraction

### Current Implementation (in system notification formatter):

The current implementation uses multiple `Map.get` calls with fallbacks, which can be simplified with pattern matching.

### Improved Implementation:

```elixir
# Pattern match directly in function parameters
def format_system_notification(%{"solar_system_id" => id, "solar_system_name" => name} = system) do
  # Process with known ID and name
end

def format_system_notification(%{"system_id" => id, "system_name" => name} = system) do
  # Process with known ID and name using different keys
end

# Add more pattern matching variants for different data formats
```

## 3. WebSocket Message Handling

### Current Implementation (in `websocket.ex`):

```elixir
defp classify_json_message(json_data) do
  cond do
    # Killmail with zkb data
    is_map_key(json_data, "killmail_id") and is_map_key(json_data, "zkb") ->
      {:killmail_with_zkb, json_data["killmail_id"], json_data["zkb"]}

    # Killmail without zkb data
    is_map_key(json_data, "killmail_id") ->
      {:killmail_without_zkb, json_data["killmail_id"]}

    # Kill info message
    is_map_key(json_data, "kill_id") ->
      {:kill_info, json_data["kill_id"], Map.get(json_data, "solar_system_id")}

    # Action message
    is_map_key(json_data, "action") ->
      {:action, json_data["action"]}

    # Unknown message format
    true ->
      :unknown
  end
end
```

### Improved Implementation:

```elixir
defp classify_json_message(%{"killmail_id" => kill_id, "zkb" => zkb}), 
  do: {:killmail_with_zkb, kill_id, zkb}
  
defp classify_json_message(%{"killmail_id" => kill_id}), 
  do: {:killmail_without_zkb, kill_id}
  
defp classify_json_message(%{"kill_id" => kill_id, "solar_system_id" => system_id}), 
  do: {:kill_info, kill_id, system_id}
  
defp classify_json_message(%{"kill_id" => kill_id}), 
  do: {:kill_info, kill_id, nil}
  
defp classify_json_message(%{"action" => action}), 
  do: {:action, action}
  
defp classify_json_message(_), do: :unknown
```

## 4. Data Field Extraction

### Current Implementation:

The code currently uses a lot of `Map.get || Map.get || ...` patterns that could be replaced with a cleaner approach.

### Improved Implementation:

```elixir
# Define accessor functions that handle different key formats
def get_field(map, field) do
  field_variants = [
    field, 
    String.to_atom(field), 
    Macro.camelize(field), 
    String.to_atom(Macro.camelize(field))
  ]
  
  Enum.find_value(field_variants, fn key -> 
    Map.get(map, key)
  end)
end

# Or using pattern matching for nested access
def get_nested_field(map, parent, field) do
  with parent_data when not is_nil(parent_data) <- Map.get(map, parent),
       field_value when not is_nil(field_value) <- Map.get(parent_data, field) do
    field_value
  else
    _ -> nil
  end
end
```

## 5. Type-Based Data Transformation

### Current Approach:
The code uses many conditionals to determine what type of data is being processed.

### Improved Approach:
Create specialized functions with pattern matching:

```elixir
# For system notification formatting
def format_notification(%{type: :wormhole} = system), do: format_wormhole_system(system)
def format_notification(%{type: :highsec} = system), do: format_highsec_system(system)
def format_notification(%{type: :lowsec} = system), do: format_lowsec_system(system)
def format_notification(%{type: :nullsec} = system), do: format_nullsec_system(system)
```

## Recommendations

1. Create specialized extractor modules for each data type
2. Use pattern matching in function heads rather than conditional logic in function bodies
3. Create common field access functions that handle different naming conventions
4. Use the `with` special form for multi-step data transformations
5. Create proper structs for key data types to leverage compile-time checking