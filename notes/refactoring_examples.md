# Refactoring Examples

This document provides concrete examples of how to refactor problematic patterns in the codebase, with a focus on API data handling.

## 1. Killmail Data Extraction Refactoring

### Current Pattern (Problematic)

```elixir
# Scattered throughout the codebase
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

### Refactored Pattern (Recommended)

```elixir
# In the Killmail module
defmodule WandererNotifier.Data.Killmail do
  # ... existing code ...

  @doc """
  Creates a new Killmail struct from different possible data formats.

  ## Parameters
    - data: Raw killmail data in any supported format

  ## Returns
    - {:ok, %Killmail{}} on success
    - {:error, reason} if the data cannot be converted
  """
  def from_data(data) when is_map(data) do
    # Try to extract the required fields
    with {:ok, kill_id} <- extract_killmail_id(data),
         {:ok, zkb} <- extract_zkb_data(data) do

      # Extract remaining ESI data if available
      esi_data = extract_esi_data(data)

      # Return the structured killmail
      {:ok, new(kill_id, zkb, esi_data)}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  def from_data(data) when is_binary(data) do
    # Try to decode JSON string
    case Jason.decode(data) do
      {:ok, decoded} -> from_data(decoded)
      {:error, reason} -> {:error, {:json_decode_error, reason}}
    end
  end

  def from_data(_), do: {:error, :invalid_killmail_format}

  # Private extraction helpers
  defp extract_killmail_id(data) do
    case data do
      # Pattern match for common scenarios
      %{"killmail_id" => id} when not is_nil(id) -> {:ok, id}
      %{killmail_id: id} when not is_nil(id) -> {:ok, id}
      %{"killID" => id} when not is_nil(id) -> {:ok, id}
      %{"zkb" => %{"killmail_id" => id}} when not is_nil(id) -> {:ok, id}
      %{"zkb" => %{"killID" => id}} when not is_nil(id) -> {:ok, id}
      %{"killmail" => %{"killmail_id" => id}} when not is_nil(id) -> {:ok, id}

      # Try string conversion if needed
      %{"zkb" => %{"killID" => id}} when is_binary(id) ->
        try do
          {:ok, String.to_integer(id)}
        rescue
          _ -> {:error, :invalid_killmail_id}
        end

      # No valid ID found
      _ -> {:error, :missing_killmail_id}
    end
  end

  defp extract_zkb_data(data) do
    case data do
      # Direct zkb field
      %{"zkb" => zkb} when is_map(zkb) -> {:ok, zkb}
      %{zkb: zkb} when is_map(zkb) -> {:ok, zkb}

      # For zkillboard websocket format
      %{"killID" => _} = websocket_data ->
        # Create a synthetic zkb map from websocket data
        zkb = %{
          "killID" => Map.get(websocket_data, "killID"),
          "hash" => Map.get(websocket_data, "hash"),
          "totalValue" => Map.get(websocket_data, "totalValue")
        }
        {:ok, zkb}

      # Minimal zkb data
      _ -> {:ok, %{}}
    end
  end

  defp extract_esi_data(data) do
    # Remove zkb data and keep the rest as ESI data
    case data do
      %{"zkb" => _} = map -> Map.drop(map, ["zkb"])
      %{zkb: _} = map -> Map.drop(map, [:zkb])
      _ -> data  # If no zkb field, treat entire map as ESI data
    end
  end
end
```

## 2. System Notification Formatter Refactoring

### Current Pattern (Problematic)

```elixir
def format_system_notification(system) do
  # Extract all system information with normalized data
  require Logger

  Logger.debug("[Formatter] Processing system notification with original data: #{inspect(system)}")

  system = normalize_system_data(system)

  # Extract essential system information using consistent extraction methods
  system_id = extract_system_id(system)
  system_name = extract_system_name(system)
  type_description = extract_type_description(system)

  # ... many more extractions ...

  # Determine system properties
  is_wormhole =
    String.contains?(type_description || "", "Class") ||
      (extract_class_title(system) != nil &&
        (String.contains?(extract_class_title(system), "C") ||
            String.contains?(extract_class_title(system), "Class")))

  # ... complex conditional logic for fields ...

  # Create the generic notification structure
  %{
    type: :system_notification,
    title: title,
    description: description,
    color: embed_color,
    timestamp: DateTime.utc_now() |> DateTime.to_iso8601(),
    thumbnail: %{url: icon_url},
    fields: fields
  }
end

# Many extraction helper functions
defp extract_system_id(system) when is_map(system) do
  Map.get(system, "solar_system_id") ||
    Map.get(system, "system_id") ||
    Map.get(system, "id") ||
    Map.get(system, "systemId")
end

defp extract_system_name(system) when is_map(system) do
  Map.get(system, "name") ||
    Map.get(system, "system_name") ||
    Map.get(system, "systemName") ||
    "Unknown System"
end

# ... more extraction helpers ...
```

### Refactored Pattern (Recommended)

```elixir
def format_system_notification(%MapSystem{} = system) do
  Logger.info(
    "[StructuredFormatter] Processing System notification for: #{system.name} (#{system.solar_system_id})"
  )

  # Check if the system is a wormhole
  is_wormhole = MapSystem.is_wormhole?(system)

  # Generate the display name for the notification using the dedicated function
  display_name = MapSystem.format_display_name(system)

  # Generate title and description
  title = generate_system_title(is_wormhole, system.class_title)
  description = generate_system_description(is_wormhole, system.class_title)

  # Determine system color and icon
  system_color = determine_system_color(system.system_type, is_wormhole)
  icon_url = determine_system_icon(system.sun_type_id, system.effect_name, system.system_type)

  # Build fields using the struct directly
  fields = [%{name: "System", value: display_name, inline: true}]

  # Add shattered field if applicable
  fields =
    if is_wormhole && system.is_shattered do
      fields ++ [%{name: "Shattered", value: "Yes", inline: true}]
    else
      fields
    end

  # Add statics field if applicable for wormhole systems
  fields =
    if is_wormhole do
      add_statics_field(fields, system.statics, system.static_details, system.name)
    else
      fields
    end

  # Add region field if available
  fields =
    if system.region_name do
      encoded_region_name = URI.encode(system.region_name)
      region_link = "[#{system.region_name}](https://evemaps.dotlan.net/region/#{encoded_region_name})"
      fields ++ [%{name: "Region", value: region_link, inline: true}]
    else
      fields
    end

  # Create the generic notification structure
  %{
    type: :system_notification,
    title: title,
    description: description,
    color: system_color,
    timestamp: DateTime.utc_now() |> DateTime.to_iso8601(),
    thumbnail: %{url: icon_url},
    fields: fields
  }
end

# For backward compatibility with map API response data
def format_system_notification(system_data) when is_map(system_data) do
  # Try to convert to a MapSystem struct if not already
  system =
    if Map.has_key?(system_data, :__struct__) && system_data.__struct__ == MapSystem do
      system_data
    else
      # Convert raw map to MapSystem struct
      MapSystem.new(system_data)
    end

  format_system_notification(system)
end
```

## 3. Character ID/Name Extraction Refactoring

### Current Pattern (Problematic)

```elixir
@doc """
Extracts a character ID from a character map following the API format.

According to the API documentation, characters are returned with:
1. A nested 'character' object containing 'eve_id' field (standard format)
2. Direct 'character_id' field for notification format

Returns the ID as a string, or nil if not found.
"""
def extract_character_id(character_data) do
  cond do
    # New format with character_id field
    is_map(character_data) && Map.has_key?(character_data, "character_id") ->
      Map.get(character_data, "character_id")

    # Legacy format with character field
    is_map(character_data) && Map.has_key?(character_data, "character") &&
    is_map(Map.get(character_data, "character")) &&
    Map.has_key?(Map.get(character_data, "character"), "eve_id") ->
      get_in(character_data, ["character", "eve_id"])

    # Alternate legacy format direct id
    is_map(character_data) && Map.has_key?(character_data, "id") ->
      Map.get(character_data, "id")

    # Alternate legacy format with characterID (old eveapi style)
    is_map(character_data) && Map.has_key?(character_data, "characterID") ->
      Map.get(character_data, "characterID")

    # Fallback - try to extract from any field that looks like an ID
    true ->
      nil
  end
end
```

### Refactored Pattern (Recommended)

```elixir
defmodule WandererNotifier.Data.Character do
  # ... existing struct definition ...

  @doc """
  Creates a Character struct from different possible data formats.

  ## Parameters
    - data: Raw character data in any supported format

  ## Returns
    - {:ok, %Character{}} on success
    - {:error, reason} if the data cannot be converted
  """
  def from_data(data) do
    with {:ok, eve_id} <- extract_character_id(data),
         {:ok, name} <- extract_character_name(data) do

      # Create the struct with additional fields
      character = %__MODULE__{
        eve_id: eve_id,
        name: name,
        corporation_id: extract_corporation_id(data),
        corporation_ticker: extract_corporation_ticker(data),
        alliance_id: extract_alliance_id(data),
        alliance_ticker: extract_alliance_ticker(data),
        tracked: extract_tracked_status(data)
      }

      {:ok, character}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  # Pattern matching for different character ID formats
  defp extract_character_id(%{"character_id" => id}) when not is_nil(id), do: {:ok, id}
  defp extract_character_id(%{"character" => %{"eve_id" => id}}) when not is_nil(id), do: {:ok, id}
  defp extract_character_id(%{"id" => id}) when not is_nil(id), do: {:ok, id}
  defp extract_character_id(%{"characterID" => id}) when not is_nil(id), do: {:ok, id}
  defp extract_character_id(%{"eve_id" => id}) when not is_nil(id), do: {:ok, id}
  defp extract_character_id(_), do: {:error, :missing_character_id}

  # Pattern matching for character name extraction
  defp extract_character_name(%{"character_name" => name}) when not is_nil(name), do: {:ok, name}
  defp extract_character_name(%{"character" => %{"name" => name}}) when not is_nil(name), do: {:ok, name}
  defp extract_character_name(%{"name" => name}) when not is_nil(name), do: {:ok, name}
  defp extract_character_name(_), do: {:error, :missing_character_name}

  # Similar pattern matching for other fields
  # ...
end
```

## 4. WebSocket Message Handling Refactoring

### Current Pattern (Problematic)

```elixir
def handle_message(message, state) do
  case message do
    # Check for different message types with conditionals
    %{"action" => action} when action in ["tqStatus", "tq"] ->
      Logger.debug("WebSocket received TQ status message: #{inspect(message)}")
      # Handle TQ status message
      {:ok, state}

    %{"killID" => kill_id} when is_integer(kill_id) or is_binary(kill_id) ->
      Logger.debug("WebSocket received killmail message: #{inspect(message)}")
      # Process killmail with complex extraction
      process_killmail(message, state)

    %{"killmail" => _} ->
      Logger.debug("WebSocket received structured killmail: #{inspect(message)}")
      # Process structured killmail
      process_killmail(message, state)

    %{"zkb" => _} ->
      Logger.debug("WebSocket received zkb-style killmail: #{inspect(message)}")
      # Process zkb killmail
      process_killmail(message, state)

    true ->
      Logger.warning("WebSocket received unknown message: #{inspect(message)}")
      {:ok, state}
  end
end

defp process_killmail(message, state) do
  # Complex extraction with multiple formats
  kill_id = extract_kill_id(message)

  if kill_id do
    # More complex processing logic
    # ...
  else
    Logger.warning("Unable to extract kill_id from message: #{inspect(message)}")
    {:ok, state}
  end
end
```

### Refactored Pattern (Recommended)

```elixir
def handle_message(message, state) do
  case classify_message(message) do
    {:tq_status, status_data} ->
      Logger.debug("WebSocket received TQ status message")
      handle_tq_status(status_data, state)

    {:killmail, kill_data} ->
      Logger.debug("WebSocket received killmail message")
      handle_killmail(kill_data, state)

    {:unknown, unknown_data} ->
      Logger.warning("WebSocket received unknown message type: #{inspect(unknown_data)}")
      {:ok, state}
  end
end

# Clear message classification with pattern matching
defp classify_message(%{"action" => action}) when action in ["tqStatus", "tq"], do: {:tq_status, message}
defp classify_message(%{"killID" => _} = message), do: {:killmail, message}
defp classify_message(%{"killmail" => _} = message), do: {:killmail, message}
defp classify_message(%{"zkb" => _} = message), do: {:killmail, message}
defp classify_message(message), do: {:unknown, message}

# Structured killmail handling
defp handle_killmail(kill_data, state) do
  # Convert to Killmail struct immediately
  case Killmail.from_data(kill_data) do
    {:ok, killmail} ->
      # Process using the proper struct
      KillProcessor.process_kill(killmail)
      {:ok, state}

    {:error, reason} ->
      Logger.warning("Failed to process killmail: #{inspect(reason)}, data: #{inspect(kill_data)}")
      {:ok, state}
  end
end
```

These refactoring examples demonstrate the principles of:

1. Consistent struct conversion at boundaries
2. Pattern matching instead of complex conditionals
3. Clear error handling
4. Reducing code duplication
5. Using the proper domain structs throughout the codebase
