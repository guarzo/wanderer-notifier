#!/usr/bin/env elixir

# This script updates all Logger aliases in the project to point to the new module path

defmodule AliasUpdater do
  def run do
    # Get list of all files with Logger alias
    {files_output, 0} = System.cmd("grep", ["-r", "alias WandererNotifier.Logger", "--include=*.ex", "lib/"])
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

    # Get list of all files with StartupTracker references
    {startup_files, 0} = System.cmd("grep", ["-r", "WandererNotifier.Logger.StartupTracker", "--include=*.ex", "lib/"])
    startup_files = startup_files
                    |> String.split("\n")
                    |> Enum.filter(&(&1 != ""))
                    |> Enum.map(fn line ->
                      [file_path | _] = String.split(line, ":")
                      file_path
                    end)
                    |> Enum.uniq()

    # Update StartupTracker references
    Enum.each(startup_files, fn file ->
      update_startup_tracker(file)
    end)

    # Also fix the logger file itself which is in the Core path now
    startup_logger_file = "lib/wanderer_notifier/core/logger/startup_tracker.ex"
    if File.exists?(startup_logger_file) do
      update_self_reference(startup_logger_file)
    end

    # Also fix the batch logger file
    batch_logger_file = "lib/wanderer_notifier/core/logger/batch_logger.ex"
    if File.exists?(batch_logger_file) do
      update_self_reference(batch_logger_file)
    end
  end

  defp update_file(file) do
    IO.puts("Updating #{file}")
    content = File.read!(file)
    updated_content = String.replace(content,
                                    "alias WandererNotifier.Logger, as: AppLogger",
                                    "alias WandererNotifier.Core.Logger, as: AppLogger")
    File.write!(file, updated_content)
  end

  defp update_startup_tracker(file) do
    IO.puts("Updating StartupTracker reference in #{file}")
    content = File.read!(file)
    updated_content = String.replace(content,
                                    "WandererNotifier.Logger.StartupTracker",
                                    "WandererNotifier.Core.Logger.StartupTracker")
    File.write!(file, updated_content)
  end

  defp update_self_reference(file) do
    IO.puts("Updating self-reference in #{file}")
    content = File.read!(file)
    updated_content = String.replace(content,
                                    "alias WandererNotifier.Logger",
                                    "alias WandererNotifier.Core.Logger")
    File.write!(file, updated_content)
  end
end

AliasUpdater.run()
