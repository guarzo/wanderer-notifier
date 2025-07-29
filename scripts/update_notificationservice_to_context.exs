#!/usr/bin/env elixir

# Script to update NotificationService references to NotificationContext

defmodule UpdateNotificationServiceReferences do
  @files_to_update [
    # Domain files
    "lib/wanderer_notifier/domains/killmail/pipeline.ex",
    "lib/wanderer_notifier/map/event_processor.ex",
    "lib/wanderer_notifier/domains/tracking/handlers/system_handler.ex",
    "lib/wanderer_notifier/domains/tracking/handlers/character_handler.ex",
    "lib/wanderer_notifier/domains/tracking/map_tracking_client.ex"
  ]

  def run do
    IO.puts("Updating NotificationService references to NotificationContext...\n")
    
    Enum.each(@files_to_update, fn file_path ->
      full_path = Path.join(File.cwd!(), file_path)
      
      if File.exists?(full_path) do
        IO.puts("Processing: #{file_path}")
        content = File.read!(full_path)
        
        # Apply specific updates based on file
        updated_content = case file_path do
          "lib/wanderer_notifier/domains/killmail/pipeline.ex" ->
            update_pipeline(content)
          
          "lib/wanderer_notifier/map/event_processor.ex" ->
            update_event_processor(content)
            
          "lib/wanderer_notifier/domains/tracking/handlers/system_handler.ex" ->
            update_system_handler(content)
            
          "lib/wanderer_notifier/domains/tracking/handlers/character_handler.ex" ->
            update_character_handler(content)
            
          "lib/wanderer_notifier/domains/tracking/map_tracking_client.ex" ->
            update_map_tracking_client(content)
            
          _ ->
            content
        end
        
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
  
  defp update_pipeline(content) do
    content
    |> String.replace(
      "WandererNotifier.Application.Services.NotificationService.notify_kill(killmail)",
      "case WandererNotifier.Contexts.NotificationContext.send_kill_notification(killmail) do\n        {:ok, _} -> :ok\n        {:error, reason} -> {:error, reason}\n      end"
    )
  end
  
  defp update_event_processor(content) do
    # For rally point, we need to keep using the old NotificationService
    # or implement it in NotificationContext
    content
  end
  
  defp update_system_handler(content) do
    content
    |> String.replace(
      "WandererNotifier.Application.Services.NotificationService.notify_system(system)",
      "case WandererNotifier.Contexts.NotificationContext.send_system_notification(system) do\n          {:ok, _} -> :ok\n          {:error, reason} -> {:error, reason}\n        end"
    )
  end
  
  defp update_character_handler(content) do
    content
    |> String.replace(
      "WandererNotifier.Application.Services.NotificationService.notify_character(map_character)",
      "case WandererNotifier.Contexts.NotificationContext.send_character_notification(map_character) do\n        {:ok, _} -> :ok\n        {:error, reason} -> {:error, reason}\n      end"
    )
  end
  
  defp update_map_tracking_client(content) do
    content
    |> String.replace(
      "alias WandererNotifier.Application.Services.NotificationService",
      "alias WandererNotifier.Contexts.NotificationContext"
    )
    # Note: This file doesn't seem to actually use NotificationService based on grep
  end
end

UpdateNotificationServiceReferences.run()