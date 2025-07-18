#!/usr/bin/env elixir

Mix.install([
  :jason,
  {:cachex, "~> 3.6"}
])

defmodule MemoryAnalysis do
  @moduledoc """
  Analyzes potential memory issues in the WandererNotifier codebase.
  """

  def run do
    IO.puts("Memory Analysis Report")
    IO.puts("====================")
    
    analyze_cache_configuration()
    analyze_data_structures()
    analyze_potential_leaks()
    suggest_optimizations()
  end

  defp analyze_cache_configuration do
    IO.puts("\n1. Cache Configuration Analysis:")
    IO.puts("   - Default cache implementation: Cachex")
    IO.puts("   - Compression threshold: 1024 bytes")
    IO.puts("   - No memory limits configured")
    IO.puts("   - TTL varies by data type:")
    IO.puts("     * Characters: 24 hours")
    IO.puts("     * Corporations: 24 hours") 
    IO.puts("     * Alliances: 24 hours")
    IO.puts("     * Systems: 1 hour")
    IO.puts("     * Killmails: 30 minutes")
    
    IO.puts("\n   ⚠️  ISSUE: No cache size limits configured")
    IO.puts("   ⚠️  ISSUE: Cache hit ratio at 0% suggests cache keys aren't matching")
  end

  defp analyze_data_structures do
    IO.puts("\n2. Data Structure Analysis:")
    
    IO.puts("   Large accumulators found:")
    IO.puts("   - Cache.Analytics: operations list (limited to 200)")
    IO.puts("   - Cache.Analytics: response_times list (limited to 200)")
    IO.puts("   - Cache.Analytics: key_stats map (limited to 200 keys)")
    IO.puts("   - Cache.PerformanceMonitor: performance_history (limited to 10)")
    
    IO.puts("\n   JSON processing:")
    IO.puts("   - WebSocket messages: full message logged + decoded")
    IO.puts("   - SSE events: parsed and processed")
    IO.puts("   - HTTP responses: JSON decoded for each API call")
    
    IO.puts("\n   ⚠️  POTENTIAL ISSUE: Full message logging in WebSocket client")
    IO.puts("   ⚠️  POTENTIAL ISSUE: No JSON streaming for large responses")
  end

  defp analyze_potential_leaks do
    IO.puts("\n3. Potential Memory Leaks:")
    
    IO.puts("   Telemetry system:")
    IO.puts("   - Multiple telemetry attachments for cache metrics")
    IO.puts("   - HTTP middleware telemetry for every request")
    IO.puts("   - Killmail processing telemetry")
    
    IO.puts("   Process mailboxes:")
    IO.puts("   - WebSocket client receives all messages")
    IO.puts("   - SSE client processes continuous events") 
    IO.puts("   - Cache analytics processes every cache operation")
    
    IO.puts("\n   GenServer state accumulation:")
    IO.puts("   - Cache.Analytics: bounded collections but 200 items each")
    IO.puts("   - Performance monitor: stores performance history")
    IO.puts("   - Version manager: stores version history")
    
    IO.puts("\n   ⚠️  CRITICAL: Cache hit ratio 0% means all requests miss cache")
    IO.puts("   ⚠️  CRITICAL: This causes excessive API calls and memory allocation")
  end

  defp suggest_optimizations do
    IO.puts("\n4. Optimization Suggestions:")
    
    IO.puts("\n   Immediate fixes:")
    IO.puts("   1. Add cache memory limits (e.g., 200MB max)")
    IO.puts("   2. Fix cache key generation/matching issue")
    IO.puts("   3. Reduce WebSocket message logging verbosity")
    IO.puts("   4. Add cache warmup on startup")
    
    IO.puts("\n   Cache configuration:")
    IO.puts("   1. Set max_size limits on all caches")
    IO.puts("   2. Configure memory usage thresholds")
    IO.puts("   3. Enable proper cache statistics")
    IO.puts("   4. Add cache warming for frequently accessed data")
    
    IO.puts("\n   Memory monitoring:")
    IO.puts("   1. Add process memory monitoring")
    IO.puts("   2. Monitor GenServer mailbox sizes")
    IO.puts("   3. Track binary allocation patterns")
    IO.puts("   4. Implement memory alerts")
    
    IO.puts("\n   Data structure optimizations:")
    IO.puts("   1. Stream large JSON responses")
    IO.puts("   2. Limit log message sizes")
    IO.puts("   3. Use circular buffers for analytics")
    IO.puts("   4. Implement data compression for large objects")
  end
end

MemoryAnalysis.run()