# Comprehensive Killmail Processing Pipeline Refactoring Plan

## 1. Create a Unified KillmailProcessor Module

- [ ] **Implement a central KillmailProcessor module**

  - [ ] Create a single public API entry point `process_killmail/1`
  - [ ] Implement the `with` pattern for sequential processing
  - [ ] Consolidate error handling in a single place
  - [ ] Place in appropriate directory (`lib/wanderer_notifier/processing/killmail/`)

- [ ] **Define clear helper functions for each stage**
  - [ ] `validate_killmail/1`
  - [ ] `enrich_killmail/1`
  - [ ] `persist_killmail/1`
  - [ ] `notify_killmail/1`

## 2. Standardize on KillmailData Structure

- [ ] **Update KillmailData struct definition**

  - [ ] Remove nested `esi_data` and `zkb_data` structures once data is extracted
  - [ ] Add all required fields at the top level only
  - [ ] Keep only raw data needed for debugging or special cases

- [ ] **Enforce immediate conversion to KillmailData**
  - [ ] Update `KillmailData.from_zkb_and_esi` to extract all fields to top level
  - [ ] Update `KillmailData.from_resource` to properly hydrate all fields
  - [ ] Add validation in constructors instead of later in the pipeline

## 3. Consolidate Enrichment Logic

- [ ] **Create a unified Enrichment module**

  - [ ] Merge functionality from `Pipeline.enrich_killmail_data` and `Processing.Killmail.Enrichment`
  - [ ] Create clean, step-by-step enrichment functions
  - [ ] Clearly separate API data loading from data transformation

- [ ] **Implement strict enrichment validation**
  - [ ] Return clear errors instead of trying to "fix" missing data
  - [ ] Add proper error types for each failure case (e.g. `:missing_system_name`)
  - [ ] Log detailed errors for easier debugging

## 4. Implement Focused Validation

- [ ] **Simplify the Validator module**

  - [ ] Focus exclusively on validation with no data manipulation
  - [ ] Add typed, structured error returns
  - [ ] Implement comprehensive validation rules

- [ ] **Implement proper error composition**
  - [ ] Allow multiple validation errors to be returned
  - [ ] Create structured error types for different validation failures
  - [ ] Improve error messages for operators and debugging

## 5. Streamline Notification Determination

- [ ] **Overhaul the notification determination logic**

  - [ ] Consolidate all notification checks in one module
  - [ ] Remove redundant character/system tracking checks
  - [ ] Implement more efficient caching of tracked entities
  - [ ] Add clearer return values with specific reasons

- [ ] **Improve error handling in notification subsystem**
  - [ ] Return structured errors instead of generic reasons
  - [ ] Add better observability for notification failures
  - [ ] Implement retry logic for transient failures

## 6. Reduce Data Transformation Complexity

- [ ] **Eliminate the generic Extractor module**

  - [ ] Replace with direct struct access where possible
  - [ ] Create specialized extractors only for external data formats
  - [ ] Remove redundant extraction functions

- [ ] **Simplify Transformer logic**
  - [ ] Keep only transformations to/from database resources
  - [ ] Remove unnecessary conversions between similar formats
  - [ ] Use pattern matching instead of generic transformers

## 7. Clean Up Persistence Layer

- [ ] **Simplify the persistence interface**

  - [ ] Create a single, clear function to persist a killmail
  - [ ] Move character involvement persistence logic into the same module
  - [ ] Properly handle database errors

- [ ] **Improve database interaction**
  - [ ] Add proper batching for multiple involvements
  - [ ] Implement proper transactions
  - [ ] Add retries for transient database errors

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

1. Create the KillmailProcessor module structure first
2. Update the KillmailData struct to flatten the data
3. Implement the focused subcomponents (Validation, Enrichment, etc.)
4. Wire everything together in the processor
5. Add comprehensive tests with dependency injection
6. Update documentation
7. Remove deprecated code and duplicate functions

## 10. Files to Modify (Priority Order)

1. Create new: `lib/wanderer_notifier/processing/killmail/killmail_processor.ex`
2. `lib/wanderer_notifier/killmail_processing/killmail_data.ex`
3. `lib/wanderer_notifier/processing/killmail/enrichment.ex`
4. `lib/wanderer_notifier/killmail_processing/validator.ex`
5. `lib/wanderer_notifier/notifications/determiner/kill.ex`
6. `lib/wanderer_notifier/resources/killmail_persistence.ex`
7. `lib/wanderer_notifier/killmail_processing/transformer.ex` (minimize or remove)
8. `lib/wanderer_notifier/killmail_processing/extractor.ex` (minimize or remove)
9. Update: `lib/wanderer_notifier/killmail_processing/pipeline.ex` (to use new processor)
