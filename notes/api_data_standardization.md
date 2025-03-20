# API Data Standardization Guide

## Core Principles

1. **Single Source of Truth**: Each domain entity should have a single, well-defined data structure
2. **Early Conversion**: Convert API responses to structured data immediately at API boundaries
3. **No Silent Renaming**: Field names should be preserved consistently through processing pipelines
4. **No Defensive Fallbacks**: Avoid "just in case" fallback logic that masks real issues
5. **Clear Contracts**: Each function should have explicit input/output contracts
6. **Explicit Error Handling**: Errors should be handled explicitly, not silently ignored
7. **Consistent Access Patterns**: Use the Access behavior consistently for all domain structs

## Data Structure Conversion Process

### API Boundary

1. **Input Validation**: Validate incoming data format (JSON schema, keys presence)
2. **Immediate Conversion**: Convert to appropriate struct (Character, MapSystem, Killmail)
3. **Error Handling**: Fail fast if required fields are missing instead of using defaults
4. **Data Enrichment**: Enrich data if needed through additional API calls
5. **Logging**: Log any validation or conversion errors with appropriate context

### Internal Processing

1. **Struct-Only Processing**: Only accept and work with proper structs, not raw maps
2. **Access Behavior**: Use the struct's Access behavior for field access (e.g., `system["name"]`)
3. **Pattern Matching**: Use pattern matching on structs instead of conditional logic
4. **No Dynamic Field Access**: Avoid `Map.get` on structs; use explicit field access

### Formatting & Output

1. **Explicit Formatting**: Use dedicated formatters for transforming structs to output format
2. **Struct-Based Templates**: Create template functions that work with specific struct types
3. **Platform Adapters**: Convert generic formatted outputs to platform-specific formats
4. **Field Mapping Documentation**: Document the mapping between struct fields and output fields

## Domain Object Guidelines

### Killmail

- Properly combine zKillboard and ESI data into a single Killmail struct
- Standardize access to victim and attacker information
- Implement Access behavior to allow both string and atom key access
- Document the format of all expected zkb/ESI fields

### Character

- Normalize access pattern for character IDs and names
- Standardize corporation and alliance information access
- Ensure proper formatting of character name/corporation ticker
- Document all field access patterns and their meanings

### MapSystem

- Use the proper display name formatting function consistently
- Standardize access to statics and wormhole information
- Document system type classification logic
- Ensure consistent handling of temporary system names

## Field Naming Conventions

| Entity Type | Primary ID Field  | Name Field | Other Key Fields                                 |
| ----------- | ----------------- | ---------- | ------------------------------------------------ |
| Character   | `eve_id`          | `name`     | `corporation_id`, `corporation_ticker`           |
| MapSystem   | `solar_system_id` | `name`     | `original_name`, `temporary_name`, `system_type` |
| Killmail    | `killmail_id`     | N/A        | `zkb`, `esi_data`, victim info, attacker info    |
| Corporation | `corporation_id`  | `name`     | `ticker`, `alliance_id`                          |
| Alliance    | `alliance_id`     | `name`     | `ticker`                                         |

## API Response to Struct Mapping

### 1. MapSystem Struct Mapping (Map API Responses)

#### From `/api/map/systems` Response:

```json
{
  "data": [
    {
      "id": "string",
      "solar_system_id": 30000001,
      "name": "System Name",
      "status": "string",
      "updated_at": "2023-01-01T00:00:00Z",
      "updated_by": "string"
    }
  ]
}
```

Maps to `MapSystem` struct:

```elixir
%MapSystem{
  id: "string",
  solar_system_id: 30000001,
  name: "System Name",
  original_name: "System Name",  # Set to name if not provided
  temporary_name: nil,           # Set if provided and different from original_name
  locked: false,                 # Default value
  class_title: nil,              # Will be populated from static info
  effect_name: nil,              # Will be populated from static info
  region_name: nil,              # Will be populated from static info
  statics: [],                   # Will be populated from static info
  static_details: [],            # Will be populated from static info
  system_type: :kspace,          # Determined by solar_system_id range
  type_description: "Unknown",   # Will be updated with static info
  is_shattered: false,           # Will be populated from static info
  sun_type_id: nil               # Will be populated from static info
}
```

#### From `/api/common/system-static-info` (Wormhole System):

```json
{
  "data": {
    "statics": ["E545", "N062"],
    "security": "-1.0",
    "class_title": "C2",
    "constellation_id": 21000055,
    "constellation_name": "B-C00055",
    "effect_name": null,
    "effect_power": 2,
    "is_shattered": false,
    "region_id": 11000007,
    "region_name": "B-R00007",
    "solar_system_id": 31000709,
    "solar_system_name": "J123555",
    "solar_system_name_lc": "j123555",
    "sun_type_id": 7,
    "system_class": 2,
    "triglavian_invasion_status": "Normal",
    "type_description": "Class 2",
    "wandering": ["F135"],
    "static_details": [
      {
        "name": "E545",
        "destination": {
          "id": "ns",
          "name": "Null-sec",
          "short_name": "N"
        },
        "properties": {
          "lifetime": "16",
          "mass_regeneration": 0,
          "max_jump_mass": 300000000,
          "max_mass": 2000000000
        }
      }
    ]
  }
}
```

Maps to `MapSystem.update_with_static_info/2` which updates:

```elixir
%MapSystem{
  # existing fields...
  class_title: "C2",
  effect_name: nil,
  region_name: "B-R00007",
  statics: ["E545", "N062"],
  static_details: [%{name: "E545", destination: %{...}, properties: %{...}}],
  system_type: :wormhole,        # Updated based on solar_system_id
  type_description: "Class 2",
  is_shattered: false,
  sun_type_id: 7
}
```

### 2. Character Struct Mapping (Map API Responses)

#### From `/api/map/characters` Response:

```json
{
  "data": [
    {
      "id": "cca87560-ca67-4a66-ace4-ed2957b24a43",
      "character": {
        "name": "Janissik",
        "alliance_id": null,
        "alliance_ticker": null,
        "corporation_id": 98551135,
        "corporation_ticker": "FLYSF",
        "eve_id": "404850015"
      },
      "inserted_at": "2025-01-01T01:25:29.811588Z",
      "updated_at": "2025-01-01T01:25:29.811588Z",
      "tracked": true,
      "map_id": "678c43cf-f71f-4e14-932d-0545465cdff0",
      "character_id": "c6bed9ad-12ba-4b1b-9ffa-49285d0f7b7e"
    }
  ]
}
```

Maps to `Character` struct:

```elixir
%Character{
  eve_id: "404850015",
  name: "Janissik",
  corporation_id: 98551135,
  corporation_ticker: "FLYSF",
  alliance_id: nil,
  alliance_ticker: nil,
  tracked: true
}
```

### 3. Killmail Struct Mapping (zKillboard and ESI Responses)

#### From zKillboard WebSocket:

```json
{
  "killID": 12345,
  "hash": "abcdef123456",
  "totalValue": 10000000
}
```

Maps to initial `Killmail` struct:

```elixir
%Killmail{
  killmail_id: 12345,
  zkb: %{
    "killID" => 12345,
    "hash" => "abcdef123456",
    "totalValue" => 10000000
  },
  esi_data: nil
}
```

#### ESI Killmail Enrichment:

```json
{
  "killmail_id": 12345,
  "killmail_time": "2023-01-01T00:00:00Z",
  "solar_system_id": 30000142,
  "victim": {
    "character_id": 93265215,
    "corporation_id": 98551135,
    "damage_taken": 1500,
    "ship_type_id": 603
  },
  "attackers": [
    {
      "character_id": 93265216,
      "corporation_id": 98551136,
      "damage_done": 1500,
      "final_blow": true,
      "ship_type_id": 11567,
      "weapon_type_id": 2977
    }
  ]
}
```

Updates the `Killmail` struct:

```elixir
%Killmail{
  killmail_id: 12345,
  zkb: %{
    "killID" => 12345,
    "hash" => "abcdef123456",
    "totalValue" => 10000000
  },
  esi_data: %{
    "killmail_id" => 12345,
    "killmail_time" => "2023-01-01T00:00:00Z",
    "solar_system_id" => 30000142,
    "victim" => %{
      "character_id" => 93265215,
      "corporation_id" => 98551135,
      "damage_taken" => 1500,
      "ship_type_id" => 603
    },
    "attackers" => [
      %{
        "character_id" => 93265216,
        "corporation_id" => 98551136,
        "damage_done" => 1500,
        "final_blow" => true,
        "ship_type_id" => 11567,
        "weapon_type_id" => 2977
      }
    ]
  }
}
```

## Testing Strategy

1. **Format Validation Tests**: Create tests for each supported input format
2. **Field Access Tests**: Verify that all field access patterns work as expected
3. **Edge Case Tests**: Test with partial, missing, or malformed data
4. **Round-Trip Tests**: Verify data integrity from API → Struct → Output format
5. **Visual Validation**: Create visual diff tests for formatted outputs
6. **Legacy Compatibility**: Ensure new formatters produce results compatible with legacy code

## Implementation Roadmap

1. **Audit Current Code**: Identify all places using direct field access on raw maps
2. **Define Structs**: Complete or refine struct definitions for all domain objects
3. **Convert API Clients**: Update all API clients to return proper structs
4. **Update Services**: Update service modules to expect and use structs
5. **Refine Formatters**: Enhance formatters to work with structs using the Access behavior
6. **Test & Validate**: Create comprehensive test suite for the new approach
7. **Remove Legacy Code**: Phase out old formatters and direct map access once verified

## Example: Proper Data Flow

For killmail processing:

```
1. Receive killmail data from WebSocket
2. Validate data has at least killmail_id and hash
3. Convert to Killmail struct immediately
4. Enrich with ESI data if needed
5. Store in cache as Killmail struct
6. When formatting, use Killmail-specific formatter
7. Format to Discord (or other platform) specific format
8. Send notification with properly formatted data
```

## Common Issues and Solutions

| Problem                | Current Approach                                | Recommended Approach                        |
| ---------------------- | ----------------------------------------------- | ------------------------------------------- |
| Missing fields         | Complex fallbacks using multiple field names    | Explicit checking with clear errors         |
| API format differences | Multiple extraction functions for each format   | Normalizing to structs with Access behavior |
| Complex field access   | Nested cond/if blocks checking multiple options | Pattern matching on struct types            |
| Data enrichment        | Done in formatting layer                        | Done at API boundary or service layer       |
| Error handling         | Silent fallbacks to defaults                    | Explicit error handling with context        |
| Inconsistent naming    | Field names change throughout processing        | Use consistent field names via structs      |

## Documentation Requirements

Each struct module should document:

1. The struct fields and their meanings
2. Expected source API format(s) that can be converted
3. Validation rules for required vs. optional fields
4. How the Access behavior implements field mapping
5. Examples of correct struct creation and field access
