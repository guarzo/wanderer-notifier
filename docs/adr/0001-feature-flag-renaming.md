# ADR 0001: Feature Flag Renaming

## Status

Accepted

## Context

The application had two feature flags with names that did not clearly reflect their purpose:

1. `map_tools_enabled` - This flag controlled map-based activity charts functionality, but the name suggested a broader scope than just charts.
2. `persistence_enabled` - This flag controlled killmail persistence and chart generation, but the name didn't clearly indicate the user-facing feature.

This naming scheme caused confusion when developers needed to understand which flags controlled specific features, particularly related to charts functionality.

## Decision

We decided to rename these feature flags to better reflect their purpose:

1. `map_tools_enabled` → `map_charts_enabled`
2. `persistence_enabled` → `kill_charts_enabled`

Additionally, we:

1. Added new helper methods in the Config module with the new names
2. Maintained backward compatibility by keeping the old methods and having the new methods call them as fallbacks
3. Updated all references in the codebase to use the new method names
4. Updated the documentation to reflect the new naming scheme
5. Updated the frontend components to use the more descriptive names

## Consequences

### Positive

- Feature flag names now clearly indicate their purpose
- Frontend code more accurately reflects the functionality being controlled
- Documentation is clearer about which flags control which features
- API remains compatible with existing clients by maintaining the original property names in responses

### Negative

- Some temporary duplication in the codebase to maintain backward compatibility
- Need to support both old and new environment variable names during transition

## Implementation

The following changes were made:

1. Added new feature definitions in the Config module:

   - Added `map_charts` with env var `ENABLE_MAP_CHARTS`
   - Added `kill_charts` with env var `ENABLE_KILL_CHARTS`

2. Added new helper methods in the Config module:

   - `map_charts_enabled?`
   - `kill_charts_enabled?`

3. Updated all references to the old methods throughout the codebase:

   - Updated Chart Controller and API endpoints
   - Updated Schedulers to use the new method names
   - Updated Router to use the new method names
   - Maintained backward compatibility in API responses

4. Updated frontend React components to use the new naming:

   - `mapToolsEnabled` → `mapChartsEnabled`
   - `persistenceEnabled` → `killChartsEnabled`

5. Updated documentation to reflect the new naming scheme:

   - Updated feature flags documentation
   - Updated kill persistence documentation

6. Removed unsupported chart types:
   - Removed `activity_timeline` chart functionality
   - Removed `activity_distribution` chart functionality
   - Updated all controllers and adapters to return appropriate error messages for removed chart types
   - Updated frontend to only show supported chart types

## Future Work

- Eventually remove the legacy methods and properties once all clients have migrated to the new naming scheme
- Consider a formal deprecation process for future naming changes
