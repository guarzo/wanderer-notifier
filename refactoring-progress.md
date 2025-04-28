# Refactoring Progress

## 1. HTTP Client Cleanup ✅

- Created lib/wanderer_notifier/http_client/behaviour.ex
- Updated lib/wanderer_notifier/http_client/httpoison.ex to use new behavior
- Deleted the root-level lib/wanderer_notifier/http_client.ex

## 2. Map API Context Consolidation 🔄

- Created lib/wanderer_notifier/api/clients directory
- Created lib/wanderer_notifier/api/clients/map_characters.ex
- Created lib/wanderer_notifier/api/clients/map_system.ex (basic structure)
- TODO: Complete the following client modules:
  - [ ] lib/wanderer_notifier/api/clients/map_system_static_info.ex
  - [ ] lib/wanderer_notifier/api/clients/map_url_builder.ex
  - [ ] lib/wanderer_notifier/api/clients/map_response_validator.ex
  - [ ] lib/wanderer_notifier/api/clients/map_universe.ex
- TODO: Update all references to the old modules
- TODO: Delete original map API modules once migration is complete

## 3. Killmail / ZKill Consolidation 📝

- TODO: Merge zkill.ex functionality into killmail context
- TODO: Merge lib/wanderer_notifier/api/zkill/client.ex into killmail context
- TODO: Consolidate duplicate implementations between zkill/ and killmail/zkill/
- TODO: Update all references to the consolidated modules
- TODO: Remove the old modules and directories

## 4. Notifications vs. Notifiers 📝

- TODO: Analyze the overlap between notifications/ and notifiers/
- TODO: Decide on a clear boundary between notification generation and delivery
- TODO: Reorganize into a single coherent structure
- TODO: Update all references
- TODO: Remove duplicated modules

## 5. Generic "Behaviours" Folder Tidy-up 📝

- TODO: Relocate date_behaviour.ex into appropriate context (utilities?)
- TODO: Relocate notifier_factory_behaviour.ex into notifications or notifiers context
- TODO: Update references to relocated behaviours
- TODO: Delete the behaviours/ directory once empty

## 6. Root-level Module Remnants 📝

- TODO: Move character.ex functionality into character/ context
- TODO: Move zkill.ex functionality into killmail/ context
- TODO: Review other root-level modules and relocate or remove them
- TODO: Ensure module names match file paths consistently

Legend:

- ✅ Complete
- 🔄 In Progress
- 📝 Not Started
