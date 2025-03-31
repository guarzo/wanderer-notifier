### Phase 1: Audit Discord API Usage ✅

- [x] Identify all deprecated API calls
  - [x] Review `discord/notifier.ex`
  - [x] Document current API version usage
  - [x] List all affected functions
- [x] Map dependencies on deprecated calls
  - [x] Identify affected features
  - [x] Document data structure changes needed

### Phase 2: Implement New API Patterns ⏳

- [x] Update core Discord functionality
  - [x] Implement new message creation endpoints
  - [x] Update embed handling
  - [x] Update file attachment handling
- [x] Update notification formatters
  - [x] Move to new Discord message components
  - [x] Update rich embed formatting
  - [x] Implement new permission handling
- [x] Integrate Nostrum library more extensively
  - [x] Create NeoClient module with Nostrum API
  - [x] Add feature flag for Nostrum vs HTTP
  - [ ] Implement interaction handling

### Phase 3: Migration and Testing

- [x] Create parallel implementations
  - [x] Add new API methods alongside old ones
  - [x] Add feature flags for new implementations
  - [x] Create migration helpers
- [ ] Update all Discord calls
  - [ ] Migrate message sending
  - [ ] Migrate embed creation
  - [ ] Migrate webhook handling
- [ ] Comprehensive testing
  - [ ] Test all notification types
  - [ ] Test error handling
  - [ ] Test rate limiting
  - [ ] Test interaction handling
