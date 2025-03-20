# Pattern Matching Improvements

This document outlines the pattern matching improvements made to handle different data structures in the WandererNotifier application.

## Killmail Data Structure Handling

The application needs to handle killmails in multiple formats:

1. Raw JSON strings from the WebSocket
2. Parsed maps with string keys
3. `WandererNotifier.Data.Killmail` structs
4. Maps with atom keys

We've improved the pattern matching to handle all these formats consistently.

## Improvements Made

### 1. Extract Kill ID from Different Structures

```elixir
defp get_killmail_id(kill_data) when is_map(kill_data) do
  cond do
    # Direct field
    Map.has_key?(kill_data, "killmail_id") -> 
      Map.get(kill_data, "killmail_id")
    
    # Check for nested structure
    Map.has_key?(kill_data, "zkb") && Map.has_key?(kill_data, "killmail") ->
      get_in(kill_data, ["killmail", "killmail_id"])
    
    # Check for string keys converted to atoms
    Map.has_key?(kill_data, :killmail_id) ->
      Map.get(kill_data, :killmail_id)
      
    # Try to extract from the raw data if it has a zkb key 
    # (common format in real-time websocket feed)
    Map.has_key?(kill_data, "zkb") ->
      kill_id = Map.get(kill_data, "killID") || 
               get_in(kill_data, ["zkb", "killID"]) ||
               get_in(kill_data, ["zkb", "killmail_id"])
               
      # If we found a string ID, convert to integer
      if is_binary(kill_id) do
        String.to_integer(kill_id)
      else
        kill_id
      end
    
    true -> nil
  end
end
```

### 2. Extract Kill Data from Different Formats

```elixir
defp extract_kill_data(kill) do
  cond do
    # Case 1: It's a Killmail struct
    match?(%Killmail{}, kill) ->
      # Convert struct to a map format that the notifier expects
      kill_id = kill.killmail_id
      # Merge zkb and esi_data into a single map for the notifier
      kill_data = Map.merge(%{"killmail_id" => kill_id}, kill.zkb || %{})
      kill_data = if kill.esi_data, do: Map.merge(kill_data, kill.esi_data), else: kill_data
      {kill_data, kill_id}
    
    # Case 2: It's a binary string (JSON)
    is_binary(kill) ->
      case Jason.decode(kill) do
        {:ok, decoded} -> 
          kill_id = get_killmail_id(decoded)
          {decoded, kill_id}
        _ -> 
          {kill, nil}
      end
    
    # Case 3: It's a regular map
    is_map(kill) ->
      kill_id = get_killmail_id(kill)
      {kill, kill_id}
    
    # Case 4: Unknown format
    true ->
      {kill, nil}
  end
end
```

### 3. Convert Raw Data to Killmail Struct

```elixir
defp try_create_killmail_struct(kill_data) do
  kill_id = get_killmail_id(kill_data)
  
  if kill_id do
    # Extract zkb data if available
    zkb_data = Map.get(kill_data, "zkb") || %{}
    
    # The rest is treated as ESI data
    esi_data = Map.drop(kill_data, ["zkb"])
    
    # Create a proper Killmail struct
    try do
      Killmail.new(kill_id, zkb_data, esi_data)
    rescue
      # If struct creation fails, just store the raw data
      _ -> kill_data
    end
  else
    # If no kill ID, just return the raw data
    kill_data
  end
end
```

## Benefits

These improvements provide several benefits:

1. **Robustness**: The application can handle kills in different formats without failing
2. **Consistency**: Data is normalized to a consistent structure when possible
3. **Error Recovery**: If struct creation fails, the system falls back to the raw data
4. **Graceful Degradation**: Even partial or malformed data can be handled appropriately

## Testing

When testing kill notifications, the system now:

1. Checks if the data is a Killmail struct and handles it appropriately
2. Properly extracts the killmail ID regardless of format
3. Converts to the expected format for the notifier
4. Falls back to sample data only when absolutely necessary

This makes the testing flow more reliable, especially when real WebSocket data is available.