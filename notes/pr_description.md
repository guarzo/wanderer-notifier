# Restore and Improve Kill Notification Filtering and System Classification

## Summary

This PR restores and improves the notification filtering logic that was lost during a previous refactor, as well as enhances system classification to properly prioritize API data. The main goal is to ensure notifications are properly filtered based on tracked systems and characters while improving the code organization and system type determination.

## Changes

1. **Centralized Notification Determiner**:

   - Created a new module `WandererNotifier.Services.NotificationDeterminer` that centralizes all notification filtering logic
   - Moved existing filtering functions from `KillProcessor` to the new module
   - Added proper documentation and improved error handling

2. **Improved Notification Criteria**:

   - Kill notifications are now properly filtered based on:
     - Global feature flag (`kill_notifications_enabled?`)
     - Tracked systems (from cache)
     - Tracked characters (from cache)
   - A notification is sent only if the kill occurred in a tracked system OR involved a tracked character (as victim or attacker)
   - System and character notifications also use centralized determination:
     - `should_notify_system?` for system-related notifications
     - `should_notify_character?` for character-related notifications

3. **Better Code Organization**:

   - Removed duplicated code from `KillProcessor`
   - Updated all notification workflows to use the centralized notification determiner:
     - Kill notifications in `KillProcessor`
     - System notifications in `Api.Map.Systems`
     - Character notifications in `Api.Map.Characters`
   - Added detailed logging to track notification decisions
   - Consistent notification filtering logic across the entire application

4. **Improved System Classification**:

   - Fixed duplicative system type classification logic
   - Implemented proper prioritization for system type determination:
     1. Use API-provided data such as "type_description", "class_title", or "system_class"
     2. Only fall back to ID-based classification when API doesn't provide type information
   - Added comprehensive documentation for system classification
   - Enhanced the data extraction process to preserve more API data

5. **Documentation Updates**:
   - Updated the killmail notification documentation to reflect the changes
   - Added a new section on notification filtering logic
   - Clarified the workflow steps for notification determination
   - Added documentation for system type determination

## Testing

- Tested with multiple killmail examples from zKillboard
- Verified that notifications are properly filtered based on tracked systems
- Verified that notifications are properly filtered based on tracked characters
- Confirmed that the global feature flag works correctly
- Tested system notifications with the centralized determiner
- Tested character notifications with the centralized determiner
- Verified that system classification properly prioritizes API data

## Additional Notes

This PR doesn't add any new features but restores and improves the existing functionality that was lost during a previous refactor. The changes improve code organization by centralizing notification decision making in a single module and fixing duplicative system classification logic, making the system more maintainable and consistent. All changes are backward compatible and should not affect existing workflows.
