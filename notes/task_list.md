# WandererNotifier Refactoring Task List

### Top Priority

  - [x] Fix System Notification Format
     - [x] Include static information for wormhole systems in embedded messages
     - [x] Update plain text messages to include temporary name for wormhole systems
  - [ ] Character Notification Improvements
     - [ ] Add zkillboard link for corporation in character notifications
     - [ ] Ensure corporation name is consistently displayed alongside ticker
  - [ ] Create Enhanced Startup Message
     - [ ] Improve embedded startup message
     - [ ] Enhance colors and display
 - [ ] Code Quality Improvements
   - [ ] Replace excessive conditionals with pattern matching where possible
     - [ ] Refactor `extract_character_id` and `extract_character_name` to use pattern matching
     - [ ] Use pattern matching in `extract_corporation_name` instead of nested cond blocks
     - [ ] Refactor key extraction in system notification formatting to use pattern matching
     - [ ] Improve WebSocket message handling with better pattern matching
   - [ ] Reduce duplication in data extraction logic
     - [ ] Create a shared module for data field extraction
     - [ ] Implement common functions for nested field access
     - [ ] Consider creating structs for key data types (character, system, kill)
   - [ ] Improve error handling with better fallbacks
     - [ ] Add more verbose logging for failed data transformations
     - [ ] Ensure all error cases have appropriate fallbacks
   - [ ] Consider creating specialized data extraction modules
     - [ ] Create a `WandererNotifier.Data.Extractors.Character` module
     - [ ] Create a `WandererNotifier.Data.Extractors.System` module
     - [ ] Create a `WandererNotifier.Data.Extractors.KillMail` module
 - [ ] Manual Testing Checklist
   - [ ] Test Kill Notifications
     - [ ] Verify first kill notification after startup is enriched (has embed with details)
     - [ ] Confirm victim and attacker details are correctly displayed
     - [ ] Test with license valid and invalid to verify gating works
     - [ ] Validate fallback corporation name extraction works
     - [ ] Check zkillboard links redirect correctly
   - [ ] Test Character Notifications
     - [ ] Verify first character notification after startup is enriched
     - [ ] Confirm corporation name displays correctly (try character with and without corporation)
     - [ ] Test with license valid and invalid to verify gating works
     - [ ] Check character portrait image loads correctly
     - [ ] Validate zkillboard link works correctly
   - [ ] Test System Notifications
     - [ ] Verify first system notification after startup is enriched
     - [ ] Test with different system types (highsec, lowsec, nullsec, wormhole)
     - [ ] Confirm statics display for wormhole systems
     - [ ] Verify region information shows for k-space systems
     - [ ] Test with license valid and invalid to verify gating works
   - [ ] Test WebSocket Functionality
     - [ ] Monitor WebSocket connection via status endpoint
     - [ ] Intentionally disconnect network to test reconnection
     - [ ] Verify kill messages from WebSocket flow through to notifications
     - [ ] Check circuit breaker functions properly on excessive disconnects
   - [ ] Test License Validation
     - [ ] Verify with valid license that all notifications are enriched
     - [ ] Test with invalid license that only first notifications are enriched
     - [ ] Change license status mid-session to verify behavior changes
   - [ ] Test Error Handling
     - [ ] Verify missing data fields produce reasonable fallbacks
     - [ ] Check logging output for appropriate error handling
     - [ ] Test with malformed data to ensure system handles it gracefullys
 - [ ] Validate notification functionality
   - [ ] Create test script to validate each notification type
   - [ ] Verify kill notifications with both test API and WebSocket
   - [ ] Test character notifications with sample data
   - [ ] Test system notifications with different system types
- [ ] Move from quickcharts to node chart service
  - [ ] Phase 1: Chart Service Enhancement
    - [ ] Update chart-service endpoints for each chart type
    - [ ] Create standardized response format with base64-encoded images
    - [ ] Add health metrics and better error handling
    - [ ] Implement chart adapters in Elixir for each chart type (TPS, Activity, etc.)
    - [ ] Update Discord notifier to support direct file attachments
  - [ ] Phase 2: Migration from QuickCharts
    - [ ] Identify all modules using QuickCharts.io URLs
    - [ ] Create parallel implementations for serv/clearer-side chart generation
    - [ ] Update schedulers to use new chart generation
    - [ ] Add feature flags to control gradual rollout
  - [ ] Phase 3: File Management & Optimization
    - [ ] Enhance automatic cleanup of generated chart files
    - [ ] Add metrics for disk usage monitoring
    - [ ] Implement caching for frequently used charts
    - [ ] Add configuration for chart size and quality options
- [ ] Get all tps charts actually working


### EVE Swagger Interface (ESI) API (Pending)
- [ ] Create structured data types for ESI responses:
  - [ ] Implement KillMail struct
  - [ ] Implement Corporation struct
  - [ ] Implement Alliance struct
  - [ ] Implement UniverseType struct (ships)
  - [ ] Implement SolarSystem struct
- [ ] Create domain-specific ESI URL builder
- [ ] Refactor ESI client to use structured types
- [ ] Add response validation for ESI endpoints
- [ ] Update services to use new structured ESI responses
- [ ] Implement caching strategies consistent with Map API

### zKillboard API & WebSocket (Pending)
- [ ] Create structured data types for zKillboard data
- [ ] Refactor zKillboard client to use structured types
- [ ] Standardize WebSocket connection handling
- [ ] Implement resilient reconnection logic
- [ ] Update kill processor to use new structured data
- [ ] Add tests for WebSocket reconnection scenarios

### EVE Corp Tools API (Pending)
- [ ] Create structured data types for TPS data responses:
  - [ ] Implement TimeFrame struct
  - [ ] Implement Chart struct with different chart types
  - [ ] Implement KillStatistics struct
- [ ] Refactor CorpToolsClient to use structured data types
- [ ] Add response validators for TPS data
- [ ] Update chart generators to use validated data models
- [ ] Standardize error handling consistent with other APIs

### License Manager API (Pending)
- [ ] Create structured License and Feature types
- [ ] Implement validation for License Manager responses
- [ ] Standardize error handling across license validation flow
- [ ] Add tests for License Manager API integration

## Documentation
- [ ] Create documentation for data model interfaces
- [ ] Add documentation for URL builders and validators
- [ ] Document common error handling patterns

## Technical Debt
- [ ] Standardize error handling across all API clients
- [ ] Replace defensive programming with clear contracts
- [ ] Audit cache strategies for consistency
- [ ] Ensure vite watcher actually rebuilds react code while using make s

## Testing
- [ ] Add tests for URL builders
- [ ] Add tests for response validators
- [ ] Add tests for data transformers
- [ ] Create integration tests for new API modules
- [ ] Add tests for schedulers and other critical components
- [ ] Create test modules and move test functions
- [ ] Implement integration tests for API interactions
- [ ] Add mock data for testing different response scenarios


### Map API
- [x] Create structured data types for API response data
- [x] Implement MapSystem struct
- [x] Implement Character struct
- [x] Create URL builder module
- [x] Implement response validators
- [x] Implement Systems client
- [x] Implement Characters client
- [x] Update System Update Scheduler to use new modules
- [x] Update Character Update Scheduler to use new modules
- [x] Update Activity Chart Scheduler to use new modules
- [x] Update controllers to use new API modules