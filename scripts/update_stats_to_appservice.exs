#!/usr/bin/env elixir

# Script to update all Stats references to ApplicationService

defmodule UpdateStatsReferences do
  @files_to_update [
    # Application layer files
    "lib/wanderer_notifier/schedulers/base_scheduler.ex",
    "lib/wanderer_notifier/application/services/application/api.ex",
    "lib/wanderer_notifier/domains/killmail/websocket_client.ex",
    "lib/wanderer_notifier/domains/killmail/pipeline_worker.ex",
    "lib/wanderer_notifier/domains/notifications/notification_service.ex",
    "lib/wanderer_notifier/domains/notifications/discord/notifier.ex",
    "lib/wanderer_notifier/map/initializer.ex",
    "lib/wanderer_notifier/domains/notifications/formatters/status.ex",
    "lib/wanderer_notifier/shared/telemetry/telemetry.ex",
    "lib/wanderer_notifier/api/controllers/system_info.ex",
    
    # Test files
    "test/wanderer_notifier/core/application/service_test.exs"
  ]

  @replacements [
    # Alias updates
    {"alias WandererNotifier.Application.Services.Stats", "alias WandererNotifier.Application.Services.ApplicationService"},
    {"alias WandererNotifier.Core.Stats", "alias WandererNotifier.Application.Services.ApplicationService"},
    
    # Function replacements - Stats to ApplicationService
    {"Stats.get_stats()", "ApplicationService.get_stats()"},
    {"Stats.increment(", "ApplicationService.increment_metric("},
    {"Stats.track_killmail_received()", "ApplicationService.increment_metric(:killmail_received)"},
    {"Stats.update_websocket_stats(", "ApplicationService.update_health(:websocket, "},
    {"Stats.set_tracked_count(", "ApplicationService.set_tracked_count("},
    {"Stats.update_last_activity()", "ApplicationService.update_health(:redisq, %{last_message: DateTime.utc_now()})"},
    {"Stats.track_notification_sent()", "ApplicationService.increment_metric(:notification_sent)"},
    
    # Full module path replacements
    {"WandererNotifier.Application.Services.Stats.", "WandererNotifier.Application.Services.ApplicationService."},
    {"WandererNotifier.Core.Stats.", "WandererNotifier.Application.Services.ApplicationService."},
  ]

  def run do
    IO.puts("Updating Stats references to ApplicationService...\n")
    
    Enum.each(@files_to_update, fn file_path ->
      full_path = Path.join(File.cwd!(), file_path)
      
      if File.exists?(full_path) do
        IO.puts("Processing: #{file_path}")
        content = File.read!(full_path)
        updated_content = apply_replacements(content)
        
        if content != updated_content do
          File.write!(full_path, updated_content)
          IO.puts("  ✓ Updated")
        else
          IO.puts("  - No changes needed")
        end
      else
        IO.puts("  ✗ File not found: #{file_path}")
      end
    end)
    
    IO.puts("\n✅ Update complete!")
  end

  defp apply_replacements(content) do
    Enum.reduce(@replacements, content, fn {pattern, replacement}, acc ->
      String.replace(acc, pattern, replacement)
    end)
  end
end

UpdateStatsReferences.run()