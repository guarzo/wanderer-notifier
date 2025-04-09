# Killmail Refactoring Scripts

This directory contains scripts to help with Phase 5 of the Killmail refactoring project - the gradual transition to the new KillmailProcessing modules.

## Scripts Overview

### Analysis Scripts

1. **find_killmail_references.exs**
   - **Purpose**: Find all references to the Killmail module in the codebase
   - **Usage**: `mix run scripts/find_killmail_references.exs`
   - **Output**: Summary of all Killmail references grouped by directory

### Migration Helper Scripts

1. **migrate_killmail_usage.exs**

   - **Purpose**: Analyze a single file and suggest migration changes
   - **Usage**: `mix run scripts/migrate_killmail_usage.exs path/to/file.ex`
   - **Output**: Suggested import statements and function replacements

2. **convert_test_fixtures.exs**
   - **Purpose**: Help convert test fixture data from maps to KillmailData structs
   - **Usage**: `mix run scripts/convert_test_fixtures.exs path/to/test_file.ex`
   - **Output**: Suggested struct conversions for test fixtures

### Progress Tracking Scripts

1. **track_migration_progress.exs**
   - **Purpose**: Track overall progress of the migration effort
   - **Usage**: `mix run scripts/track_migration_progress.exs`
   - **Output**: Progress report showing completion percentage by directory

### Cleanup Scripts

1. **add_deprecation_warnings.exs**
   - **Purpose**: Add proper deprecation warnings to the Killmail module
   - **Usage**: `mix run scripts/add_deprecation_warnings.exs`
   - **Output**: Updated Killmail module with deprecation warnings

## Suggested Migration Workflow

1. **Analyze the codebase**:

   ```
   mix run scripts/find_killmail_references.exs
   ```

   This gives you a complete picture of Killmail usage.

2. **Prioritize modules to migrate**:

   - Start with high-level components (ZKill websocket, notification determiners)
   - Then move to data processing components

3. **For each file to migrate**:

   ```
   mix run scripts/migrate_killmail_usage.exs path/to/file.ex
   ```

   This provides suggested changes.

4. **For test files with fixture data**:

   ```
   mix run scripts/convert_test_fixtures.exs path/to/test_file.ex
   ```

   This helps convert test data to KillmailData structs.

5. **Track your progress**:

   ```
   mix run scripts/track_migration_progress.exs
   ```

   This helps visualize migration progress and suggests which files to tackle next.

6. **Add deprecation warnings** (once initial migration is underway):
   ```
   mix run scripts/add_deprecation_warnings.exs
   ```
   This helps identify remaining usages through compiler warnings.

## Best Practices

1. **Incremental changes**: Update one module at a time
2. **Test after each change**: Run tests to ensure functionality is maintained
3. **Use feature flags**: For higher-risk components, use feature flags to toggle implementation
4. **Verify with integration tests**: Ensure end-to-end functionality still works
5. **Document your changes**: Add comments explaining any significant changes

## Troubleshooting

- **Function name changes**: Remember that `get_attacker` becomes `get_attackers` (plural)
- **Return type differences**: Some functions may have slightly different return types in the new modules
- **KillmailData struct**: Use proper pattern matching for the struct rather than map access
- **Test data**: Ensure all test data is updated to use the KillmailData struct

## Help and Support

If you encounter issues during migration:

1. Refer to the `docs/manual_code_update_guide.md` document
2. Check `docs/module_update_template.md` for common patterns
3. Follow the verification checklist in `docs/module_update_template.md`
