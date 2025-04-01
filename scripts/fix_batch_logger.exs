#!/usr/bin/env elixir

# This script updates all BatchLogger references in the project to point to the new module path

defmodule BatchLoggerUpdater do
  def run do
    # Get list of all files with BatchLogger references
    {files_output, 0} = System.cmd("grep", ["-r", "BatchLogger", "--include=*.ex", "lib/"])
    files = files_output
            |> String.split("\n")
            |> Enum.filter(&(&1 != ""))
            |> Enum.map(fn line ->
              [file_path | _] = String.split(line, ":")
              file_path
            end)
            |> Enum.uniq()

    # Update each file
    Enum.each(files, fn file ->
      update_file(file)
    end)
  end

  defp update_file(file) do
    IO.puts("Updating #{file}")
    content = File.read!(file)

    # Update both the alias and direct references
    updated_content = content
                      |> String.replace(
                          "alias WandererNotifier.Logger.BatchLogger",
                          "alias WandererNotifier.Core.Logger.BatchLogger")
                      |> String.replace(
                          "WandererNotifier.Logger.BatchLogger",
                          "WandererNotifier.Core.Logger.BatchLogger")

    # Also handle AppLogger.BatchLogger format
    updated_content = String.replace(updated_content,
                          "AppLogger.BatchLogger",
                          "WandererNotifier.Core.Logger.BatchLogger")

    File.write!(file, updated_content)
  end
end

BatchLoggerUpdater.run()
