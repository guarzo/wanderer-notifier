#!/usr/bin/env elixir

# Script to test telemetry metrics
defmodule TelemetryTest do
  def test do
    IO.puts("Testing telemetry metrics...")
    
    # Test processing started
    WandererNotifier.Telemetry.processing_started("test_kill_1")
    
    # Test processing completed successfully
    WandererNotifier.Telemetry.processing_completed("test_kill_1", {:ok, :notified})
    
    # Test processing skipped
    WandererNotifier.Telemetry.processing_started("test_kill_2")
    WandererNotifier.Telemetry.processing_completed("test_kill_2", {:ok, :skipped})
    WandererNotifier.Telemetry.processing_skipped("test_kill_2", :not_tracked)
    
    # Test processing error
    WandererNotifier.Telemetry.processing_started("test_kill_3")
    WandererNotifier.Telemetry.processing_completed("test_kill_3", {:error, :invalid_data})
    WandererNotifier.Telemetry.processing_error("test_kill_3", :invalid_data)
    
    # Wait for stats to update
    Process.sleep(100)
    
    # Get current stats
    stats = WandererNotifier.Core.Stats.get_stats()
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
  end
end

TelemetryTest.test()