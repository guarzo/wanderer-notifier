#!/usr/bin/env elixir

# WebSocket monitoring script for Wanderer Notifier
# Usage: elixir scripts/websocket_monitor.exs [interval_seconds]

defmodule WebSocketMonitor do
  def start(interval \\ 5) do
    IO.puts("Starting WebSocket monitoring (interval: #{interval}s)")
    IO.puts("Press Ctrl+C to stop")
    IO.puts("")
    
    # Track connection state over time
    loop(interval, %{
      start_time: DateTime.utc_now(),
      last_status: nil,
      connection_count: 0,
      disconnection_count: 0,
      last_disconnect_time: nil,
      uptime_when_disconnected: []
    })
  end
  
  defp loop(interval, state) do
    new_state = print_websocket_stats(state)
    :timer.sleep(interval * 1000)
    loop(interval, new_state)
  end
  
  defp print_websocket_stats(state) do
    timestamp = DateTime.utc_now() |> DateTime.to_string()
    
    IO.puts("=== WebSocket Report - #{timestamp} ===")
    
    # Check WebSocket client status
    websocket_pid = Process.whereis(WandererNotifier.Killmail.WebSocketClient)
    current_status = if websocket_pid, do: :connected, else: :disconnected
    
    # Track state changes
    new_state = track_state_changes(state, current_status)
    
    if websocket_pid do
      print_connected_stats(websocket_pid, new_state)
    else
      print_disconnected_stats(new_state)
    end
    
    # Print tracking data
    print_tracking_stats()
    
    # Print recent logs if available
    print_recent_websocket_logs()
    
    IO.puts("")
    IO.puts("----------------------------------------")
    IO.puts("")
    
    new_state
  end
  
  defp track_state_changes(state, current_status) do
    cond do
      # First run
      state.last_status == nil ->
        %{state | last_status: current_status}
      
      # Connection established
      state.last_status == :disconnected and current_status == :connected ->
        IO.puts("🟢 WebSocket CONNECTED!")
        %{state | 
          last_status: current_status,
          connection_count: state.connection_count + 1
        }
      
      # Connection lost
      state.last_status == :connected and current_status == :disconnected ->
        uptime = DateTime.diff(DateTime.utc_now(), state.start_time, :second)
        IO.puts("🔴 WebSocket DISCONNECTED after #{uptime} seconds!")
        
        %{state |
          last_status: current_status,
          disconnection_count: state.disconnection_count + 1,
          last_disconnect_time: DateTime.utc_now(),
          uptime_when_disconnected: [uptime | state.uptime_when_disconnected]
        }
      
      # No change
      true ->
        state
    end
  end
  
  defp print_connected_stats(websocket_pid, state) do
    uptime = DateTime.diff(DateTime.utc_now(), state.start_time, :second)
    
    IO.puts("Status: 🟢 CONNECTED")
    IO.puts("PID: #{inspect(websocket_pid)}")
    IO.puts("Connection uptime: #{format_duration(uptime)}")
    IO.puts("Total connections: #{state.connection_count}")
    IO.puts("Total disconnections: #{state.disconnection_count}")
    
    # Try to get process info
    try do
      info = Process.info(websocket_pid)
      memory_kb = div(info[:memory] || 0, 1024)
      message_queue_len = info[:message_queue_len] || 0
      
      IO.puts("Memory usage: #{memory_kb} KB")
      IO.puts("Message queue: #{message_queue_len}")
      IO.puts("Heap size: #{info[:heap_size] || 0}")
      
      if message_queue_len > 10 do
        IO.puts("⚠️  High message queue detected!")
      end
      
    rescue
      _ -> IO.puts("Could not get process info")
    end
    
    # Print disconnection pattern if we have data
    if length(state.uptime_when_disconnected) > 0 do
      IO.puts("")
      IO.puts("Disconnection pattern:")
      avg_uptime = Enum.sum(state.uptime_when_disconnected) / length(state.uptime_when_disconnected)
      IO.puts("  Average uptime before disconnect: #{round(avg_uptime)} seconds")
      IO.puts("  Uptimes: #{inspect(Enum.reverse(state.uptime_when_disconnected))}")
    end
  end
  
  defp print_disconnected_stats(state) do
    IO.puts("Status: 🔴 DISCONNECTED")
    IO.puts("Total connections: #{state.connection_count}")
    IO.puts("Total disconnections: #{state.disconnection_count}")
    
    if state.last_disconnect_time do
      disconnect_ago = DateTime.diff(DateTime.utc_now(), state.last_disconnect_time, :second)
      IO.puts("Last disconnect: #{format_duration(disconnect_ago)} ago")
    end
    
    if length(state.uptime_when_disconnected) > 0 do
      avg_uptime = Enum.sum(state.uptime_when_disconnected) / length(state.uptime_when_disconnected)
      IO.puts("Average uptime before disconnect: #{round(avg_uptime)} seconds")
    end
  end
  
  defp print_tracking_stats do
    try do
      # Get tracking stats if available
      stats = WandererNotifier.Core.Stats.get_stats()
      
      IO.puts("")
      IO.puts("Tracking Stats:")
      IO.puts("  Systems: #{stats[:systems_count] || 0}")
      IO.puts("  Characters: #{stats[:characters_count] || 0}")
      IO.puts("  Killmails received: #{stats[:killmails_received] || 0}")
      
      processing = stats[:processing] || %{}
      IO.puts("  Kills processed: #{processing[:kills_processed] || 0}")
      IO.puts("  Notifications sent: #{processing[:kills_notified] || 0}")
      
    rescue
      _ -> IO.puts("Could not get tracking stats")
    end
  end
  
  defp print_recent_websocket_logs do
    # This would require access to the logger backend
    # For now, just indicate where to look
    IO.puts("")
    IO.puts("💡 Check logs in your terminal where you ran 'make s'")
    IO.puts("   Look for WebSocket-related messages")
  end
  
  defp format_duration(seconds) when seconds < 60, do: "#{seconds}s"
  defp format_duration(seconds) when seconds < 3600 do
    minutes = div(seconds, 60)
    remaining_seconds = rem(seconds, 60)
    "#{minutes}m #{remaining_seconds}s"
  end
  defp format_duration(seconds) do
    hours = div(seconds, 3600)
    remaining_minutes = div(rem(seconds, 3600), 60)
    "#{hours}h #{remaining_minutes}m"
  end
end

# Parse command line arguments
{interval, _} = case System.argv() do
  [interval_str] -> 
    case Integer.parse(interval_str) do
      {interval, ""} -> {interval, []}
      _ -> {5, []}
    end
  _ -> {5, []}
end

# Start monitoring
WebSocketMonitor.start(interval)