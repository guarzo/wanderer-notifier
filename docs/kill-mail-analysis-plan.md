# Kill Mail Comparison Improvement Plan

## Per-Character Comparison Enhancement

- [x] Add per-character breakdown in the comparison tool

  - [x] Display each character's kill counts in DB vs. zKill
  - [x] Show missing percentage and count per character
  - [x] Sort by highest discrepancy first

- [x] Implement detailed analysis view

  - [x] Create expandable row or modal for specific character analysis
  - [x] Show specific missing kill IDs
  - [x] Add "Sync" button per character to pull latest kills

- [x] Add kill detail view
  - [x] Implement click handler for missing kill IDs
  - [x] Fetch and display full kill details from zKill
  - [x] Show possible reason why the kill was missed

## Performance Improvements

- [x] Implement server-side caching
  - [x] Create cached endpoints for common time ranges
  - [x] Add cache invalidation mechanism
  - [x] Implement UI to leverage cached data
  - [x] Provide fallback to custom date ranges when needed

## Missing Kill Tracking

- [ ] Create a "rejected_killmails" tracking system

  - [ ] Design table schema (killmail_id, character_id, timestamp, rejection_reason)
  - [ ] Implement storage mechanism for rejected kills
  - [ ] Add queries to retrieve rejection data

- [ ] Enhance the persistence logic

  - [ ] Modify `safely_persist_killmail` to return explicit rejection reasons
  - [ ] Log rejections with full character context
  - [ ] Keep track of non-persistence reasons

- [ ] Add rejection summary to comparison tool
  - [ ] Display counts of rejected kills by reason
  - [ ] Allow filtering by rejection type
  - [ ] Add timestamp analysis of rejections

## Data Flow Metrics

- [ ] Implement core metrics collection

  - [ ] Kills fetched per character
  - [ ] Kills attempted to persist
  - [ ] Successful vs. failed persistence attempts
  - [ ] Cache hit/miss rates

- [ ] Add timing measurements

  - [ ] zKill API request duration
  - [ ] ESI enrichment process time
  - [ ] Total processing time per character

- [ ] Create metrics visualization
  - [ ] Build dashboard section for metrics
  - [ ] Implement correlation analysis between metrics and missing data
  - [ ] Add alerting for abnormal patterns

## Forensic Investigation Tools

- [ ] Develop "deep comparison" functionality

  - [ ] Create interface to select character and time period
  - [ ] Implement detailed fetch and processing with enhanced logging
  - [ ] Generate comprehensive report of where/why kills are dropped

- [ ] Create kill trace function
  - [ ] Implement tracing for specific kill ID through system
  - [ ] Visualize all decision points in processing pipeline
  - [ ] Document persistence/rejection decision

## Edge Case Analysis

- [ ] Research specific edge case scenarios

  - [ ] High-volume kill processing
  - [ ] Age-based processing differences
  - [ ] Attacker vs. victim role differences
  - [ ] NPC vs. player kill handling

- [ ] Implement kill categorization in comparison results
  - [ ] Group missing kills by type
  - [ ] Analyze patterns in missing kills
  - [ ] Create visualization of kill categories vs. missing probability
