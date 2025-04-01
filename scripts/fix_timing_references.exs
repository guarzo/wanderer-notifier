#!/usr/bin/env elixir

defmodule TimingMigrationHelper do
  @moduledoc """
  Script to help migrate references from WandererNotifier.Config.Timing to
  WandererNotifier.Config.Timings after consolidation.
  """

  @source_files "lib/**/*.{ex,exs}"
  @test_files "test/**/*.{ex,exs}"
  @method_mapping %{
    "get_systems_cache_ttl" => "systems_cache_ttl",
    "get_systems_update_interval" => "systems_update_interval",
    "get_chart_service_hour" => "chart_hour",
    "get_chart_service_minute" => "chart_minute",
    "get_persistence_config" => "persistence_config",
    "get_maintenance_interval" => "maintenance_interval",
    "get_character_update_interval" => "character_update_interval",
    "get_cache_check_interval" => "cache_check_interval",
    "get_cache_sync_interval" => "cache_sync_interval",
    "get_cache_cleanup_interval" => "cache_cleanup_interval",
    "get_forced_kill_interval" => "forced_kill_interval",
    "get_websocket_heartbeat_interval" => "websocket_heartbeat_interval",
    "get_reconnect_delay" => "reconnect_delay",
    "get_license_refresh_interval" => "license_refresh_interval",
    "get_activity_chart_interval" => "activity_chart_interval",
    "get_character_update_scheduler_interval" => "character_update_scheduler_interval",
    "get_system_update_scheduler_interval" => "system_update_scheduler_interval",
    "get_timing_config" => "config"
  }

  def run do
    IO.puts("Starting migration from Timing to Timings...")

    # Get all files to process
    files = find_files()
    IO.puts("Found #{length(files)} files to scan")

    # Process each file
    results = process_files(files)

    # Summarize results
    {modified, errors} = Enum.split_with(results, fn {_file, status} -> status == :ok end)

    IO.puts("\nMigration complete!")
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

      # Replace module name
      new_content = String.replace(content,
        "WandererNotifier.Config.Timing",
        "WandererNotifier.Config.Timings")

      # Replace module alias
      new_content = String.replace(new_content,
        "alias WandererNotifier.Config.Timing",
        "alias WandererNotifier.Config.Timings")

      # Replace shortened alias
      new_content = String.replace(new_content,
        "alias WandererNotifier.Config.Timing, as: Timing",
        "alias WandererNotifier.Config.Timings, as: Timings")

      # Replace method names
      new_content = replace_method_names(new_content)

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

  defp replace_method_names(content) do
    Enum.reduce(@method_mapping, content, fn {old_name, new_name}, acc ->
      pattern = "Timing.#{old_name}("
      replacement = "Timings.#{new_name}("
      String.replace(acc, pattern, replacement)
    end)
  end
end

# Run the migration
TimingMigrationHelper.run()
