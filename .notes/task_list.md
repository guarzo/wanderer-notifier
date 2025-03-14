# WandererNotifier Implementation Tasks

## Structure Timer Notifier
- [ ] Create base modules
  - [ ] Create `WandererNotifier.Timers.Service` module
    - [ ] Add function to fetch from `/api/map/structure-timers` endpoint
    - [ ] Handle query params: `map_id`, `slug`, `system_id`
    - [ ] Parse response schema with required fields: `system_id`, `solar_system_id`, `name`, `status`
  - [ ] Create `WandererNotifier.Timers.State` module
    - [ ] Define timer state struct with fields matching API response
    - [ ] Add functions to compare timer states and detect changes

- [ ] Implement timer tracking
  - [ ] Add timer state comparison logic for:
    - [ ] New timers (not in previous state)
    - [ ] Changed timers (status or end_time changed)
    - [ ] Expiring timers (end_time approaching)
  - [ ] Add timer metadata tracking:
    - [ ] `character_eve_id`
    - [ ] `owner_name`/`owner_ticker`
    - [ ] `structure_type`
    - [ ] `solar_system_name`

## Kill Activity Summary Notifier
- [ ] Create base modules
  - [ ] Create `WandererNotifier.KillSummary.Service` module
    - [ ] Add function to fetch from `/api/map/systems-kills` endpoint
    - [ ] Handle query params: `map_id`, `slug`, `hours`
  - [ ] Create `WandererNotifier.KillSummary.Aggregator` module
    - [ ] Parse kill details from response:
      - [ ] `kill_id`
      - [ ] `kill_time`
      - [ ] `ship_name`/`ship_type_id`
      - [ ] `victim_name`/`victim_id`

- [ ] Implement kill tracking
  - [ ] Add aggregation functions for:
    - [ ] Kills by system
    - [ ] Kills by ship type
    - [ ] Kills by time period
  - [ ] Add threshold detection for high activity periods

## ACL Change Notifier
- [ ] Create base modules
  - [ ] Create `WandererNotifier.ACL.Monitor` module
    - [ ] Add function to fetch from `/api/map/acls` endpoint
    - [ ] Handle query params: `map_id`, `slug`
  - [ ] Create `WandererNotifier.ACL.Diff` module
    - [ ] Track ACL member changes via `/api/acls/{acl_id}/members` endpoint
    - [ ] Monitor member role updates via PUT endpoint
    - [ ] Track member deletions via DELETE endpoint

- [ ] Implement ACL tracking
  - [ ] Add change detection for:
    - [ ] New members (POST to members endpoint)
    - [ ] Role changes (PUT to member endpoint)
    - [ ] Member removals (DELETE to member endpoint)
  - [ ] Track member metadata:
    - [ ] `eve_alliance_id`
    - [ ] `eve_corporation_id`
    - [ ] `eve_character_id`
    - [ ] `role`

## Character Activity Notifier
- [ ] Create base modules
  - [ ] Create `WandererNotifier.Character.Activity` module
    - [ ] Add function to fetch from `/api/map/characters` endpoint
    - [ ] Handle query params: `map_id`, `slug`
  - [ ] Create `WandererNotifier.Character.State` module
    - [ ] Track character metadata:
      - [ ] `alliance_name`/`alliance_ticker`
      - [ ] `corporation_name`/`corporation_ticker`
      - [ ] `name`
      - [ ] `tracked` status

- [ ] Implement activity tracking
  - [ ] Add tracking for:
    - [ ] Corporation changes
    - [ ] Alliance changes
    - [ ] Tracking status changes
  - [ ] Add character info lookup via `/api/characters` endpoint

## Shared Infrastructure Updates
- [ ] Add API client modules
  - [ ] Create `WandererNotifier.API.Client` module
    - [ ] Add authentication handling for bearer tokens
    - [ ] Add base URL configuration
    - [ ] Add error handling for common response codes
  - [ ] Create response schemas matching API documentation

- [ ] Add configuration options
  - [ ] Add map identification config (map_id or slug)
  - [ ] Add API authentication config
  - [ ] Add notification thresholds config
  - [ ] Add polling intervals config
