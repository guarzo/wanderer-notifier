#!/usr/bin/env elixir

defmodule LoggingAnalyzer do
  @moduledoc """
  Analyzes the codebase for logging patterns to help with migration to standardized logging.

  Run with:
  ```
  mix run scripts/logging_migration/analyze_logging.exs
  ```

  Or from command line:
  ```
  elixir scripts/logging_migration/analyze_logging.exs
  ```
  """

  @lib_path "lib/wanderer_notifier"

  def run do
    IO.puts("\n====== Logging Analysis ======\n")

    # Ensure lib path exists
    unless File.dir?(@lib_path) do
      IO.puts("Error: Path #{@lib_path} not found")
      System.halt(1)
    end

    # Get all Elixir files
    files = find_elixir_files()
    IO.puts("Found #{length(files)} Elixir files to analyze\n")

    # Analyze each file
    results = analyze_files(files)

    # Print summary
    print_summary(results)

    # Write detailed results to file
    write_detailed_report(results)

    IO.puts("\nAnalysis complete. Detailed report written to scripts/logging_migration/logging_report.md")
  end

  defp find_elixir_files do
    @lib_path
    |> Path.join("**/*.ex")
    |> Path.wildcard()
    |> Enum.filter(&File.regular?/1)
  end

  defp analyze_files(files) do
    IO.puts("Analyzing files for logging patterns...")

    Enum.map(files, fn file ->
      content = File.read!(file)
      relative_path = Path.relative_to(file, "lib")

      # Analyze file
      %{
        file: relative_path,
        has_require_logger: has_require_logger?(content),
        has_import_logger: has_import_logger?(content),
        has_logger_alias: has_logger_alias?(content),
        direct_logger_calls: find_direct_logger_calls(content),
        app_logger_calls: find_app_logger_calls(content),
        detected_patterns: detect_logging_patterns(content),
        needs_migration: needs_migration?(content)
      }
    end)
  end

  defp has_require_logger?(content) do
    String.contains?(content, "require Logger")
  end

  defp has_import_logger?(content) do
    String.contains?(content, "import Logger")
  end

  defp has_logger_alias?(content) do
    String.contains?(content, "alias WandererNotifier.Logger.Logger")
  end

  defp find_direct_logger_calls(content) do
    # Match Logger.info, Logger.debug, etc.
    ~r/Logger\.(debug|info|warn|warning|error|critical)\(.*?\)/s
    |> Regex.scan(content)
    |> List.flatten()
  end

  defp find_app_logger_calls(content) do
    # Match AppLogger.info, AppLogger.api_info, etc.
    ~r/AppLogger\.\w+\(.*?\)/s
    |> Regex.scan(content)
    |> List.flatten()
  end

  defp detect_logging_patterns(content) do
    patterns = %{
      boolean_flags: detect_boolean_flags(content),
      batch_candidates: detect_batch_candidates(content),
      kv_candidates: detect_kv_candidates(content)
    }

    # Count total patterns
    total_patterns = Enum.reduce(patterns, 0, fn {_, list}, acc -> acc + length(list) end)

    Map.put(patterns, :total, total_patterns)
  end

  defp detect_boolean_flags(content) do
    # Look for boolean flag logging
    # Example: Logger.info("Flag enabled: #{enabled}")
    ~r/(Logger|AppLogger)\.\w+\(.*?(enabled|disabled|true|false).*?\)/s
    |> Regex.scan(content)
    |> List.flatten()
  end

  defp detect_batch_candidates(content) do
    # Look for similar repeated log patterns that could be batched
    # Example: AppLogger.debug("Cache hit", key: key)
    ~r/(Logger|AppLogger)\.\w+\("(Cache hit|Received|Processing).*?\)/s
    |> Regex.scan(content)
    |> List.flatten()
  end

  defp detect_kv_candidates(content) do
    # Look for logging patterns that could use key-value format
    # Example: AppLogger.info("Config value: #{value}")
    ~r/(Logger|AppLogger)\.\w+\(".*?:[^"]*?#\{.*?\}.*?\)/s
    |> Regex.scan(content)
    |> List.flatten()
  end

  defp needs_migration?(content) do
    # File needs migration if it:
    # 1. Has direct Logger calls
    # 2. Uses AppLogger without proper alias
    # 3. Has potential KV or batch candidates
    direct_calls = find_direct_logger_calls(content)

    has_app_logger = String.contains?(content, "AppLogger.")
    has_proper_alias = String.contains?(content, "alias WandererNotifier.Logger.Logger, as: AppLogger")

    patterns = detect_logging_patterns(content)

    has_bad_patterns = patterns.total > 0

    (length(direct_calls) > 0) || (has_app_logger && !has_proper_alias) || has_bad_patterns
  end

  defp print_summary(results) do
    file_count = length(results)
    migration_needed_count = Enum.count(results, & &1.needs_migration)
    direct_logger_count = Enum.reduce(results, 0, fn r, acc -> acc + length(r.direct_logger_calls) end)
    app_logger_count = Enum.reduce(results, 0, fn r, acc -> acc + length(r.app_logger_calls) end)

    require_logger_count = Enum.count(results, & &1.has_require_logger)
    logger_alias_count = Enum.count(results, & &1.has_logger_alias)

    # Count pattern candidates
    boolean_flags_count = Enum.reduce(results, 0, fn r, acc ->
      acc + length(r.detected_patterns.boolean_flags)
    end)

    batch_candidates_count = Enum.reduce(results, 0, fn r, acc ->
      acc + length(r.detected_patterns.batch_candidates)
    end)

    kv_candidates_count = Enum.reduce(results, 0, fn r, acc ->
      acc + length(r.detected_patterns.kv_candidates)
    end)

    IO.puts("\n====== Summary ======")
    IO.puts("Total files analyzed: #{file_count}")
    IO.puts("Files needing migration: #{migration_needed_count}")
    IO.puts("Files with 'require Logger': #{require_logger_count}")
    IO.puts("Files with Logger alias: #{logger_alias_count}")
    IO.puts("\nTotal direct Logger calls: #{direct_logger_count}")
    IO.puts("Total AppLogger calls: #{app_logger_count}")
    IO.puts("\nDetected migration opportunities:")
    IO.puts("  - Boolean flag logging candidates: #{boolean_flags_count}")
    IO.puts("  - Batch logging candidates: #{batch_candidates_count}")
    IO.puts("  - Key-value logging candidates: #{kv_candidates_count}")

    # List top files needing attention
    IO.puts("\nTop files needing attention:")
    results
    |> Enum.filter(& &1.needs_migration)
    |> Enum.sort_by(fn r ->
      length(r.direct_logger_calls) +
      (if r.has_logger_alias, do: 0, else: 10) +
      r.detected_patterns.total
    end, :desc)
    |> Enum.take(10)
    |> Enum.each(fn r ->
      IO.puts("  - #{r.file}")
      IO.puts("      Direct Logger calls: #{length(r.direct_logger_calls)}")
      IO.puts("      Has proper alias: #{r.has_logger_alias}")
      IO.puts("      Pattern opportunities: #{r.detected_patterns.total}")
    end)
  end

  defp write_detailed_report(results) do
    report_path = "scripts/logging_migration/logging_report.md"

    # Create report content
    report = """
    # Logging Migration Analysis Report

    Generated on: #{DateTime.utc_now() |> DateTime.to_string()}

    ## Overview

    Total files analyzed: #{length(results)}
    Files needing migration: #{Enum.count(results, & &1.needs_migration)}

    ## Direct Logger Usage

    Files with direct Logger calls: #{Enum.count(results, fn r -> length(r.direct_logger_calls) > 0 end)}

    """

    # Add files with direct Logger calls
    report = report <> "### Files with Direct Logger Calls\n\n"

    direct_logger_files = results
    |> Enum.filter(fn r -> length(r.direct_logger_calls) > 0 end)
    |> Enum.sort_by(fn r -> length(r.direct_logger_calls) end, :desc)

    report = report <> "| File | Direct Logger Calls |\n"
    report = report <> "| ---- | ------------------ |\n"

    report = report <> Enum.map_join(direct_logger_files, "\n", fn r ->
      "| #{r.file} | #{length(r.direct_logger_calls)} |"
    end)

    # Add files missing proper alias
    report = report <> "\n\n## Missing Proper Alias\n\n"

    missing_alias_files = results
    |> Enum.filter(fn r ->
      String.contains?(File.read!("lib/#{r.file}"), "AppLogger.") && !r.has_logger_alias
    end)

    report = report <> "| File |\n"
    report = report <> "| ---- |\n"

    report = report <> Enum.map_join(missing_alias_files, "\n", fn r ->
      "| #{r.file} |"
    end)

    # Add pattern migration opportunities
    report = report <> "\n\n## Migration Opportunities\n\n"

    # Boolean flags
    report = report <> "### Boolean Flag Candidates\n\n"

    boolean_files = results
    |> Enum.filter(fn r -> length(r.detected_patterns.boolean_flags) > 0 end)
    |> Enum.sort_by(fn r -> length(r.detected_patterns.boolean_flags) end, :desc)
    |> Enum.take(20)

    report = report <> "| File | Count |\n"
    report = report <> "| ---- | ----- |\n"

    report = report <> Enum.map_join(boolean_files, "\n", fn r ->
      "| #{r.file} | #{length(r.detected_patterns.boolean_flags)} |"
    end)

    # Batch candidates
    report = report <> "\n\n### Batch Logging Candidates\n\n"

    batch_files = results
    |> Enum.filter(fn r -> length(r.detected_patterns.batch_candidates) > 0 end)
    |> Enum.sort_by(fn r -> length(r.detected_patterns.batch_candidates) end, :desc)
    |> Enum.take(20)

    report = report <> "| File | Count |\n"
    report = report <> "| ---- | ----- |\n"

    report = report <> Enum.map_join(batch_files, "\n", fn r ->
      "| #{r.file} | #{length(r.detected_patterns.batch_candidates)} |"
    end)

    # KV candidates
    report = report <> "\n\n### Key-Value Logging Candidates\n\n"

    kv_files = results
    |> Enum.filter(fn r -> length(r.detected_patterns.kv_candidates) > 0 end)
    |> Enum.sort_by(fn r -> length(r.detected_patterns.kv_candidates) end, :desc)
    |> Enum.take(20)

    report = report <> "| File | Count |\n"
    report = report <> "| ---- | ----- |\n"

    report = report <> Enum.map_join(kv_files, "\n", fn r ->
      "| #{r.file} | #{length(r.detected_patterns.kv_candidates)} |"
    end)

    # Write report to file
    File.write!(report_path, report)
  end
end

LoggingAnalyzer.run()
