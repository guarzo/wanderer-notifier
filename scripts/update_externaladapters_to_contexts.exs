#!/usr/bin/env elixir

# Script to update ExternalAdapters references to ApiContext

defmodule UpdateExternalAdaptersReferences do
  @files_to_update [
    # Domain files
    "lib/wanderer_notifier/domains/killmail/websocket_client.ex",
    "lib/wanderer_notifier/domains/killmail/fallback_handler.ex",
    
    # Scripts
    "scripts/websocket_debug.exs",
    "scripts/check_killmail_flow.exs"
  ]

  def run do
    IO.puts("Updating ExternalAdapters references to ApiContext...\n")
    
    Enum.each(@files_to_update, fn file_path ->
      full_path = Path.join(File.cwd!(), file_path)
      
      if File.exists?(full_path) do
        IO.puts("Processing: #{file_path}")
        content = File.read!(full_path)
        
        updated_content = content
        |> String.replace(
          "alias WandererNotifier.Contexts.ExternalAdapters",
          "alias WandererNotifier.Contexts.ApiContext"
        )
        |> String.replace(
          "ExternalAdapters.get_tracked_systems()",
          "ApiContext.get_tracked_systems()"
        )
        |> String.replace(
          "ExternalAdapters.get_tracked_characters()",
          "ApiContext.get_tracked_characters()"
        )
        |> String.replace(
          "WandererNotifier.Contexts.ExternalAdapters.get_tracked_systems()",
          "WandererNotifier.Contexts.ApiContext.get_tracked_systems()"
        )
        |> String.replace(
          "WandererNotifier.Contexts.ExternalAdapters.get_tracked_characters()",
          "WandererNotifier.Contexts.ApiContext.get_tracked_characters()"
        )
        # Handle the dynamic adapter case in fallback_handler
        |> update_dynamic_adapter()
        
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
  
  defp update_dynamic_adapter(content) do
    # For fallback_handler.ex, we need to handle the dynamic adapter
    if String.contains?(content, "adapter = adapter || ExternalAdapters") do
      content
      |> String.replace(
        "adapter = adapter || ExternalAdapters",
        "adapter = adapter || ApiContext"
      )
    else
      content
    end
  end
end

UpdateExternalAdaptersReferences.run()