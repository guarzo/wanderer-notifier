#!/usr/bin/env elixir

defmodule ModuleNameFixer do
  @moduledoc """
  Script to fix the inconsistent naming of WandererNotifier.Config.Timings[s+]
  module across the codebase.
  """

  @source_files "lib/**/*.{ex,exs}"
  @test_files "test/**/*.{ex,exs}"

  def run do
    IO.puts("Starting module name fixer...")

    # Get all files to process
    files = find_files()
    IO.puts("Found #{length(files)} files to scan")

    # Process each file
    results = process_files(files)

    # Summarize results
    {modified, errors} = Enum.split_with(results, fn {_file, status} -> status == :ok end)

    IO.puts("\nFix complete!")
    IO.puts("Modified files: #{length(modified)}")
    IO.puts("Error files: #{length(errors)}")

    if length(errors) > 0 do
      IO.puts("\nErrors:")
      Enum.each(errors, fn {file, {:error, reason}} ->
        IO.puts("  #{file}: #{inspect(reason)}")
      end)
    end

    if length(modified) > 0 do
      IO.puts("\nModified files:")
      Enum.each(modified, fn {file, :ok} ->
        IO.puts("  #{file}")
      end)
    end
  end

  defp find_files do
    source_files = Path.wildcard(@source_files)
    test_files = Path.wildcard(@test_files)
    source_files ++ test_files
  end

  defp process_files(files) do
    Enum.map(files, fn file ->
      {file, process_file(file)}
    end)
  end

  defp process_file(file) do
    IO.puts("Processing #{file}...")

    try do
      content = File.read!(file)

      # Fix module definitions
      new_content = Regex.replace(~r/defmodule WandererNotifier\.Config\.Timings+/, content,
                                 "defmodule WandererNotifier.Config.Timings")

      # Fix alias statements
      new_content = Regex.replace(~r/alias WandererNotifier\.Config\.Timings+/, new_content,
                                 "alias WandererNotifier.Config.Timings")

      # Fix alias statements with as:
      new_content = Regex.replace(~r/alias WandererNotifier\.Config\.Timings+, as: Timings+/, new_content,
                                "alias WandererNotifier.Config.Timings, as: Timings")

      # Fix test modules
      new_content = Regex.replace(~r/defmodule WandererNotifier\.Config\.Timings+Test/, new_content,
                                "defmodule WandererNotifier.Config.TimingsTest")

      # Only write if changes were made
      if content != new_content do
        IO.puts("  Changes detected, updating file...")
        File.write!(file, new_content)
        :ok
      else
        IO.puts("  No changes needed")
        :ok
      end
    rescue
      e -> {:error, Exception.message(e)}
    end
  end
end

# Run the fixer
ModuleNameFixer.run()
