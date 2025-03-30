# Important Notes About This Codebase

1. **Caching System**:

   - All cache access modules (`Repository`, `CacheRepo`, and fully qualified paths) point to the same location
   - Systems are stored at `map:systems` - there's only one source of truth
   - No fallbacks should be used for cache lookups

2. **Character Handling**:

   - `eve_id` must be used from the map response - it's a required field
   - No fallbacks should be added for `character_id` or other fields
   - Character structure should not be modified to work around validation
   - The map API response has a consistent structure - don't add fallbacks that assume different structures
   - The only fallback for eve_id is in test environment, not in production
   - DO NOT add new fields or fallback paths to character creation
   - NEVER modify extract_eve_id, validate_eve_id, or other character validation methods

3. **Notification System**:

   - All notification functions should use `WandererNotifier.Notifiers.Factory` as `NotifierFactory`
   - Avoid adding debug endpoints - fix core issues directly

4. **General Principles**:
   - Focus on fixing issues, not adding more diagnostics
   - Don't introduce new fallbacks or bypasses for validation
   - Stick to existing code patterns and validations
   - When the codebase says something is required, believe it and fix the source of missing data
   - Respect the existing structure of the API responses - don't invent new fields

## Character Structure

The character creation expects:

- `eve_id` field in the map API response
- No fallbacks except in test environment
- The API structure is fixed and known - do not add or modify field paths

## Common Break Points:

- Adding fallbacks for missing eve_id (WRONG - fix the data source instead)
- Working around character validation (WRONG - respect the validation)
- Adding complex debug code instead of fixing core issues
