#!/usr/bin/env elixir

# Script to find all references to the Killmail module in the codebase
#
# Usage:
#   mix run scripts/find_killmail_references.exs
#
# This script will:
# 1. Search for all references to WandererNotifier.Killmail
# 2. Search for all references to alias Killmail
# 3. Group by file type and purpose
# 4. Output a report of all references found

defmodule KillmailRefFinder do
  @base_path "lib/"
  @test_path "test/"
  @include_extensions [".ex", ".exs"]

  def run do
    IO.puts("Finding references to the Killmail module...\n")

    IO.puts("===== Source Code =====")
    find_references(@base_path)
    |> process_references("Source")

    IO.puts("\n===== Test Code =====")
    find_references(@test_path)
    |> process_references("Test")

    IO.puts("\nAnalysis complete. This list can be used to prioritize updates for Phase 5.")
  end

  defp find_references(path) do
    Path.wildcard("#{path}/**/*")
    |> Enum.filter(fn file ->
      ext = Path.extname(file)
      Enum.member?(@include_extensions, ext)
    end)
    |> Enum.map(fn file ->
      content = File.read!(file)
      references = find_killmail_references(content)
      {file, references}
    end)
    |> Enum.filter(fn {_file, references} -> references != [] end)
  end

  defp find_killmail_references(content) do
    # Match patterns that might be references to the Killmail module
    patterns = [
      ~r/WandererNotifier\.Killmail/,          # Full module name
      ~r/alias WandererNotifier\.Killmail/,    # Alias declaration
      ~r/alias.*Killmail/,                     # Alias including multiple modules
      ~r/import WandererNotifier\.Killmail/,   # Import declaration
      ~r/Killmail\.[a-z_]+/                    # Direct function calls
    ]

    # Find all matches for each pattern
    Enum.flat_map(patterns, fn pattern ->
      Regex.scan(pattern, content)
      |> Enum.map(fn [match | _] -> match end)
    end)
    |> Enum.uniq()
  end

  defp process_references(files_with_references, type) do
    if Enum.empty?(files_with_references) do
      IO.puts("No references found in #{type} code.")
    else
      # Group by directory/category
      grouped = Enum.group_by(files_with_references, fn {file, _} ->
        Path.dirname(file) |> String.replace_prefix(@base_path, "") |> String.replace_prefix(@test_path, "")
      end)

      # Print grouped references
      Enum.each(grouped, fn {group, files} ->
        IO.puts("\n#{group}:")
        Enum.each(files, fn {file, references} ->
          IO.puts("  #{Path.basename(file)}")
          Enum.each(references, fn ref ->
            IO.puts("    - #{ref}")
          end)
        end)
      end)

      # Print summary
      total_files = Enum.count(files_with_references)
      total_refs = Enum.reduce(files_with_references, 0, fn {_, refs}, acc -> acc + Enum.count(refs) end)
      IO.puts("\n#{type} summary: #{total_refs} references in #{total_files} files")
    end
  end
end

KillmailRefFinder.run()
