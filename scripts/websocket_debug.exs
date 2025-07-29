#!/usr/bin/env elixir

# WebSocket debug script for examining heartbeat and connection behavior
# Usage: elixir scripts/websocket_debug.exs

defmodule WebSocketDebug do
  def start do
    IO.puts("=== WebSocket Debug Analysis ===")
    IO.puts("")
    
    analyze_websocket_state()
    analyze_heartbeat_config()
    analyze_subscription_data()
    analyze_connection_url()
    
    IO.puts("")
    IO.puts("=== Recommendations ===")
    print_recommendations()
  end
  
  defp analyze_websocket_state do
    IO.puts("📡 WebSocket Client State:")
    
    websocket_pid = Process.whereis(WandererNotifier.Killmail.WebSocketClient)
    
    if websocket_pid do
      IO.puts("  Status: ✅ Running (PID: #{inspect(websocket_pid)})")
      
      try do
        info = Process.info(websocket_pid)
        IO.puts("  Memory: #{div(info[:memory] || 0, 1024)} KB")
        IO.puts("  Message Queue: #{info[:message_queue_len] || 0}")
        IO.puts("  Heap Size: #{info[:heap_size] || 0}")
        
        # Try to get state (this might not work depending on WebSockex implementation)
        IO.puts("  Process alive: #{Process.alive?(websocket_pid)}")
        
      rescue
        error -> IO.puts("  ⚠️  Could not get process info: #{inspect(error)}")
      end
    else
      IO.puts("  Status: ❌ Not running")
    end
    
    IO.puts("")
  end
  
  defp analyze_heartbeat_config do
    IO.puts("💓 Heartbeat Configuration:")
    
    # Get configuration from the module
    heartbeat_interval = 30_000  # From @heartbeat_interval in the module
    subscription_interval = 300_000  # From @subscription_update_interval
    reconnect_delay = 5_000  # From @reconnect_delay
    
    IO.puts("  Heartbeat interval: #{heartbeat_interval}ms (#{heartbeat_interval / 1000}s)")
    IO.puts("  Subscription update: #{subscription_interval}ms (#{subscription_interval / 1000}s)")
    IO.puts("  Reconnect delay: #{reconnect_delay}ms (#{reconnect_delay / 1000}s)")
    
    # Calculate expected disconnection pattern
    IO.puts("")
    IO.puts("  Expected behavior:")
    IO.puts("    - Heartbeat every 30 seconds")
    IO.puts("    - If server timeout is ~10 minutes, expects heartbeat every 30s")
    IO.puts("    - 10 minutes = 600 seconds = 20 heartbeats")
    IO.puts("    - If 2-3 heartbeats fail, server may disconnect")
    
    IO.puts("")
  end
  
  defp analyze_subscription_data do
    IO.puts("📊 Subscription Data:")
    
    try do
      # Try to get current tracking data
      {:ok, systems} = WandererNotifier.Contexts.ExternalAdapters.get_tracked_systems()
      {:ok, characters} = WandererNotifier.Contexts.ExternalAdapters.get_tracked_characters()
      
      # Process the data similar to how WebSocket client does
      system_ids = systems
      |> Enum.map(&extract_system_id/1)
      |> Enum.filter(&valid_system_id?/1)
      |> Enum.uniq()
      
      character_ids = characters
      |> Enum.map(&extract_character_id/1)
      |> Enum.filter(&valid_character_id?/1)
      |> Enum.uniq()
      
      IO.puts("  Raw systems: #{length(systems)}")
      IO.puts("  Valid system IDs: #{length(system_ids)}")
      IO.puts("  Raw characters: #{length(characters)}")
      IO.puts("  Valid character IDs: #{length(character_ids)}")
      
      # Check if payload might be too large
      estimated_payload_size = length(system_ids) * 10 + length(character_ids) * 12  # rough estimate
      IO.puts("  Estimated payload size: ~#{estimated_payload_size} bytes")
      
      if length(system_ids) > 1000 or length(character_ids) > 500 do
        IO.puts("  ⚠️  Large subscription - may cause server issues")
      end
      
      if length(system_ids) > 0 do
        IO.puts("  Sample system IDs: #{inspect(Enum.take(system_ids, 5))}")
      end
      
      if length(character_ids) > 0 do
        IO.puts("  Sample character IDs: #{inspect(Enum.take(character_ids, 5))}")
      end
      
    rescue
      error -> IO.puts("  ❌ Could not get subscription data: #{inspect(error)}")
    end
    
    IO.puts("")
  end
  
  defp analyze_connection_url do
    IO.puts("🔗 Connection Configuration:")
    
    websocket_url = WandererNotifier.Config.websocket_url()
    IO.puts("  Base URL: #{websocket_url}")
    
    # Build socket URL like the client does
    socket_url = websocket_url
    |> String.replace("http://", "ws://")
    |> String.replace("https://", "wss://")
    |> ensure_socket_path()
    
    IO.puts("  Full WebSocket URL: #{socket_url}")
    
    # Check if URL is reachable
    IO.puts("  💡 Test connection manually with (if wscat is installed):")
    IO.puts("    wscat -c \"#{socket_url}\"")
    IO.puts("  💡 Or install wscat with: npm install -g wscat")
    
    IO.puts("")
  end
  
  defp ensure_socket_path(url) do
    cond do
      String.ends_with?(url, "/socket/websocket") ->
        add_version_param(url)
      String.ends_with?(url, "/socket") ->
        add_version_param("#{url}/websocket")
      true ->
        url = String.trim_trailing(url, "/")
        add_version_param("#{url}/socket/websocket")
    end
  end
  
  defp add_version_param(url) do
    separator = if String.contains?(url, "?"), do: "&", else: "?"
    "#{url}#{separator}vsn=1.0.0"
  end
  
  defp print_recommendations do
    IO.puts("🔍 Debug Steps:")
    IO.puts("1. Run the monitoring script: elixir scripts/websocket_monitor.exs")
    IO.puts("2. Watch logs in your 'make s' terminal for WebSocket messages")
    IO.puts("3. Test WebSocket server directly (if wscat is available):")
    IO.puts("   wscat -c \"ws://localhost:4004/socket/websocket?vsn=1.0.0\"")
    IO.puts("4. Check WandererKills service logs for connection issues")
    IO.puts("5. Monitor application memory and process health")
    IO.puts("")
    IO.puts("🔧 Possible Issues to Investigate:")
    IO.puts("- Server-side timeout configuration (usually 60-600 seconds)")
    IO.puts("- Network connectivity to WandererKills service")
    IO.puts("- Large subscription payload causing server to drop connection")
    IO.puts("- Heartbeat mechanism not compatible with server expectations")
    IO.puts("- Phoenix Channels version mismatch")
    IO.puts("")
    IO.puts("🚀 Quick Test:")
    IO.puts("Try reducing subscription size by limiting systems/characters")
    IO.puts("Add these to your .env file to test:")
    IO.puts("  WEBSOCKET_MAX_SYSTEMS=50")
    IO.puts("  WEBSOCKET_MAX_CHARACTERS=25")
    IO.puts("")
    IO.puts("📊 Dashboard:")
    IO.puts("Check the enhanced dashboard at http://localhost:3000")
    IO.puts("for real-time WebSocket status and process monitoring")
  end
  
  # Helper functions from WebSocket client
  defp extract_system_id(system) when is_struct(system) do
    system.solar_system_id || system.id
  end
  
  defp extract_system_id(system) when is_map(system) do
    system["solar_system_id"] || system[:solar_system_id] ||
      system["system_id"] || system[:system_id]
  end
  
  defp extract_system_id(_), do: nil
  
  defp valid_system_id?(system_id) do
    is_integer(system_id) && system_id > 30_000_000 && system_id < 40_000_000
  end
  
  defp extract_character_id(char) do
    char_id = char["eve_id"] || char[:eve_id]
    normalize_character_id(char_id)
  end
  
  defp normalize_character_id(id) when is_integer(id), do: id
  defp normalize_character_id(id) when is_binary(id) do
    case Integer.parse(id) do
      {int_id, ""} -> int_id
      _ -> nil
    end
  end
  defp normalize_character_id(_), do: nil
  
  defp valid_character_id?(char_id) do
    is_integer(char_id) && char_id > 90_000_000 && char_id < 100_000_000_000
  end
end

# Start debug analysis
WebSocketDebug.start()