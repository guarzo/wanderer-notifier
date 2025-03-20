# WandererNotifier Refactoring Task List

### Top Priority

- [x] Validate all scheduled tasks
  - [x] When do they run, what do they do
- [ ] Create Enhanced Startup Message
  - [ ] Improve embedded startup message
  - [ ] Enhance colors and display
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
