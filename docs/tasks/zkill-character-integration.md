# ZKill API Integration Plan for Character Kills

## Research and Planning Phase

- [x] Review existing kill persistence implementation in `docs/features/kill-persistence.md`
- [x] Examine existing ZKill API client module
- [x] Document data transformation flow from ZKill API → Killmail struct → Persistence

## Core Implementation

- [x] Enhance ZKill API client module
  - [x] Add character kills history endpoint function
  - [x] Implement rate limiting for ZKill API calls
- [x] Ensure proper integration with existing ESI client
  - [x] Verify caching implementation for ESI responses
  - [x] Add rate limiting for ESI API calls if not present
- [x] Develop killmail transformation service
  - [x] Convert ZKill API character kills to internal Killmail struct
  - [x] Ensure compatibility with `KillmailPersistence.maybe_persist_killmail`

## API Endpoint Implementation

- [x] Create API controller function for character kills endpoint
  - [x] Follow existing controller patterns in the codebase
  - [x] Implement authentication/authorization for the endpoint
  - [x] Design response format with appropriate status codes and error handling
- [x] Add controller function to router configuration

## Caching and Optimization

- [x] Implement deduplication logic to prevent storing duplicate killmails
- [x] Ensure proper cache utilization for ZKill/ESI responses
- [x] Add retry mechanism for failed API calls

## Testing and Documentation

- [x] Write unit tests for new ZKill API client functions
- [x] Create integration tests for the full data flow
- [x] Add documentation for the new endpoint

## Implementation Notes

### Data Flow

1. React app makes request to our backend endpoint for tracked character kills
2. Backend fetches kills for character from ZKill API
3. Backend transforms ZKill response to internal Killmail struct format
4. Backend calls `KillmailPersistence.maybe_persist_killmail` for each transformed killmail
5. Backend returns success/status response to frontend

### Considerations

- Rate limiting for both ZKill and ESI APIs
- Caching responses to prevent redundant calls
- Proper error handling and logging
- Deduplication to prevent storing the same killmail multiple times

### Usage

```
# Fetch and persist kills for a specific character
GET /api/character-kills?character_id=12345

# Fetch and persist kills for all tracked characters
GET /api/character-kills?all=true

# Control the number of kills retrieved
GET /api/character-kills?character_id=12345&limit=50

# Paginate through results
GET /api/character-kills?character_id=12345&page=2
```

This API can be called by your React frontend to manually trigger fetching kills for a character
or all tracked characters. This complements the existing websocket-based kill processing pipeline
and allows for direct/proactive fetching of character kill data.
