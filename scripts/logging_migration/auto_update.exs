#!/usr/bin/env elixir

defmodule LoggingAutoUpdater do
  @moduledoc """
  Automatically performs basic updates to standardize logging in the codebase.

  This script can:
  1. Fix module declarations by adding the proper alias
  2. Replace direct Logger calls with AppLogger equivalents
  3. Update simple log patterns

  Run with:
  ```
  mix run scripts/logging_migration/auto_update.exs [--dry-run] [file_path]
  ```

  Or from command line:
  ```
  elixir scripts/logging_migration/auto_update.exs [--dry-run] [file_path]
  ```

  Options:
  --dry-run: Show changes without applying them
  file_path: Optional specific file path to update
  """

  @lib_path "lib/wanderer_notifier"

  def run(args \\ []) do
    # Parse arguments
    {opts, files} = parse_args(args)
    dry_run = Keyword.get(opts, :dry_run, false)

    IO.puts("\n====== Logging Auto-Update ======\n")
    IO.puts("Mode: #{if dry_run, do: "Dry run (no changes will be applied)", else: "Live run"}")

    # Get target files
    target_files = get_target_files(files)
    IO.puts("Found #{length(target_files)} files to process\n")

    # Process each file
    results = Enum.map(target_files, fn file ->
      process_file(file, dry_run)
    end)

    # Print summary
    print_summary(results, dry_run)
  end

  defp parse_args(args) do
    {opts, files, _} = OptionParser.parse(args, strict: [dry_run: :boolean])
    {opts, files}
  end

  defp get_target_files([]) do
    # No specific files provided, use all Elixir files
    @lib_path
    |> Path.join("**/*.ex")
    |> Path.wildcard()
    |> Enum.filter(&File.regular?/1)
  end

  defp get_target_files(files) do
    # Use provided files, resolving full paths if needed
    Enum.map(files, fn file ->
      if String.starts_with?(file, @lib_path) do
        file
      else
        Path.join(@lib_path, file)
      end
    end)
    |> Enum.filter(&File.exists?/1)
  end

  defp process_file(file, dry_run) do
    IO.puts("Processing #{file}...")
    content = File.read!(file)

    # Apply transformations
    new_content = content
    |> fix_module_declaration()
    |> convert_direct_logger_calls()
    |> update_simple_patterns()

    # Check if content changed
    changed = content != new_content

    if changed do
      if dry_run do
        IO.puts("  Would update file (changes detected)")
      else
        IO.puts("  Updating file...")
        File.write!(file, new_content)
        IO.puts("  File updated successfully")
      end
    else
      IO.puts("  No changes needed")
    end

    %{
      file: file,
      changed: changed,
      original_content: content,
      new_content: new_content
    }
  end

  defp fix_module_declaration(content) do
    # Skip if already has the proper alias
    if String.contains?(content, "alias WandererNotifier.Logger.Logger, as: AppLogger") do
      content
    else
      # Check if the file uses AppLogger
      if String.contains?(content, "AppLogger.") do
        # Find the module declaration line
        module_regex = ~r/defmodule .*? do/

        case Regex.run(module_regex, content) do
          [module_line] ->
            # Add the alias after the module declaration
            String.replace(content, module_line,
              "#{module_line}\n  alias WandererNotifier.Logger.Logger, as: AppLogger")
          _ ->
            content
        end
      else
        content
      end
    end
  end

  defp convert_direct_logger_calls(content) do
    # Replace direct Logger calls with AppLogger equivalents
    content
    |> String.replace(~r/Logger\.debug\((.*?)\)/s, "AppLogger.debug(\\1)")
    |> String.replace(~r/Logger\.info\((.*?)\)/s, "AppLogger.info(\\1)")
    |> String.replace(~r/Logger\.warn\((.*?)\)/s, "AppLogger.warn(\\1)")
    |> String.replace(~r/Logger\.warning\((.*?)\)/s, "AppLogger.warn(\\1)")
    |> String.replace(~r/Logger\.error\((.*?)\)/s, "AppLogger.error(\\1)")
  end

  defp update_simple_patterns(content) do
    # Update simple patterns
    content
    # API-related patterns
    |> update_api_patterns()
    # WebSocket-related patterns
    |> update_websocket_patterns()
    # Cache-related patterns
    |> update_cache_patterns()
    # Processor-related patterns
    |> update_processor_patterns()
  end

  defp update_api_patterns(content) do
    content
    |> String.replace(
      ~r/AppLogger\.(debug|info|warn|error)\(([\"'])API (.*?)\2(.*?)\)/s,
      "AppLogger.api_\\1(\\2\\3\\2\\4)"
    )
    |> String.replace(
      ~r/AppLogger\.(debug|info|warn|error)\(([\"'])Making (API |HTTP )request(.*?)\2(.*?)\)/s,
      "AppLogger.api_\\1(\\2Making request\\4\\2\\5)"
    )
    |> String.replace(
      ~r/AppLogger\.(debug|info|warn|error)\(([\"'])Received (API |HTTP )response(.*?)\2(.*?)\)/s,
      "AppLogger.api_\\1(\\2Received response\\4\\2\\5)"
    )
  end

  defp update_websocket_patterns(content) do
    content
    |> String.replace(
      ~r/AppLogger\.(debug|info|warn|error)\(([\"'])WebSocket (.*?)\2(.*?)\)/si,
      "AppLogger.websocket_\\1(\\2\\3\\2\\4)"
    )
    |> String.replace(
      ~r/AppLogger\.(debug|info|warn|error)\(([\"'])Websocket (.*?)\2(.*?)\)/si,
      "AppLogger.websocket_\\1(\\2\\3\\2\\4)"
    )
    |> String.replace(
      ~r/AppLogger\.(debug|info|warn|error)\(([\"'])WS (.*?)\2(.*?)\)/si,
      "AppLogger.websocket_\\1(\\2\\3\\2\\4)"
    )
  end

  defp update_cache_patterns(content) do
    content
    |> String.replace(
      ~r/AppLogger\.(debug|info|warn|error)\(([\"'])Cache (.*?)\2(.*?)\)/s,
      "AppLogger.cache_\\1(\\2\\3\\2\\4)"
    )
  end

  defp update_processor_patterns(content) do
    content
    |> String.replace(
      ~r/AppLogger\.(debug|info|warn|error)\(([\"'])Processing (.*?)\2(.*?)\)/s,
      "AppLogger.processor_\\1(\\2\\3\\2\\4)"
    )
  end

  defp print_summary(results, dry_run) do
    changed_count = Enum.count(results, & &1.changed)

    IO.puts("\n====== Summary ======")
    IO.puts("Total files processed: #{length(results)}")
    IO.puts("Files with changes: #{changed_count}")

    if changed_count > 0 do
      IO.puts("\nChanged files:")
      Enum.filter(results, & &1.changed)
      |> Enum.each(fn r ->
        IO.puts("  - #{r.file}")
      end)

      if dry_run do
        IO.puts("\nRun without --dry-run to apply these changes")
      end
    end
  end
end

LoggingAutoUpdater.run(System.argv())
