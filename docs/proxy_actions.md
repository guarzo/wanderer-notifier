### Phase 1: Audit and Document
- [ ] Create comprehensive list of proxy modules
  - [ ] Document `WandererNotifier.NotifierBehaviour`
  - [ ] Document `WandererNotifier.Maintenance.Scheduler`
  - [ ] Document legacy ESI service functions
  - [ ] Document deprecated feature functions
- [ ] Map all usages of proxy modules
  - [ ] Use grep to find all references
  - [ ] Create dependency graph
  - [ ] Document test dependencies

### Phase 2: Update References
- [ ] Update NotifierBehaviour references
  - [ ] Change imports to use `WandererNotifier.Notifiers.Behaviour`
  - [ ] Update any custom implementations
  - [ ] Update tests
- [ ] Update Maintenance.Scheduler references
  - [ ] Switch to `WandererNotifier.Services.Maintenance.Scheduler`
  - [ ] Update supervisor configurations
  - [ ] Update tests
- [ ] Update ESI Service calls
  - [ ] Replace `get_esi_kill_mail` with `get_killmail`
  - [ ] Update dependent modules
  - [ ] Update tests
- [ ] Update Feature module references
  - [ ] Replace `track_all_systems?` with `track_kspace_systems?`
  - [ ] Update dependent modules
  - [ ] Update tests

### Phase 3: Remove Legacy Code
- [ ] Remove proxy modules
  - [ ] Delete `WandererNotifier.NotifierBehaviour`
  - [ ] Delete `WandererNotifier.Maintenance.Scheduler`
- [ ] Remove deprecated functions
  - [ ] Remove legacy ESI service functions
  - [ ] Remove deprecated feature functions
- [ ] Clean up documentation
  - [ ] Remove references to old modules
  - [ ] Update architecture documentation
  - [ ] Update API documentation