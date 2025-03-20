oh,# API Dependencies in WandererNotifier

This document provides an overview of all external API dependencies in the WandererNotifier application, along with the current parsing strategies and recommendations for simplification.

## 1. EVE Swagger Interface (ESI) API

### Base URL

- `https://esi.evetech.net/latest`

### Endpoints

| Endpoint                                                          | Function                | Description                                          |
| ----------------------------------------------------------------- | ----------------------- | ---------------------------------------------------- |
| `/killmails/{kill_id}/{hash}/`                                    | `get_killmail`          | Fetches a killmail from ESI                          |
| `/characters/{eve_id}/`                                           | `get_character_info`    | Fetches character info from ESI                      |
| `/corporations/{eve_id}/`                                         | `get_corporation_info`  | Fetches corporation info from ESI                    |
| `/alliances/{eve_id}/`                                            | `get_alliance_info`     | Fetches alliance info from ESI                       |
| `/universe/types/{ship_type_id}/`                                 | `get_universe_type`     | Fetches universe type info (e.g. ship type) from ESI |
| `/search/?categories={categories}&search={query}&strict={strict}` | `search_inventory_type` | Searches for inventory types                         |
| `/universe/systems/{system_id}/`                                  | `get_solar_system`      | Fetches solar system info from ESI                   |
| `/universe/regions/{region_id}/`                                  | `get_region`            | Fetches region info from ESI                         |

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

| Endpoint                 | Function              | Description                                 |
| ------------------------ | --------------------- | ------------------------------------------- |
| `/killID/{kill_id}/`     | `get_single_killmail` | Retrieves a single killmail from zKillboard |
| `/kills/`                | `get_recent_kills`    | Retrieves recent kills from zKillboard      |
| `/systemID/{system_id}/` | `get_system_kills`    | Retrieves kills for a specific system       |

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

| Endpoint                                        | Function                    | Description                                        |
| ----------------------------------------------- | --------------------------- | -------------------------------------------------- |
| `/api/map/systems?slug={slug_id}`               | `update_systems`            | Updates system information from the map            |
| `/api/map/characters?slug={slug_id}`            | `update_tracked_characters` | Updates tracked character information from the map |
| `/api/map/character-activity?slug={slug_id}`    | `get_character_activity`    | Gets character activity information                |
| `/api/common/system-static-info?id={system_id}` | `get_system_static_info`    | Gets static information about a solar system       |

### Authentication

- Uses Bearer token authentication with the Map API token
- Token is provided in the Authorization header with format: `Bearer {token}`

### Response Format

For `/api/map/systems?slug={slug_id}`:

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

For `/api/map/characters?slug={slug_id}`:

```json
{
  "data": [
    {
      "character": {
        "name": "Character Name",
        "eve_id": "12345"
      },
      "location": {
        "solar_system_id": 30000001,
        "solar_system_name": "System Name"
      },
      "ship": {
        "name": "Ship Name",
        "type_id": 12345
      },
      "last_seen": "2023-01-01T00:00:00Z"
    }
  ]
}
```

For `/api/map/character-activity?slug={slug_id}`:

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

For `/api/common/system-static-info?id={system_id}`:

For a non-wormhole system:

```json
{
  "data": {
    "statics": [],
    "security": "0.9",
    "class_title": "0.9",
    "constellation_id": 20000020,
    "constellation_name": "Kimotoro",
    "effect_name": null,
    "effect_power": 0,
    "is_shattered": false,
    "region_id": 10000002,
    "region_name": "The Forge",
    "solar_system_id": 30000142,
    "solar_system_name": "Jita",
    "solar_system_name_lc": "jita",
    "sun_type_id": 3796,
    "system_class": 7,
    "triglavian_invasion_status": "Normal",
    "type_description": "High-sec",
    "wandering": []
  }
}
```

For a wormhole system:

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
      },
      {
        "name": "N062",
        "destination": {
          "id": "c5",
          "name": "Class 5",
          "short_name": "C5"
        },
        "properties": {
          "lifetime": "24",
          "mass_regeneration": 0,
          "max_jump_mass": 375000000,
          "max_mass": 3000000000
        }
      }
    ]
  }
}
```

### Legacy Response Formats

The Wanderer Map API also supports legacy response formats that may use different keys:

- `static_info` instead of `data` for system static info
- `activity` instead of `data` for character activity
- Legacy character format without the nested `character` object

### Error Responses

| Status Code | Error           | Description                                    |
| ----------- | --------------- | ---------------------------------------------- |
| 401         | `:unauthorized` | Invalid API token                              |
| 403         | `:forbidden`    | API token does not have access to the resource |
| 404         | `:not_found`    | Resource not found                             |
| 500         | `:server_error` | Internal server error                          |

### Current Parsing Logic

The Map API client:

1. Builds URLs from configuration with the appropriate map slug
2. Adds authentication headers with the bearer token
3. Handles response validation with a structured validator
4. Supports both current and legacy response formats
5. Maps API responses to Elixir structs for easier handling in the application
6. Provides detailed error handling and logging

## 5. License Manager API

### Base URL

- Dynamic, built from configuration (typically `https://license.eve-wanderer.com`)

### Endpoints

| Endpoint                | Function           | Description                        |
| ----------------------- | ------------------ | ---------------------------------- |
| `/api/validate_bot`     | `validate_bot`     | Validates a bot with a license key |
| `/api/validate_license` | `validate_license` | Validates a license key            |

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

| Status Code | Error Type            | Description                                    |
| ----------- | --------------------- | ---------------------------------------------- |
| 401         | `:invalid_bot_token`  | Invalid bot API token                          |
| 403         | `:bot_not_authorized` | Bot is inactive or not associated with license |
| 404         | `:not_found`          | Bot or license not found                       |
| (various)   | `:request_failed`     | Connection issues or timeouts                  |

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

| Endpoint           | Function               | Description                                                          |
| ------------------ | ---------------------- | -------------------------------------------------------------------- |
| `/health`          | `health_check`         | Checks if the EVE Corp Tools API is operational                      |
| `/tracked`         | `get_tracked_entities` | Retrieves tracked entities (alliances, corporations, characters)     |
| `/recent-tps-data` | `get_recent_tps_data`  | Retrieves recent TPS (Time, Pilots, Ships) data optimized for charts |
| `/refresh-tps`     | `refresh_tps_data`     | Triggers a refresh of TPS data                                       |
| `/appraise-loot`   | `appraise_loot`        | Appraises EVE Online loot items                                      |
| `/activity`        | `get_activity_data`    | Retrieves character activity data                                    |

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
    { "id": 12345, "name": "Test Alliance Please Ignore" },
    { "id": 67890, "name": "Goonswarm Federation" }
  ],
  "corporations": [
    { "id": 11111, "name": "Dreddit" },
    { "id": 22222, "name": "Karmafleet" }
  ],
  "characters": [
    { "id": 33333, "name": "Test Character" },
    { "id": 44444, "name": "Another Test Character" }
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

| Status Code           | Meaning               | Return Value          |
| --------------------- | --------------------- | --------------------- |
| 206 (Partial Content) | Data is still loading | `{:loading, message}` |

### Error Responses

| Status Code | Error                 | Description                                              |
| ----------- | --------------------- | -------------------------------------------------------- |
| 401         | `:unauthorized`       | Invalid API token                                        |
| 403         | `:forbidden`          | API token does not have access to the requested resource |
| 404         | `:not_found`          | Resource not found                                       |
| (various)   | `:connection_refused` | Connection issues or timeouts                            |

### Current Parsing Logic

The Corp Tools client:

1. Builds the API URL from configuration
2. Sets up headers with Bearer token authentication
3. Sends requests with appropriate content types
4. Handles redirects manually when necessary
5. Transforms HTTP status codes into meaningful error types
6. Provides detailed logging for debugging
7. Supports special status code 206 for data that is still loading

## 7. Discord API

### Base URL

- `https://discord.com/api`

### Endpoints

| Endpoint                          | Function                     | Description                                             |
| --------------------------------- | ---------------------------- | ------------------------------------------------------- |
| `/channels/{channel_id}/messages` | `send_message`, `send_embed` | Sends a text message or rich embed to a Discord channel |
| `/channels/{channel_id}/messages` | `send_file`                  | Uploads a file to a Discord channel with optional embed |

### Authentication

- Uses Bot token authentication
- Token is provided in the Authorization header with format: `Bot {token}`

### Request Format

For text messages:

```json
{
  "content": "Your message here"
}
```

For embeds:

```json
{
  "embeds": [
    {
      "title": "Embed title",
      "description": "Embed description",
      "color": 3447003,
      "fields": [
        {
          "name": "Field name",
          "value": "Field value",
          "inline": true
        }
      ],
      "thumbnail": {
        "url": "https://example.com/image.png"
      },
      "image": {
        "url": "https://example.com/image.png"
      },
      "footer": {
        "text": "Footer text",
        "icon_url": "https://example.com/icon.png"
      }
    }
  ]
}
```

For file uploads:

- Uses multipart form data with:
  - A `payload_json` part containing any text/embed data
  - A `file` part containing the binary file data

### Response Format

```json
{
  "id": "message_id",
  "channel_id": "channel_id",
  "content": "message content",
  "timestamp": "2021-05-01T12:00:00.000000+00:00",
  "author": {
    "id": "bot_user_id",
    "username": "Bot Name",
    "discriminator": "0000",
    "bot": true
  }
}
```

### Error Responses

| Status Code | Error           | Description                                                  |
| ----------- | --------------- | ------------------------------------------------------------ |
| 401         | `:unauthorized` | Invalid bot token                                            |
| 403         | `:forbidden`    | Bot does not have permission to send messages to the channel |
| 404         | `:not_found`    | Channel not found                                            |
| 429         | `:rate_limited` | Rate limit exceeded                                          |

### Current Parsing Logic

The Discord client:

1. Gets the channel ID and bot token from configuration
2. Builds the request URL and headers
3. Encodes the payload as JSON
4. Sends the request using the HTTP client
5. Handles different response formats and error codes
6. Provides specialized handling for file uploads using multipart form data

## 8. Chart Service APIs

### 8.1 Local Node Chart Service

#### Base URL

- Local service running on `http://localhost:{port}` (default port: 3001)

#### Endpoints

| Endpoint            | Function               | Description                               |
| ------------------- | ---------------------- | ----------------------------------------- |
| `/generate`         | `generate_chart_image` | Generates a chart as base64-encoded image |
| `/save`             | `generate_chart_file`  | Generates a chart and saves it to a file  |
| `/generate-no-data` | `create_no_data_chart` | Creates a "No Data Available" chart       |

#### Request Format

For `/generate`:

```json
{
  "chart": {
    "type": "bar",
    "data": {
      "labels": ["Label 1", "Label 2"],
      "datasets": [
        {
          "label": "Dataset 1",
          "data": [10, 20],
          "backgroundColor": "rgba(255, 99, 132, 0.5)"
        }
      ]
    },
    "options": {
      "responsive": true,
      "plugins": {
        "legend": {
          "position": "top"
        },
        "title": {
          "display": true,
          "text": "Chart Title"
        }
      }
    }
  },
  "width": 800,
  "height": 400,
  "backgroundColor": "white"
}
```

For `/save`:

```json
{
  "chart": {
    // Same chart configuration as above
  },
  "fileName": "chart.png",
  "width": 800,
  "height": 400,
  "backgroundColor": "white"
}
```

For `/generate-no-data`:

```json
{
  "title": "Chart Title",
  "message": "No data available for this chart"
}
```

#### Response Format

For `/generate`:

```json
{
  "success": true,
  "imageData": "base64-encoded-image-data"
}
```

For `/save`:

```json
{
  "success": true,
  "filePath": "/tmp/wanderer_notifier_charts/chart.png"
}
```

For `/generate-no-data`:

```json
{
  "success": true,
  "imageData": "base64-encoded-image-data"
}
```

#### Error Response Format

```json
{
  "success": false,
  "message": "Error message"
}
```

### 8.2 QuickChart External API (Fallback)

#### Base URL

- `https://quickchart.io`

#### Endpoints

| Endpoint  | Function        | Description                                |
| --------- | --------------- | ------------------------------------------ |
| `/chart`  | `get_chart_url` | Generates a chart and returns a URL        |
| `/create` | `create_chart`  | Creates a chart and returns a URL or image |

#### Request Format

For `/create`:

```json
{
  "chart": {
    // Same chart configuration as above
  },
  "width": 800,
  "height": 400,
  "backgroundColor": "white",
  "format": "png"
}
```

#### Response Format

For `/create`:

```json
{
  "success": true,
  "url": "https://quickchart.io/chart/render/zf-12345"
}
```

### Current Parsing Logic

The Chart Service:

1. First attempts to use the local Node.js chart service
2. Falls back to the QuickChart API if the local service fails
3. Gets the service URL from the ChartServiceManager or uses defaults
4. Prepares chart configuration using ChartConfigHandler
5. Makes HTTP requests to the appropriate endpoints
6. Handles base64 decoding for image data
7. Provides detailed error handling and logging
8. Supports temporary file storage for saved charts

## 9. EVE Online Image APIs

### 9.1 EVE Images API

#### Base URL

- `https://images.evetech.net`

#### Endpoints

| Endpoint                  | Description                                          |
| ------------------------- | ---------------------------------------------------- |
| `/types/{type_id}/icon`   | Returns an icon for an EVE item/ship type            |
| `/types/{type_id}/render` | Returns a rendered 3D image of an EVE item/ship type |

#### Authentication

- No authentication required

#### Response Format

- Direct image data in PNG format
- Standard HTTP status codes for errors

### 9.2 EVE ImageServer API (Legacy)

#### Base URL

- `https://imageserver.eveonline.com`

#### Endpoints

| Endpoint                               | Description                        |
| -------------------------------------- | ---------------------------------- |
| `/Character/{character_id}_{size}.jpg` | Returns a character portrait image |
| `/Corporation/{corp_id}_{size}.png`    | Returns a corporation logo image   |
| `/Alliance/{alliance_id}_{size}.png`   | Returns an alliance logo image     |

#### Size Options

- Available sizes: 32, 64, 128, 256, 512, 1024

#### Authentication

- No authentication required

#### Response Format

- Direct image data in JPG/PNG format
- Standard HTTP status codes for errors

#### Usage Notes

- This API is being deprecated in favor of the EVE Images API
- Some endpoints are still used where the newer API does not provide equivalent functionality
