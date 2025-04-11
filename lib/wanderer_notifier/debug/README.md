# Kill Processing Debugging Tools

This directory contains tools to help debug issues with kill processing in the Wanderer Notifier application. Use these tools to diagnose problems with the killmail processing pipeline, especially when processing appears to hang or not complete.

## IMPORTANT: These debug tools use the REAL production code paths

A key principle of these tools is that they use the exact same code paths as production. They don't stub, mock, or replace any parts of the pipeline with special debug versions. This ensures that issues identified with these tools are actual issues in the production pipeline.

The debug tools provide:

1. Convenient entry points (e.g., using character indices instead of IDs)
2. Enhanced logging at critical points
3. Hardcoded known-good character IDs for testing
4. Detailed error reporting

They do NOT replace or modify the actual pipeline code.

## Quick Start

# Direct Pipeline Testing (Simplest Method)

The most direct way to test the killmail pipeline is to use the `direct_process` function, which simply:

1. Fetches a kill from ZKillboard
2. Passes it directly to the real production pipeline
3. Returns the result with detailed information about what happened

```elixir
# Directly process a specific killmail ID with the real pipeline
WandererNotifier.Debug.ProcessKillDebug.direct_process(123456789) # Replace with actual killmail_id
```

This is the most direct approach with no special handling or modifications. It uses exactly the same code path as the production pipeline.

## What Success Looks Like

**Important:** When the pipeline succeeds, you'll see:

1. A success message in the logs showing the kill details
2. Information about whether the kill was persisted to the database
3. Information about whether a notification was sent
4. The return value will be a large data structure - this is expected!

**Example of successful output in the logs:**

```
✅ PIPELINE SUCCESS! Killmail processed successfully through the REAL pipeline!
* Killmail ID: 126186577
* Duration: 235ms
* System: J160941
* Victim: Some Character in Retriever

RESULTS:
* Database: ✅ Persisted to database
* Notification: ✅ Notification sent

The return value is a fully processed KillmailData struct containing all kill details.
This is the expected successful result and NOT an error!
```

**Example of successful return value:**

```
{:ok, %WandererNotifier.KillmailProcessing.KillmailData{
  killmail_id: 126186577,
  solar_system_id: 31000376,
  solar_system_name: "J160941",
  esi_data: %{...},  # Contains all the ESI data
  zkb_data: %{...},  # Contains ZKill data
  victim: %{...},    # Contains victim data
  attackers: [...],  # Contains attacker data
  ...
}}
```

Seeing this large data structure means the pipeline worked correctly! It's not an error - it's the expected format of the processed data. The debug tools will extract and display key information so you don't have to dig through the structure.

To diagnose issues with kill processing, try these debugging functions in order:

```elixir
# Use the hardcoded debug character (guaranteed to have kills)
# This is the recommended starting point
WandererNotifier.Debug.ProcessKillDebug.process_single_kill(0)

# First, check if a single kill can be processed for a specific character
# Use the first character in your tracked characters list
WandererNotifier.Debug.ProcessKillDebug.process_single_kill(1)

# Try processing a specific killmail ID with the debug character
killmail_id = 123456789 # Replace with a specific killmail ID
WandererNotifier.Debug.ProcessKillDebug.process_specific_kill(0, killmail_id)

# If those succeed, try the full character processing pipeline
WandererNotifier.Debug.ProcessKillDebug.debug_character_processing(0)

# For detailed pipeline analysis of a specific killmail
WandererNotifier.Debug.PipelineDebug.analyze_pipeline(killmail_id, 0)
```

## Diagnosing Issues

When a kill fails to process, check the logs to see which stage failed:

1. **Data Fetching**: Failures might be due to API issues or rate limits
2. **Data Transformation**: Failures might indicate incompatible data structures
3. **Enrichment**: Failures might indicate missing lookup data (e.g., system names)
4. **Validation**: Failures might indicate missing required fields
5. **Persistence**: Failures might indicate database connectivity issues
6. **Notification**: Failures might indicate messaging service issues

The most common issues are:

- Missing system data
- Invalid character data
- Database connection issues
- API rate limits or timeouts

## Available Tools

### ProcessKillDebug Module

For single kill or character-based testing:

- `process_single_kill(character_index, opts)` - Process a single kill for a character
- `process_specific_kill(character_index, kill_id)` - Process a specific killmail
- `debug_character_processing(character_index, opts)` - Process all kills for a character

### PipelineDebug Module

For analyzing pipeline steps of a specific killmail:

- `analyze_pipeline(killmail_id, character_index)` - Analyze a killmail going through the pipeline

## Debug Character

The hardcoded debug character ID (`640_170_087`) is a known character that has kills. Use this character when your own tracked characters might not have any recent kills, making it easier to test the pipeline.

Use character index `0` to access this debug character:

```elixir
WandererNotifier.Debug.ProcessKillDebug.process_single_kill(0)
```

## Available Debugging Tools

### `ProcessKillDebug` Module

This module helps debug the process of retrieving and processing kills for a specific character:

- `process_single_kill(character_id_or_index, opts \\ [])` - Process a single recent kill for a character
  - Special value: Use `0` as the index to use a hardcoded debug character ID that's guaranteed to have kills
  - Options: `force_debug_character: true` will use the debug character regardless of input ID
- `process_specific_kill(character_id_or_index, killmail_id, opts \\ [])` - Process a specific killmail ID for a character
- `debug_character_processing(character_id_or_index, opts \\ [])` - Debug the full character kill processing mechanism

### `PipelineDebug` Module

This module analyzes the killmail processing pipeline in detail:

- `analyze_pipeline(killmail_id, character_id, opts \\ [])` - Step through each pipeline stage separately

### `KillmailTools` Module

Existing tools for forcing notification processing:

- `log_next_killmail()` - Enable detailed logging for the next killmail received
- `notify_next_killmail()` - Force notification for the next killmail received
- `force_notify_killmail_by_id(killmail_id)` - Force notification for a specific killmail ID

## Diagnosing Common Issues

### Hanging Process

If the kill processing appears to hang and never completes:

1. Use `ProcessKillDebug.process_single_kill(0)` to test processing a single kill with the debug character
2. Check for errors in the output, particularly around ESI data retrieval or enrichment
3. If a specific kill is problematic, use `PipelineDebug.analyze_pipeline(kill_id, character_id)` to analyze each stage separately

### No Kills Being Processed

If no kills are being processed at all:

1. Verify ZKill API access by using `ProcessKillDebug.debug_character_processing(0, kill_limit: 1)`
2. Check if the tracked characters are correctly set up
3. Look for API throttling or rate limiting issues in the output

### Errors During Processing

If you see errors during processing:

1. Use `PipelineDebug.analyze_pipeline(kill_id, character_id)` to identify which stage is failing
2. Look for validation errors, particularly around missing data like system names or ship types
3. Check enrichment errors that might indicate issues with ESI API access

## Examples

### Example 1: Debug processing with hardcoded debug character

```elixir
iex> WandererNotifier.Debug.ProcessKillDebug.process_single_kill(0)
```

### Example 2: Process a specific killmail ID with debug character

```elixir
iex> WandererNotifier.Debug.ProcessKillDebug.process_specific_kill(0, 123456789)
```c

### Example 3: Analyze all pipeline stages for a killmail

```elixir
iex> WandererNotifier.Debug.PipelineDebug.analyze_pipeline(123456789, 90129202)
```

## Using the Debug Character

The debug tools include a hardcoded character ID (640170087) that's known to have killmails. This makes testing more reliable when your tracked characters might not have recent kills.

There are two ways to use the debug character:

1. Use index `0` with any debug function:

   ```elixir
   WandererNotifier.Debug.ProcessKillDebug.process_single_kill(0)
   ```

2. Use the `force_debug_character: true` option with any character ID/index:
   ```elixir
   WandererNotifier.Debug.ProcessKillDebug.process_single_kill(1, force_debug_character: true)
   ```

This ensures you can test the pipeline even if your regular tracked characters have no activity.

## Troubleshooting Recommendations

1. **Start simple**: Test with the debug character first using `process_single_kill(0)`
2. **Increase verbosity**: Use `verbose: true` option to get more detailed logs
3. **Check API health**: Ensure both ZKill and ESI APIs are accessible
4. **Look for validation issues**: Most processing problems occur during validation or enrichment
5. **Check database connectivity**: Ensure database connections are working for persistence

# Advanced Debugging with Detailed Pipeline Tracing

For advanced debugging needs, we've provided detailed tracing capabilities that show exactly what's happening in each pipeline stage. These tools enable you to see the exact function calls and transformations that occur during pipeline execution.

## Pipeline Tracing

To use the enhanced tracing tools:

```elixir
# Trace complete pipeline execution for the debug character
WandererNotifier.Debug.ProcessKillDebug.trace_pipeline_execution(0)

# Trace pipeline for a specific character by index
WandererNotifier.Debug.ProcessKillDebug.trace_pipeline_execution(1)

# Analyze pipeline with detailed function tracing
WandererNotifier.Debug.PipelineDebug.analyze_pipeline(123456789, 0)
```

These commands will output detailed function calls and transformations as the killmail moves through each phase of processing, showing:

1. Data transformation from raw ZKill data to KillmailData struct
2. All internal pipeline function calls with parameters
3. Enrichment operations and ESI API calls
4. Validation steps and results
5. Persistence operations
6. Notification determinations

This information is invaluable for identifying exactly where processing fails and why.
