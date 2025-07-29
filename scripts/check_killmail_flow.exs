#!/usr/bin/env elixir

# Script to check killmail data flow
defmodule KillmailFlowCheck do
  def check do
    IO.puts("\n=== Killmail Flow Diagnostics ===\n")
    
    check_websocket_connection()
    check_tracked_entities()
    check_recent_activity()
    check_wanderer_kills_api()
    
    IO.puts("\n=== Recommendations ===")
    print_recommendations()
  end
  
  defp check_websocket_connection do
    IO.puts("🔌 WebSocket Connection:")
    pid = Process.whereis(WandererNotifier.Killmail.WebSocketClient)
    
    if pid do
      IO.puts("  ✅ WebSocket client is running")
      IO.puts("  PID: #{inspect(pid)}")
    else
      IO.puts("  ❌ WebSocket client not running!")
    end
    IO.puts("")
  end
  
  defp check_tracked_entities do
    IO.puts("📍 Tracked Entities:")
    
    stats = WandererNotifier.Core.Stats.get_stats()
    systems_count = stats[:systems_count] || 0
    characters_count = stats[:characters_count] || 0
    
    IO.puts("  Systems: #{systems_count}")
    IO.puts("  Characters: #{characters_count}")
    
    # Get some sample systems
    {:ok, systems} = WandererNotifier.Contexts.ExternalAdapters.get_tracked_systems()
    sample_systems = systems 
      |> Enum.take(5)
      |> Enum.map(fn s -> 
        id = s.solar_system_id || s.id || s["solar_system_id"] || s[:solar_system_id]
        name = s.name || s["name"] || s[:name] || "Unknown"
        "#{name} (#{id})"
      end)
    
    IO.puts("  Sample systems: #{inspect(sample_systems)}")
    IO.puts("")
  end
  
  defp check_recent_activity do
    IO.puts("📊 Recent Activity:")
    
    stats = WandererNotifier.Core.Stats.get_stats()
    
    # Check killmail stats
    killmails_received = stats[:killmails_received] || 0
    processing = stats[:processing] || %{}
    kills_processed = processing[:kills_processed] || 0
    kills_notified = processing[:kills_notified] || 0
    
    IO.puts("  Killmails received: #{killmails_received}")
    IO.puts("  Kills processed: #{kills_processed}")
    IO.puts("  Kills notified: #{kills_notified}")
    
    # Check metrics
    metrics = stats[:metrics] || %{}
    IO.puts("  Processing started: #{metrics[:killmail_processing_start] || 0}")
    IO.puts("  Processing completed: #{metrics[:killmail_processing_complete] || 0}")
    IO.puts("  Processing errors: #{metrics[:killmail_processing_error] || 0}")
    
    IO.puts("")
  end
  
  defp check_wanderer_kills_api do
    IO.puts("🌐 Checking WandererKills API:")
    
    url = WandererNotifier.Config.wanderer_kills_url()
    IO.puts("  API URL: #{url}")
    
    # Try to fetch recent kills for a known active system
    test_system_id = 31000005  # Thera - usually has activity
    
    case fetch_recent_kills(url, test_system_id) do
      {:ok, kills} ->
        IO.puts("  ✅ API is responding")
        IO.puts("  Test query returned #{length(kills)} kills for system #{test_system_id}")
        
        if length(kills) > 0 do
          latest = List.first(kills)
          IO.puts("  Latest kill time: #{latest["kill_time"]}")
        end
        
      {:error, reason} ->
        IO.puts("  ❌ API request failed: #{inspect(reason)}")
    end
    
    IO.puts("")
  end
  
  defp fetch_recent_kills(base_url, system_id) do
    url = "#{base_url}/api/kills/recent?system_id=#{system_id}&limit=5"
    
    case :httpc.request(:get, {String.to_charlist(url), []}, [{:timeout, 5000}], []) do
      {:ok, {{_, 200, _}, _, body}} ->
        case Jason.decode(body) do
          {:ok, %{"kills" => kills}} -> {:ok, kills}
          {:ok, data} -> {:ok, data}
          error -> error
        end
        
      {:ok, {{_, status, _}, _, body}} ->
        {:error, "HTTP #{status}: #{body}"}
        
      error ->
        {:error, error}
    end
  rescue
    e -> {:error, "Exception: #{inspect(e)}"}
  end
  
  defp print_recommendations do
    IO.puts("🔍 Things to check:")
    IO.puts("1. Verify WandererKills service is receiving data from zkillboard")
    IO.puts("   - Check WandererKills logs")
    IO.puts("   - Verify zkillboard RedisQ is working")
    IO.puts("")
    IO.puts("2. Check if your tracked systems have recent activity")
    IO.puts("   - Wormhole systems might have low activity")
    IO.puts("   - Try adding a known active system like Jita (30000142)")
    IO.puts("")
    IO.puts("3. Monitor WebSocket frames in debug mode:")
    IO.puts("   In IEx: Logger.configure(level: :debug)")
    IO.puts("")
    IO.puts("4. Check the WandererKills WebSocket endpoint directly:")
    IO.puts("   wscat -c \"ws://host.docker.internal:4004/socket/websocket?vsn=1.0.0\"")
    IO.puts("   Then send a join message")
    IO.puts("")
    IO.puts("5. Query WandererKills API for your tracked systems:")
    IO.puts("   curl http://host.docker.internal:4004/api/kills/recent?system_id=YOUR_SYSTEM_ID")
  end
end

# Run the check
KillmailFlowCheck.check()