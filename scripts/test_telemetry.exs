#!/usr/bin/env elixir

# Script to test telemetry metrics
defmodule TelemetryTest do
  def test do
    IO.puts("Testing telemetry metrics...")
    
    try do
      # Check if telemetry module is available
      unless Code.ensure_loaded?(WandererNotifier.Telemetry) do
        raise "Telemetry module not loaded. Ensure the application is running."
      end
      
      # Test processing started
      safe_telemetry_call("processing_started", fn ->
        WandererNotifier.Telemetry.processing_started("test_kill_1")
      end)
      
      # Test processing completed successfully
      safe_telemetry_call("processing_completed (success)", fn ->
        WandererNotifier.Telemetry.processing_completed("test_kill_1", {:ok, :notified})
      end)
      
      # Test processing skipped
      safe_telemetry_call("processing_started (skip)", fn ->
        WandererNotifier.Telemetry.processing_started("test_kill_2")
      end)
      
      safe_telemetry_call("processing_completed (skip)", fn ->
        WandererNotifier.Telemetry.processing_completed("test_kill_2", {:ok, :skipped})
      end)
      
      safe_telemetry_call("processing_skipped", fn ->
        WandererNotifier.Telemetry.processing_skipped("test_kill_2", :not_tracked)
      end)
      
      # Test processing error
      safe_telemetry_call("processing_started (error)", fn ->
        WandererNotifier.Telemetry.processing_started("test_kill_3")
      end)
      
      safe_telemetry_call("processing_completed (error)", fn ->
        WandererNotifier.Telemetry.processing_completed("test_kill_3", {:error, :invalid_data})
      end)
      
      safe_telemetry_call("processing_error", fn ->
        WandererNotifier.Telemetry.processing_error("test_kill_3", :invalid_data)
      end)
      
      # Wait for stats to update
      Process.sleep(100)
      
      # Get current stats with error handling
      stats = get_stats_safely()
      metrics = stats[:metrics] || %{}
    
    IO.puts("\nTelemetry Metrics:")
    IO.puts("- Processing start: #{Map.get(metrics, :killmail_processing_start, 0)}")
    IO.puts("- Processing complete: #{Map.get(metrics, :killmail_processing_complete, 0)}")
    IO.puts("- Processing success: #{Map.get(metrics, :killmail_processing_complete_success, 0)}")
    IO.puts("- Processing error: #{Map.get(metrics, :killmail_processing_complete_error, 0)}")
    IO.puts("- Processing skipped: #{Map.get(metrics, :killmail_processing_skipped, 0)}")
    IO.puts("- Processing errors: #{Map.get(metrics, :killmail_processing_error, 0)}")
    
    # Test performance calculation
    processing_complete = Map.get(metrics, :killmail_processing_complete, 0)
    processing_error = Map.get(metrics, :killmail_processing_error, 0)
    processing_skipped = Map.get(metrics, :killmail_processing_skipped, 0)
    
    success_rate = if processing_complete + processing_error > 0 do
      Float.round(processing_complete / (processing_complete + processing_error) * 100, 1)
    else
      0.0
    end
    
    efficiency = if processing_complete + processing_skipped > 0 do
      Float.round(processing_complete / (processing_complete + processing_skipped) * 100, 1)
    else
      0.0
    end
    
    IO.puts("\nCalculated Performance:")
    IO.puts("- Success Rate: #{success_rate}%")
    IO.puts("- Processing Efficiency: #{efficiency}%")
    
      IO.puts("\nTest complete!")
    rescue
      error ->
        IO.puts("\n❌ Test failed with error: #{inspect(error)}")
        IO.puts("Stacktrace:")
        IO.inspect(__STACKTRACE__, limit: :infinity)
        System.halt(1)
    end
  end

  defp safe_telemetry_call(operation, fun) do
    try do
      fun.()
      IO.puts("✓ #{operation}")
    rescue
      error ->
        IO.puts("✗ #{operation} failed: #{inspect(error)}")
        # Don't re-raise, continue with other tests
    end
  end

  defp get_stats_safely do
    try do
      # Check if Stats module is available
      unless Code.ensure_loaded?(WandererNotifier.Core.Stats) do
        raise "Stats module not loaded"
      end
      
      # Check if the GenServer is running
      case Process.whereis(WandererNotifier.Core.Stats) do
        nil ->
          IO.puts("⚠️  Stats GenServer not running, using empty stats")
          %{}
        
        pid when is_pid(pid) ->
          WandererNotifier.Core.Stats.get_stats()
      end
    rescue
      error ->
        IO.puts("⚠️  Failed to get stats: #{inspect(error)}")
        %{}
    end
  end
end

# Run the test with proper error handling
try do
  TelemetryTest.test()
rescue
  error ->
    IO.puts("\n❌ Failed to run telemetry test: #{inspect(error)}")
    System.halt(1)
end