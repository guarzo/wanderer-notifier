# EVE Corp Tools Service API Integration Guide

## Overview

The EVE Corp Tools Service API provides programmatic access to key features of the EVE Corp Tools platform, allowing third-party applications to retrieve data and perform actions without requiring user authentication. This document outlines how to integrate with the API.

## Authentication

All API requests require authentication using a bearer token.

```
Authorization: Bearer api-token-for-service-to-service-auth
```

The API token should be obtained from your EVE Corp Tools administrator. This token is used to authenticate service-to-service requests and does not require user login.

## Base URL

The base URL for all API endpoints is:

```
http://your-server-address/service-api
```

Replace `your-server-address` with the actual address of your EVE Corp Tools server.

## Endpoints

### Health Check

Check if the API is operational.

- **URL**: `/health`
- **Method**: `GET`
- **Response**: 
  ```json
  {
    "status": "ok"
  }
  ```

### Tracked Entities

Retrieve all tracked alliances, corporations, and characters.

- **URL**: `/tracked`
- **Method**: `GET`
- **Response**:
  ```json
  {
    "alliances": [
      {
        "id": 99010452,
        "name": "Alliance Name",
        "type": "alliance",
        "AddedBy": "Character Name",
        "AddedAt": "2023-05-15T14:22:10Z"
      }
    ],
    "corporations": [
      {
        "id": 98648442,
        "name": "Corporation Name",
        "type": "corporation",
        "AddedBy": "Character Name",
        "AddedAt": "2023-05-15T14:22:10Z"
      }
    ],
    "characters": [
      {
        "id": 96180548,
        "name": "Character Name",
        "type": "character",
        "AddedBy": "Character Name",
        "AddedAt": "2023-05-15T14:22:10Z"
      }
    ]
  }
  ```

### TPS Data

Retrieve Time, Pilots, Ships (TPS) data for tracked entities.

- **URL**: `/tps-data`
- **Method**: `GET`
- **Response** (if data is available):
  ```json
  {
    "Last12MonthsData": {
      "KillsByShipType": { ... },
      "KillsByMonth": { ... },
      "TotalKills": 250,
      "TotalValue": 15000000000
    },
    "LastMonthData": { ... },
    "MTDData": { ... }
  }
  ```
- **Response** (if data is loading):
  ```json
  "data loading in progress"
  ```
- **Status Codes**:
  - `200 OK`: Data is available
  - `206 Partial Content`: Data is still loading

### Refresh TPS Data

Trigger a refresh of TPS data.

- **URL**: `/refresh-tps`
- **Method**: `GET`
- **Response**:
  ```json
  "refresh started"
  ```

### Appraise Loot

Appraise EVE Online loot items.

- **URL**: `/appraise-loot`
- **Method**: `POST`
- **Headers**:
  - `Content-Type: text/plain`
- **Body**: Plain text list of items and quantities, one per line
  ```
  Tritanium 100
  Pyerite 50
  Mexallon 25
  ```
- **Response**:
  ```json
  {
    "code": "abc123",
    "immediatePrices": {
      "totalBuyPrice": 12500.75,
      "totalSplitPrice": 13750.25,
      "totalSellPrice": 15000.50
    },
    "items": [
      {
        "amount": 100,
        "immediatePrices": {
          "buyPrice": 10000.50,
          "splitPrice": 11000.25,
          "sellPrice": 12000.00,
          "buyPrice5DayMedian": 9800.75,
          "splitPrice5DayMedian": 10800.50,
          "sellPrice5DayMedian": 11800.25,
          "buyPrice30DayMedian": 9500.25
        },
        "itemType": {
          "eid": 34,
          "name": "Tritanium",
          "volume": 0.01,
          "packagedVolume": 0.01
        }
      },
      // Additional items...
    ]
  }
  ```

## Error Handling

The API uses standard HTTP status codes to indicate the success or failure of requests:

- `200 OK`: The request was successful
- `206 Partial Content`: The request was successful but data is still loading
- `400 Bad Request`: The request was invalid
- `401 Unauthorized`: Authentication failed
- `500 Internal Server Error`: An error occurred on the server

Error responses include a JSON object with an error message:

```json
{
  "error": "Error message"
}
```

## Code Examples

### cURL

```bash
# Health check
curl -X GET "http://your-server-address/service-api/health" \
  -H "Authorization: Bearer api-token-for-service-to-service-auth"

# Get tracked entities
curl -X GET "http://your-server-address/service-api/tracked" \
  -H "Authorization: Bearer api-token-for-service-to-service-auth"

# Get TPS data
curl -X GET "http://your-server-address/service-api/tps-data" \
  -H "Authorization: Bearer api-token-for-service-to-service-auth"

# Refresh TPS data
curl -X GET "http://your-server-address/service-api/refresh-tps" \
  -H "Authorization: Bearer api-token-for-service-to-service-auth"

# Appraise loot
curl -X POST "http://your-server-address/service-api/appraise-loot" \
  -H "Authorization: Bearer api-token-for-service-to-service-auth" \
  -H "Content-Type: text/plain" \
  -d "Tritanium 100
Pyerite 50
Mexallon 25"
```

### Python

```python
import requests

API_TOKEN = "api-token-for-service-to-service-auth"
BASE_URL = "http://your-server-address/service-api"

headers = {
    "Authorization": f"Bearer {API_TOKEN}"
}

# Health check
response = requests.get(f"{BASE_URL}/health", headers=headers)
print(response.json())

# Get tracked entities
response = requests.get(f"{BASE_URL}/tracked", headers=headers)
print(response.json())

# Get TPS data
response = requests.get(f"{BASE_URL}/tps-data", headers=headers)
if response.status_code == 206:
    print("Data is still loading")
else:
    print(response.json())

# Refresh TPS data
response = requests.get(f"{BASE_URL}/refresh-tps", headers=headers)
print(response.json())

# Appraise loot
loot_data = """Tritanium 100
Pyerite 50
Mexallon 25"""

headers["Content-Type"] = "text/plain"
response = requests.post(f"{BASE_URL}/appraise-loot", headers=headers, data=loot_data)
print(response.json())
```

## Rate Limiting

To ensure service stability, the API implements rate limiting. If you exceed the rate limit, you will receive a `429 Too Many Requests` response. Please implement appropriate backoff strategies in your integration.

## Support

For questions or issues with the API, please contact your EVE Corp Tools administrator. 