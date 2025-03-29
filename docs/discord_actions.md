### Phase 1: Audit Discord API Usage
- [ ] Identify all deprecated API calls
  - [ ] Review `discord/notifier.ex`
  - [ ] Document current API version usage
  - [ ] List all affected functions
- [ ] Map dependencies on deprecated calls
  - [ ] Identify affected features
  - [ ] Document data structure changes needed

### Phase 2: Implement New API Patterns
- [ ] Update core Discord functionality
  - [ ] Implement new message creation endpoints
  - [ ] Update embed handling
  - [ ] Update file attachment handling
- [ ] Update notification formatters
  - [ ] Move to new Discord message components
  - [ ] Update rich embed formatting
  - [ ] Implement new permission handling

### Phase 3: Migration and Testing
- [ ] Create parallel implementations
  - [ ] Add new API methods alongside old ones
  - [ ] Add feature flags for new implementations
  - [ ] Create migration helpers
- [ ] Update all Discord calls
  - [ ] Migrate message sending
  - [ ] Migrate embed creation
  - [ ] Migrate webhook handling
- [ ] Comprehensive testing
  - [ ] Test all notification types
  - [ ] Test error handling
  - [ ] Test rate limiting