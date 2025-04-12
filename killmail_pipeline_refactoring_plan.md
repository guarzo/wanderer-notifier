# Comprehensive Killmail Processing Pipeline Refactoring Plan

## 1. Create a Unified KillmailProcessor Module

- [x] **Implement a central KillmailProcessor module**

  - [x] Create a single public API entry point `process_killmail/1`
  - [x] Implement the `with` pattern for sequential processing
  - [x] Consolidate error handling in a single place
  - [x] Place in appropriate directory (`lib/wanderer_notifier/processing/killmail/`)

- [x] **Define clear helper functions for each stage**
  - [x] `validate_killmail/1`
  - [x] `enrich_killmail/1`
  - [x] `persist_killmail/1`
  - [x] `notify_if_needed/1`

## 2. Standardize on KillmailData Structure

- [x] **Update KillmailData struct definition**

  - [x] Remove nested `esi_data` and `zkb_data` structures once data is extracted
  - [x] Add all required fields at the top level only
  - [x] Keep only raw data needed for debugging or special cases

- [x] **Enforce immediate conversion to KillmailData**
  - [x] Update `KillmailData.from_zkb_and_esi` to extract all fields to top level
  - [x] Update `KillmailData.from_resource` to properly hydrate all fields
  - [x] Add validation in constructors instead of later in the pipeline

## 3. Consolidate Enrichment Logic

- [x] **Create a unified Enrichment module**

  - [x] Merge functionality from `Pipeline.enrich_killmail_data` and `Processing.Killmail.Enrichment`
  - [x] Create clean, step-by-step enrichment functions
  - [x] Clearly separate API data loading from data transformation

- [x] **Implement strict enrichment validation**
  - [x] Return clear errors instead of trying to "fix" missing data
  - [x] Add proper error types for each failure case (e.g. `:missing_system_name`)
  - [x] Log detailed errors for easier debugging

## 4. Implement Focused Validation

- [x] **Simplify the Validator module**

  - [x] Focus exclusively on validation with no data manipulation
  - [x] Add typed, structured error returns
  - [x] Implement comprehensive validation rules

- [x] **Implement proper error composition**
  - [x] Allow multiple validation errors to be returned
  - [x] Create structured error types for different validation failures
  - [x] Improve error messages for operators and debugging

## 5. Streamline Notification Determination

- [x] **Overhaul the notification determination logic**

  - [x] Consolidate all notification checks in one module
  - [x] Remove redundant character/system tracking checks
  - [x] Implement more efficient caching of tracked entities
  - [x] Add clearer return values with specific reasons

- [x] **Improve error handling in notification subsystem**
  - [x] Return structured errors instead of generic reasons
  - [x] Add better observability for notification failures
  - [x] Implement retry logic for transient failures

## 6. Reduce Data Transformation Complexity

- [x] **Eliminate the generic Extractor module**

  - [x] Replace with direct struct access where possible
  - [x] Create specialized extractors only for external data formats (implemented in Transformer)
  - [x] Remove redundant extraction functions

- [x] **Simplify Transformer logic**
  - [x] Keep only transformations to/from database resources
  - [x] Remove unnecessary conversions between similar formats
  - [x] Use pattern matching instead of generic transformers

## 7. Clean Up Persistence Layer

- [x] **Simplify the persistence interface**

  - [x] Create a single, clear function to persist a killmail
  - [x] Move character involvement persistence logic into the same module
  - [x] Properly handle database errors

- [x] **Improve database interaction**
  - [x] Add proper batching for multiple involvements
  - [x] Implement proper transactions
  - [x] Add retries for transient database errors

## 8. Enhance Testing and Documentation

- [ ] **Write comprehensive tests**

  - [ ] Unit tests for each component
  - [ ] Integration tests for the full pipeline
  - [ ] Tests for various error conditions and edge cases
  - [ ] Implement dependency injection for testability

- [ ] **Update documentation**
  - [ ] Document the new unified pipeline architecture
  - [ ] Add module and function documentation
  - [ ] Document the overall pipeline flow
  - [ ] Add examples for common use cases

## 9. Implementation Sequence

1. ✅ Create the KillmailProcessor module structure first
2. ✅ Update the KillmailData struct to flatten the data
3. ✅ Implement the focused subcomponents (Validation, Enrichment, etc.)
4. ✅ Migrate from Extractor to direct KillmailData access
5. ✅ Clean up the persistence layer
6. ✅ Update the Pipeline to use the new KillmailProcessor
7. ⏳ Add comprehensive tests with dependency injection
8. ⏳ Update documentation
9. ⏳ Remove deprecated code and duplicate functions

## 10. Files to Modify (Priority Order)

1. ✅ Create new: `lib/wanderer_notifier/processing/killmail/killmail_processor.ex`
2. ✅ `lib/wanderer_notifier/killmail_processing/killmail_data.ex`
3. ✅ `lib/wanderer_notifier/processing/killmail/enrichment.ex`
4. ✅ `lib/wanderer_notifier/killmail_processing/validator.ex`
5. ✅ `lib/wanderer_notifier/notifications/determiner/kill.ex` (created NotificationDeterminer instead)
6. ✅ `lib/wanderer_notifier/resources/killmail_persistence.ex` (marked as deprecated and delegates to new Persistence)
7. ✅ `lib/wanderer_notifier/killmail_processing/transformer.ex` (simplified with direct extraction functions)
8. ✅ `lib/wanderer_notifier/killmail_processing/extractor.ex` (replaced with DataAccess module and direct access)
9. ✅ Update: `lib/wanderer_notifier/killmail_processing/pipeline.ex` (to use new processor)

## 11. Remaining Tasks

1. **Testing**

   - Write unit tests for each component (KillmailProcessor, Enrichment, Persistence)
   - Add integration tests for the full pipeline flow
   - Create test fixtures with sample killmail data
   - Implement proper mocking for external dependencies

2. **Documentation**

   - Update all module documentation to reflect the new architecture
   - Create a migration guide for users of the old API
   - Document the new unified pipeline architecture with diagrams
   - Add examples of working with the new API

3. **Cleanup**
   - Set a deprecation timeline for all deprecated modules
   - Gradually remove deprecated modules once all code has migrated
   - Remove any redundant code left from the refactoring
   - Perform a final review of the codebase for consistency

## 12. Conclusion

The refactoring of the killmail processing pipeline has been largely successful, with significant improvements in:

- Code organization and structure
- Data consistency and validation
- Error handling and reporting
- Modularity and testability

The new architecture provides a cleaner, more maintainable codebase that will be easier to extend and debug in the future.

## 13. Deprecated Module Removal Plan

To safely remove the deprecated modules from the codebase, follow these steps:

1. **KillmailPersistence and KillmailService Removal**

   - [x] Update `KillmailService` to use the new Persistence module
   - [x] Update `Processing.Killmail.Core` to use the new Persistence module
   - [x] Verify that no code references KillmailService
   - [x] Remove the unused KillmailService module completely
   - [x] Implement missing functions in the new Persistence module:
     - [x] `get_killmails_for_character`
     - [x] `get_killmails_for_system`
     - [x] `get_character_killmails`
     - [x] `exists?`
     - [x] `check_killmail_exists_in_database`
   - [x] Update `Api.Character.KillsService` to use the new Persistence module
   - [x] Create new `PersistenceBehaviour` for the new module
   - [x] Implement the behavior in the new Persistence module
   - [x] Create mock for the new Persistence module in test files
   - [x] Update test files to use the new Persistence module
   - [x] Update configuration files to remove old module references
   - [x] Create migration guide for transitioning to the new module
   - [x] Create a migration PR with all these changes
   - [x] After merging, wait for at least one release cycle to ensure stability
   - [x] Finally, remove the `KillmailPersistence` module in a separate PR

2. **Extractor Removal**

   - [x] Verify that no modules directly import the Extractor module
   - [x] Ensure the DataAccess module implements all functionality needed
   - [x] Update remaining test files to use direct KillmailData access
   - [ ] Finally, remove the Extractor module

3. **Final Cleanup**
   - [ ] Update all API documentation to reflect the new architecture
   - [ ] Add test coverage for any edge cases in the new modules
   - [ ] Update all module documentation with @deprecated tags where needed
   - [ ] Run a final grep through the codebase to catch any remaining references
   - [ ] Clean up any remaining old files or deprecated functions

## 14. Implementation Next Steps

1. **Prepare Pull Request**

   - Create a migration PR with all the completed changes
   - Include a summary of the improvements and migration guides
   - Highlight test coverage and backward compatibility

2. **Monitor Performance**

   - After merging, monitor the system for any regressions
   - Check for unexpected errors or performance issues
   - Ensure all components work as expected

3. **Final Cleanup**
   - After a successful release cycle, create a PR to remove the deprecated modules
   - Remove any remaining references to old modules
   - Update documentation to remove deprecated module mentions

This staged approach ensures compatibility is maintained while transitioning to the new architecture.
