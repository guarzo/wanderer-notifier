oh,# API Dependencies in WandererNotifier

This document provides an overview of all external API dependencies in the WandererNotifier application, along with the current parsing strategies and recommendations for simplification.

## 1. EVE Swagger Interface (ESI) API

### Base URL
- `https://esi.evetech.net/latest`

### Endpoints
| Endpoint | Function | Description |
|----------|----------|-------------|
| `/killmails/{kill_id}/{hash}/` | `get_killmail` | Fetches a killmail from ESI |
| `/characters/{eve_id}/` | `get_character_info` | Fetches character info from ESI |
| `/corporations/{eve_id}/` | `get_corporation_info` | Fetches corporation info from ESI |
| `/alliances/{eve_id}/` | `get_alliance_info` | Fetches alliance info from ESI |
| `/universe/types/{ship_type_id}/` | `get_universe_type` | Fetches universe type info (e.g. ship type) from ESI |
| `/search/?categories={categories}&search={query}&strict={strict}` | `search_inventory_type` | Searches for inventory types |
| `/universe/systems/{system_id}/` | `get_solar_system` | Fetches solar system info from ESI |
| `/universe/regions/{region_id}/` | `get_region` | Fetches region info from ESI |

### Current Parsing Logic
The ESI client uses `ErrorHandler.handle_http_response` to handle responses, which:
1. Converts HTTP status codes to meaningful errors
2. Decodes JSON response bodies
3. Adds domain-specific context to errors
4. Returns standardized response formats

The ESI client implementation is relatively clean and follows a consistent pattern.

## 2. zKillboard API

### Base URL
- `https://zkillboard.com/api`

### Endpoints
| Endpoint | Function | Description |
|----------|----------|-------------|
| `/killID/{kill_id}/` | `get_single_killmail` | Retrieves a single killmail from zKillboard |
| `/kills/` | `get_recent_kills` | Retrieves recent kills from zKillboard |
| `/systemID/{system_id}/` | `get_system_kills` | Retrieves kills for a specific system |

### Current Parsing Logic
The zKillboard client has some custom handling for edge cases:
1. It specifically handles the case where zKillboard returns `true` as a full response
2. Has additional validation to check if the response is a list in some functions
3. Truncates responses to the requested limit

## 3. zKillboard WebSocket

### Endpoint
- WebSocket endpoint for real-time killmail notifications

### Current Parsing Logic
The WebSocket client has complex logic to:
1. Manage connection state and implement circuit breaker patterns
2. Classify and handle different message types based on their content
3. Manage reconnection with exponential backoff
4. Parse and forward killmail notifications to the service module

## 4. Wanderer Map API

### Base URL
- Dynamic, built from configuration

### Endpoints
| Endpoint | Function | Description |
|----------|----------|-------------|
| `/api/map/systems?slug={slug_id}` | `update_systems` | Updates system information from the map |
| `/api/map/characters?slug={slug_id}` | `update_tracked_characters` | Updates tracked character information from the map |
| `/api/map/character-activity?slug={slug_id}` | `get_character_activity` | Gets character activity information |



## 5. License Manager API

### Base URL
- Dynamic, built from configuration (typically `https://license.eve-wanderer.com`)

### Endpoints
| Endpoint | Function | Description |
|----------|----------|-------------|
| `/api/validate_bot` | `validate_bot` | Validates a bot with a license key |
| `/api/validate_license` | `validate_license` | Validates a license key |

### Authentication
- Uses Bearer token authentication with the bot API token
- License key is included in the request body

### Request Format
```json
{
  "license_key": "your-license-key-here"
}
```

### Response Format
The API returns responses in the following format:

For `/api/validate_bot`:
```json
{
  "license_valid": true,
  "message": "License is valid",
  "features": {
    "basic_notifications": true,
    "tracked_systems_notifications": true,
    "tracked_characters_notifications": true,
    "backup_kills_processing": true,
    "web_dashboard_full": true,
    "advanced_statistics": true
  },
  "limits": {
    "tracked_systems": 100,
    "tracked_characters": 500,
    "notification_history": 500
  }
}
```

For `/api/validate_license`:
```json
{
  "valid": true,
  "bot_assigned": true,
  "message": "License is valid",
  "features": {
    "basic_notifications": true,
    "tracked_systems_notifications": true,
    "tracked_characters_notifications": true,
    "backup_kills_processing": true,
    "web_dashboard_full": true,
    "advanced_statistics": true
  },
  "limits": {
    "tracked_systems": 100,
    "tracked_characters": 500,
    "notification_history": 500
  }
}
```

### Error Responses
| Status Code | Error Type | Description |
|-------------|------------|-------------|
| 401 | `:invalid_bot_token` | Invalid bot API token |
| 403 | `:bot_not_authorized` | Bot is inactive or not associated with license |
| 404 | `:not_found` | Bot or license not found |
| (various) | `:request_failed` | Connection issues or timeouts |

### Current Parsing Logic
The License Manager client:
1. Builds the API URL from configuration
2. Sets up headers with Bearer token authentication
3. Sends a POST request with the license key in the body
4. Handles different response formats for compatibility
5. Transforms HTTP status codes into meaningful error types
6. Provides detailed logging for debugging

The client implementation is clean with proper error handling and validation.

## 6. EVE Corp Tools API

### Base URL
- Dynamic, built from configuration (typically `https://tools.eve-wanderer.com/service-api`)

### Endpoints
| Endpoint | Function | Description |
|----------|----------|-------------|
| `/health` | `health_check` | Checks if the EVE Corp Tools API is operational |
| `/tracked` | `get_tracked_entities` | Retrieves tracked entities (alliances, corporations, characters) |
| `/recent-tps-data` | `get_recent_tps_data` | Retrieves recent TPS (Time, Pilots, Ships) data optimized for charts |
| `/refresh-tps` | `refresh_tps_data` | Triggers a refresh of TPS data |
| `/appraise-loot` | `appraise_loot` | Appraises EVE Online loot items |
| `/activity` | `get_activity_data` | Retrieves character activity data |

### Authentication
- Uses Bearer token authentication with the Corp Tools API token
- Token is provided in the Authorization header

### Request Format
For most endpoints, a simple authenticated GET request is sufficient:
```
GET /service-api/recent-tps-data
Authorization: Bearer your-api-token-here
```

For the `/appraise-loot` endpoint, the request format is plain text:
```
POST /service-api/appraise-loot
Authorization: Bearer your-api-token-here
Content-Type: text/plain

Tritanium 100
Pyerite 50
Mexallon 25
```

### Response Format

For `/recent-tps-data`:
```json
{
  "TimeFrames": [
    {
      "Name": "Recent7Days",
      "Charts": [
        {
          "Name": "Character Damage and Final Blows",
          "ID": "characterDamageAndFinalBlowsChart_Recent7Days",
          "Data": "[{\"Name\":\"Pilot1\",\"FinalBlows\":8,\"DamageDone\":224361}, ...]",
          "Type": "bar"
        },
        {
          "Name": "Character Performance",
          "ID": "characterPerformanceChart_Recent7Days",
          "Data": "[{\"CharacterID\":123456,\"KillCount\":25,\"Name\":\"Pilot1\",\"Points\":106,\"SoloKills\":0}, ...]",
          "Type": "bar"
        },
        {
          "Name": "Kill Activity Over Time",
          "ID": "killActivityOverTimeChart_Recent7Days",
          "Data": "[{\"Time\":\"2025-03-13T00:00:00Z\",\"Kills\":7}, ...]",
          "Type": "line"
        },
        {
          "Name": "Top Ships Killed",
          "ID": "topShipsKilledChart_Recent7Days",
          "Data": "[{\"ShipTypeID\":47466,\"KillCount\":4,\"Name\":\"Praxis\"}, ...]",
          "Type": "wordCloud"
        },
        {
          "Name": "Kill-to-Loss Ratio",
          "ID": "killToLossRatioChart_Recent7Days",
          "Data": "[{\"CharacterName\":\"Pilot1\",\"Kills\":25,\"Losses\":0,\"Ratio\":25,\"ISKDestroyed\":10160387994.42,\"ISKLost\":0}, ...]",
          "Type": "bar"
        },
        {
          "Name": "Combined Losses",
          "ID": "combinedLossesChart_Recent7Days",
          "Data": "null",
          "Type": "bar"
        }
      ]
    }
  ]
}
```

Note: The `Data` field for each chart contains a JSON string that needs to be parsed again. The TPS data contains various charts with different types of EVE Online statistical information, including character performance, kill activity, ship types, and ISK values.

For `/tracked`:
```json
{
  "alliances": [
    {"id": 12345, "name": "Test Alliance Please Ignore"},
    {"id": 67890, "name": "Goonswarm Federation"}
  ],
  "corporations": [
    {"id": 11111, "name": "Dreddit"},
    {"id": 22222, "name": "Karmafleet"}
  ],
  "characters": [
    {"id": 33333, "name": "Test Character"},
    {"id": 44444, "name": "Another Test Character"}
  ]
}
```

For `/activity`:
```json
{
  "data": [
    {
      "character": {
        "name": "Character Name",
        "eve_id": "12345"
      },
      "signatures": 25,
      "connections": 10,
      "passages": 15
    }
  ]
}
```

### Special Status Codes
| Status Code | Meaning | Return Value |
|-------------|---------|--------------|
| 206 (Partial Content) | Data is still loading | `{:loading, message}` |

### Error Responses
| Status Code | Error | Description |
|-------------|-------|-------------|
| 401 | `:unauthorized` | Invalid API token |
| 403 | `:forbidden` | API token does not have access to the requested resource |
| 404 | `:not_found` | Resource not found |
| (various) | `:connection_refused` | Connection issues or timeouts |

### Current Parsing Logic
The Corp Tools client:
1. Builds the API URL from configuration
2. Sets up headers with Bearer token authentication
3. Sends requests with appropriate content types
4. Handles redirects manually when necessary
5. Transforms HTTP status codes into meaningful error types
6. Provides detailed logging for debugging
7. Supports special status code 206 for data that is still loading
