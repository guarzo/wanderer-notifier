### Phase 1: Audit Current Formatters
- [ ] Identify duplicate formatting logic
  - [ ] Map all formatting functions
  - [ ] Document common patterns
  - [ ] Identify unique requirements
- [ ] Create formatting pattern catalog
  - [ ] Document message types
  - [ ] Document embed patterns
  - [ ] Document common fields

### Phase 2: Create Unified Formatter
- [ ] Implement `WandererNotifier.Notifications.Formatter`
  - [ ] Create base formatting functions
  - [ ] Add specialized formatters for each type
  - [ ] Add helper functions for common patterns
- [ ] Create shared utilities
  - [ ] Add common text formatting
  - [ ] Add common field formatting
  - [ ] Add shared validation

### Phase 3: Migration
- [ ] Update Discord notifier
  - [ ] Use new formatter for all messages
  - [ ] Remove duplicate formatting code
  - [ ] Update tests
- [ ] Update other notification types
  - [ ] Migrate kill notifications
  - [ ] Migrate system notifications
  - [ ] Migrate character notifications