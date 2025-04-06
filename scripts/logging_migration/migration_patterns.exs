#!/usr/bin/env elixir

defmodule LoggingMigrationPatterns do
  @moduledoc """
  Generates examples of common logging migration patterns to help standardize the codebase.
  This script outputs markdown documentation of before/after examples.

  Run with:
  ```
  mix run scripts/logging_migration/migration_patterns.exs
  ```

  Or from command line:
  ```
  elixir scripts/logging_migration/migration_patterns.exs
  ```
  """

  def run do
    IO.puts("\n====== Generating Logging Migration Patterns ======\n")

    # Generate patterns documentation
    patterns_md = generate_patterns_doc()

    # Write to file
    File.write!("scripts/logging_migration/migration_patterns.md", patterns_md)

    IO.puts("Migration patterns documentation generated: scripts/logging_migration/migration_patterns.md")
  end

  defp generate_patterns_doc do
    """
    # Logging Migration Patterns Guide

    This guide provides examples of how to migrate existing logging code to the new standardized patterns.

    ## Basic Patterns

    ### Direct Logger Call Replacement

    Replace direct calls to `Logger` with the equivalent `AppLogger` function.

    ```elixir
    # Before
    Logger.debug("Message")
    Logger.info("Message")
    Logger.warning("Message")
    Logger.error("Message")

    # After
    AppLogger.debug("Message")
    AppLogger.info("Message")
    AppLogger.warn("Message")
    AppLogger.error("Message")
    ```

    ### Category-Specific Logging

    Use category-specific logging functions for better organization.

    ```elixir
    # Before
    AppLogger.debug("API request received")
    AppLogger.info("Cache hit")
    AppLogger.warn("Websocket disconnected")

    # After
    AppLogger.api_debug("Request received")
    AppLogger.cache_info("Cache hit")
    AppLogger.websocket_warn("Disconnected")
    ```

    ### Required Module Updates

    Ensure proper module requires and aliases.

    ```elixir
    # Before
    require Logger

    def function do
      Logger.info("Message")
    end

    # After
    alias WandererNotifier.Logger.Logger, as: AppLogger

    def function do
      AppLogger.info("Message")
    end
    ```

    ## Advanced Patterns

    ### Key-Value Logging for Boolean Flags and Settings

    Use key-value logging for configuration values and boolean flags.

    ```elixir
    # Before
    AppLogger.info("Websocket enabled: \#{websocket_enabled}")
    Logger.info("Status messages disabled: \#{status_disabled}")
    AppLogger.debug("Cache TTL is set to \#{ttl_seconds} seconds")

    # After
    AppLogger.config_kv("Websocket enabled", websocket_enabled)
    AppLogger.startup_kv("Status messages disabled", status_disabled)
    AppLogger.cache_kv("Cache TTL", ttl_seconds)
    ```

    ### Batch Logging for High-Volume Events

    Use batch logging for high-volume repeating events.

    ```elixir
    # Before - Multiple individual logs
    AppLogger.debug("Cache hit", key: "user:123")
    AppLogger.debug("Cache hit", key: "item:456")
    AppLogger.debug("Cache hit", key: "settings:789")

    # After - Initialize batch logger in application startup
    AppLogger.init_batch_logger()

    # Then use count_batch_event for all occurrences
    AppLogger.count_batch_event(:cache_hit, %{key_pattern: "user:"})
    AppLogger.count_batch_event(:cache_hit, %{key_pattern: "item:"})
    AppLogger.count_batch_event(:cache_hit, %{key_pattern: "settings:"})

    # Flush when needed or let automatic flushing handle it
    # AppLogger.flush_batch_logs()
    ```

    ### Startup Phase Tracking

    Use structured startup tracking for application initialization.

    ```elixir
    # Before
    AppLogger.info("Starting application")
    # ... initialization code ...
    AppLogger.info("Loading dependencies")
    # ... load dependencies ...
    AppLogger.info("Starting services")
    # ... start services ...
    AppLogger.info("Startup complete in \#{duration}ms")

    # After
    AppLogger.init_startup_tracker()

    AppLogger.begin_startup_phase(:initialization, "Starting application")
    # ... initialization code ...

    AppLogger.begin_startup_phase(:dependencies, "Loading dependencies")
    # ... load dependencies ...

    AppLogger.begin_startup_phase(:services, "Starting services")
    # ... start services ...

    AppLogger.complete_startup()
    ```

    ## Category-Specific Examples

    ### API Logging

    ```elixir
    # Before
    Logger.debug("Making API request to \#{url}")
    # ... request code ...
    Logger.info("Received API response: status=\#{status}")

    # After
    AppLogger.api_debug("Making request", url: url, method: method)
    # ... request code ...
    AppLogger.api_info("Received response", status: status, duration_ms: duration)
    ```

    ### WebSocket Logging

    ```elixir
    # Before
    Logger.info("Websocket connected")
    # ... websocket code ...
    Logger.error("Websocket error: \#{error}")

    # After
    AppLogger.websocket_info("Connected", pid: inspect(pid))
    # ... websocket code ...
    AppLogger.websocket_error("Connection error", error: inspect(error))
    ```

    ### Cache Logging

    ```elixir
    # Before
    Logger.debug("Cache hit for key \#{key}")
    Logger.debug("Cache miss for key \#{key}")

    # After
    AppLogger.cache_debug("Cache hit", key: key, ttl_remaining_s: ttl)
    AppLogger.cache_debug("Cache miss", key: key)
    ```

    ### Error Logging

    ```elixir
    # Before
    Logger.error("Error processing item: \#{inspect(error)}")

    # After
    AppLogger.error("Failed to process item",
      error: Exception.message(error),
      stacktrace: Exception.format_stacktrace(__STACKTRACE__),
      item_id: id
    )
    ```

    ## Metadata Guidelines

    Always include relevant metadata as structured data rather than interpolating into strings:

    ```elixir
    # Bad
    AppLogger.info("Process completed in \#{duration_ms}ms with \#{items_count} items")

    # Good
    AppLogger.info("Process completed", duration_ms: duration_ms, items_count: items_count)
    ```

    ### Common Metadata Fields

    Use these standard metadata fields when applicable:

    - `duration_ms`: For timing information
    - `count`: For quantity information
    - `error`: For error messages
    - `reason`: For explaining why something happened
    - `status`: For status codes
    - Entity IDs: `system_id`, `character_id`, `kill_id`, etc.
    """
  end
end

LoggingMigrationPatterns.run()
