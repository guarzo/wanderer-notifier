# API Data Standardization Implementation Plan

This document outlines a practical step-by-step approach to implement the standardized API data handling across the codebase. The plan follows a methodical approach to minimize disruption while ensuring comprehensive coverage.

## Phase 1: Audit and Preparation (Week 1)

### 1.1 Audit API Client Modules

Identify all API client modules and their response handling patterns:

- [ ] `WandererNotifier.Api.ESI.Client`
- [ ] `WandererNotifier.Api.ZKill.Client`
- [ ] `WandererNotifier.Api.ZKill.WebSocket`
- [ ] `WandererNotifier.Api.Map.SystemsClient`
- [ ] `WandererNotifier.Api.Map.CharactersClient`
- [ ] `WandererNotifier.Api.CorpTools.Client`
- [ ] `WandererNotifier.Api.LicenseManager.Client`
- [ ] `WandererNotifier.ChartService.Client`

Document for each:

1. Current response handling pattern
2. Data transformation approach
3. Error handling strategy
4. Existing struct conversion (if any)

### 1.2 Audit Domain Struct Modules

Review all domain struct modules to ensure they properly implement Access behavior:

- [ ] `WandererNotifier.Data.MapSystem`
- [ ] `WandererNotifier.Data.Character`
- [ ] `WandererNotifier.Data.Killmail`

Document for each:

1. Current field definitions
2. Access behavior implementation completeness
3. Factory function coverage
4. Validation logic

### 1.3 Identify Formatter Usage

Find all places where raw data extraction is performed in formatters:

- [ ] `WandererNotifier.Notifiers.Formatter` (legacy)
- [ ] `WandererNotifier.Notifiers.StructuredFormatter`
- [ ] `WandererNotifier.Discord.Notifier`

### 1.4 Create Test Data Fixtures

- [ ] Create sample API response fixtures for each API endpoint
- [ ] Create expected struct conversion fixtures
- [ ] Set up test helpers for struct validation

## Phase 2: Struct Enhancement (Week 2)

### 2.1 Complete Killmail Struct Implementation

- [ ] Update `WandererNotifier.Data.Killmail` with proper Access behavior for nested fields
- [ ] Implement pattern-matching extraction functions
- [ ] Add `from_data/1` function
- [ ] Add validation and error handling
- [ ] Add type specs
- [ ] Create tests for all supported formats

### 2.2 Complete Character Struct Implementation

- [ ] Enhance `WandererNotifier.Data.Character` with robust field extraction
- [ ] Implement pattern-matching extraction functions
- [ ] Add `from_data/1` function
- [ ] Add validation and error handling
- [ ] Add type specs
- [ ] Create tests for all supported formats

### 2.3 Complete MapSystem Struct Implementation

- [ ] Review and refine `WandererNotifier.Data.MapSystem` extraction methods
- [ ] Ensure proper wormhole detection and classification
- [ ] Add `from_data/1` function
- [ ] Improve static information handling
- [ ] Add validation and error handling
- [ ] Add type specs
- [ ] Create tests for all supported formats

### 2.4 Create Missing Domain Structs

- [ ] Create `WandererNotifier.Data.Corporation` struct
- [ ] Create `WandererNotifier.Data.Alliance` struct
- [ ] Create `WandererNotifier.Data.SolarSystem` struct
- [ ] Create `WandererNotifier.Data.UniverseType` struct (for ships)

## Phase 3: API Client Refactoring (Week 3)

### 3.1 Refactor Map API Clients

- [ ] Update `WandererNotifier.Api.Map.SystemsClient`:

  - Return `MapSystem` structs consistently
  - Handle errors explicitly
  - Add validation for required fields
  - Use `with` syntax for cleaner transformation

- [ ] Update `WandererNotifier.Api.Map.CharactersClient`:
  - Return `Character` structs consistently
  - Add validation for required fields
  - Add explicit error handling

### 3.2 Refactor zKillboard WebSocket Handler

- [ ] Implement message type pattern matching
- [ ] Add immediate conversion to `Killmail` struct
- [ ] Improve error logging
- [ ] Add explicit error handling

### 3.3 Refactor ESI Client

- [ ] Implement struct conversion for killmail responses
- [ ] Implement struct conversion for character info
- [ ] Implement struct conversion for corporation info
- [ ] Add explicit validation steps

### 3.4 Refactor Corporation Tools Client

- [ ] Standardize response handling
- [ ] Add explicit validation

## Phase 4: Formatter Refactoring (Week 4)

### 4.1 Create Struct-Based Formatter Functions

- [ ] Enhance `WandererNotifier.Notifiers.StructuredFormatter`:
  - Add struct-specific formatting functions
  - Remove legacy field extraction logic
  - Implement pattern matching for different struct types

### 4.2 Update Notification Handling

- [ ] Update `WandererNotifier.Services.KillProcessor` to use Killmail structs consistently
- [ ] Update `WandererNotifier.Services.SystemTracker` to expect MapSystem structs
- [ ] Update character notification flow to use Character structs

### 4.3 Create Migration Path

- [ ] Implement dual-path for backward compatibility
- [ ] Add feature flag for new formatter path
- [ ] Create A/B testing mechanism

### 4.4 Create Visualization Tests

- [ ] Create visual diff tests for formatted output
- [ ] Verify legacy and new formatter produce identical results

## Phase 5: Service Integration (Week 5)

### 5.1 Update Schedulers

- [ ] Update system update scheduler
- [ ] Update character tracker scheduler
- [ ] Update killmail processing scheduler

### 5.2 Update Notification Dispatchers

- [ ] Update Discord notifier to use struct-based formatters
- [ ] Update push notifier to use struct-based formatters
- [ ] Ensure proper struct handling throughout the pipeline

### 5.3 Update Cache Repository

- [ ] Ensure cache functions properly store/retrieve structs
- [ ] Add validation on cache retrieval
- [ ] Standardize error handling

## Phase 6: Testing & Validation (Week 6)

### 6.1 Create Integration Tests

- [ ] Create end-to-end tests for system notifications
- [ ] Create end-to-end tests for character notifications
- [ ] Create end-to-end tests for killmail notifications

### 6.2 Performance Testing

- [ ] Benchmark original vs. new implementation
- [ ] Profile memory usage
- [ ] Measure response times

### 6.3 Error Case Testing

- [ ] Test with malformed API responses
- [ ] Test with missing required fields
- [ ] Test with network failures

### 6.4 Final Validation

- [ ] Run all tests with new formatters enabled
- [ ] Verify visual output matches expected results
- [ ] Document any discrepancies and fix if needed

## Phase 7: Clean-up & Documentation (Week 7)

### 7.1 Remove Legacy Code

- [ ] Remove old formatter module
- [ ] Remove redundant extraction functions
- [ ] Remove feature flag for new formatter path

### 7.2 Final Documentation

- [ ] Update API response documentation
- [ ] Document struct conversion rules
- [ ] Document formatter usage
- [ ] Create examples for common operations

### 7.3 Monitoring Plan

- [ ] Add metrics for API response handling
- [ ] Add specific logging for data transformation issues
- [ ] Create alerts for transformation failures

## Files to Modify in Priority Order

1. **Core Domain Structs**:

   - `lib/wanderer_notifier/data/killmail.ex`
   - `lib/wanderer_notifier/data/character.ex`
   - `lib/wanderer_notifier/data/map_system.ex`

2. **API Clients**:

   - `lib/wanderer_notifier/api/zkill/websocket.ex`
   - `lib/wanderer_notifier/api/map/systems_client.ex`
   - `lib/wanderer_notifier/api/map/characters_client.ex`
   - `lib/wanderer_notifier/api/esi/client.ex`

3. **Processing Services**:

   - `lib/wanderer_notifier/services/kill_processor.ex`
   - `lib/wanderer_notifier/services/system_tracker.ex`

4. **Formatters**:

   - `lib/wanderer_notifier/notifiers/structured_formatter.ex`
   - `lib/wanderer_notifier/discord/notifier.ex`

5. **Schedulers**:
   - `lib/wanderer_notifier/schedulers/system_update_scheduler.ex`
   - `lib/wanderer_notifier/schedulers/character_update_scheduler.ex`

## Testing Strategy

1. **Unit Testing**:

   - Test each struct conversion function
   - Test Access behavior implementation
   - Test field extraction with pattern matching

2. **Integration Testing**:

   - Test API client → Struct → Formatter pipeline
   - Test struct caching and retrieval
   - Test scheduler operation with structs

3. **End-to-End Testing**:

   - Full notification flow for each notification type
   - API response → Notification delivery

4. **Visual Testing**:
   - Compare rendered Discord embeds
   - Verify all required fields are displayed
   - Check formatting matches design requirements

## Risk Mitigation

- Implement changes in parallel, maintaining compatibility with existing code
- Use feature flags to control rollout
- Add detailed logging at transformation boundaries
- Create fallback paths for critical notifications
- A/B test with production data before full deployment
