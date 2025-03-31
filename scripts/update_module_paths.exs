#!/usr/bin/env elixir

# Script to update module paths in the codebase

defmodule ModulePathUpdater do
  def run do
    # Get all Elixir files in the project
    files = find_elixir_files()
    IO.puts("Found #{length(files)} Elixir files to process")

    # Process each file
    Enum.each(files, &process_file/1)
  end

  def find_elixir_files do
    {result, 0} = System.cmd("find", ["lib", "test", "-name", "*.ex", "-o", "-name", "*.exs"])
    String.split(result, "\n", trim: true)
  end

  def process_file(file) do
    content = File.read!(file)

    # Apply all replacements
    new_content = content
      |> replace_logger_module()
      |> replace_logger_behaviour()
      |> replace_license_service()
      |> replace_license_client()
      |> replace_startup_tracker()

    # Only write to the file if changes were made
    if new_content != content do
      IO.puts("Updating #{file}")
      File.write!(file, new_content)
    end
  end

  # Replace Logger module references
  def replace_logger_module(content) do
    content
    |> String.replace(
      ~r/alias WandererNotifier\.Core\.Logger(, as: (\w+))?/,
      "alias WandererNotifier.Logger.Logger\\1"
    )
    |> String.replace(
      "WandererNotifier.Core.Logger.",
      "WandererNotifier.Logger.Logger."
    )
  end

  # Replace Logger behaviour references
  def replace_logger_behaviour(content) do
    content
    |> String.replace(
      "WandererNotifier.Core.LoggerBehaviour",
      "WandererNotifier.Logger.Behaviour"
    )
  end

  # Replace License service references
  def replace_license_service(content) do
    content
    |> String.replace(
      ~r/alias WandererNotifier\.Core\.License(, as: (\w+))?/,
      "alias WandererNotifier.License.Service\\1"
    )
    |> String.replace(
      "WandererNotifier.Core.License",
      "WandererNotifier.License.Service"
    )
  end

  # Replace License client references
  def replace_license_client(content) do
    content
    |> String.replace(
      ~r/alias WandererNotifier\.LicenseManager\.Client(, as: (\w+))?/,
      "alias WandererNotifier.License.Client\\1"
    )
    |> String.replace(
      "WandererNotifier.LicenseManager.Client",
      "WandererNotifier.License.Client"
    )
  end

  # Fix the StartupTracker module path
  def replace_startup_tracker(content) do
    content
    |> String.replace(
      "defmodule WandererNotifier.Core.Logger.StartupTracker do",
      "defmodule WandererNotifier.Logger.StartupTracker do"
    )
    |> String.replace(
      "alias WandererNotifier.Core.Logger.StartupTracker",
      "alias WandererNotifier.Logger.StartupTracker"
    )
    |> String.replace(
      "WandererNotifier.Core.Logger.StartupTracker",
      "WandererNotifier.Logger.StartupTracker"
    )
  end
end

# Run the script
ModulePathUpdater.run()
