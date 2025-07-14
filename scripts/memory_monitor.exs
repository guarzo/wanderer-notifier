#!/usr/bin/env elixir

# Memory monitoring script for Wanderer Notifier
# Usage: elixir scripts/memory_monitor.exs [interval_seconds]

defmodule MemoryMonitor do
  def start(interval \\ 5) do
    IO.puts("Starting memory monitoring (interval: #{interval}s)")
    IO.puts("Press Ctrl+C to stop")
    IO.puts("")
    
    loop(interval)
  end
  
  defp loop(interval) do
    print_memory_stats()
    :timer.sleep(interval * 1000)
    loop(interval)
  end
  
  defp print_memory_stats do
    memory_info = :erlang.memory()
    
    timestamp = DateTime.utc_now() |> DateTime.to_string()
    
    IO.puts("=== Memory Report - #{timestamp} ===")
    IO.puts("Total:      #{mb(memory_info[:total])} MB")
    IO.puts("Processes:  #{mb(memory_info[:processes])} MB (#{mb(memory_info[:processes_used])} used)")
    IO.puts("System:     #{mb(memory_info[:system])} MB")
    IO.puts("Atom:       #{mb(memory_info[:atom])} MB (#{mb(memory_info[:atom_used])} used)")
    IO.puts("Binary:     #{mb(memory_info[:binary])} MB")
    IO.puts("Code:       #{mb(memory_info[:code])} MB")
    IO.puts("ETS:        #{mb(memory_info[:ets])} MB")
    
    # Process statistics
    process_count = :erlang.system_info(:process_count)
    process_limit = :erlang.system_info(:process_limit)
    process_usage = Float.round(process_count / process_limit * 100, 1)
    
    IO.puts("")
    IO.puts("Processes:  #{process_count}/#{process_limit} (#{process_usage}%)")
    
    # Port statistics
    port_count = :erlang.system_info(:port_count)
    port_limit = :erlang.system_info(:port_limit)
    port_usage = Float.round(port_count / port_limit * 100, 1)
    
    IO.puts("Ports:      #{port_count}/#{port_limit} (#{port_usage}%)")
    
    # Atom statistics
    atom_count = :erlang.system_info(:atom_count)
    atom_limit = :erlang.system_info(:atom_limit)
    atom_usage = Float.round(atom_count / atom_limit * 100, 1)
    
    IO.puts("Atoms:      #{atom_count}/#{atom_limit} (#{atom_usage}%)")
    
    # GC statistics
    gc_info = :erlang.statistics(:garbage_collection)
    total_collections = elem(gc_info, 0)
    total_reclaimed = elem(gc_info, 1)
    
    IO.puts("GC:         #{total_collections} collections, #{mb(total_reclaimed * 8)} MB reclaimed")
    
    # Check for potential issues
    check_memory_issues(memory_info, process_usage, atom_usage)
    
    IO.puts("")
    IO.puts("----------------------------------------")
    IO.puts("")
  end
  
  defp check_memory_issues(memory_info, process_usage, atom_usage) do
    issues = []
    
    # Check total memory usage
    total_mb = mb(memory_info[:total])
    issues = if total_mb > 512 do
      ["⚠️  High total memory usage: #{total_mb} MB" | issues]
    else
      issues
    end
    
    # Check process memory
    processes_mb = mb(memory_info[:processes])
    issues = if processes_mb > 256 do
      ["⚠️  High process memory usage: #{processes_mb} MB" | issues]
    else
      issues
    end
    
    # Check binary memory (often indicates memory leaks)
    binary_mb = mb(memory_info[:binary])
    issues = if binary_mb > 64 do
      ["⚠️  High binary memory usage: #{binary_mb} MB" | issues]
    else
      issues
    end
    
    # Check ETS memory
    ets_mb = mb(memory_info[:ets])
    issues = if ets_mb > 32 do
      ["⚠️  High ETS memory usage: #{ets_mb} MB" | issues]
    else
      issues
    end
    
    # Check process count
    issues = if process_usage > 80 do
      ["⚠️  High process usage: #{process_usage}%" | issues]
    else
      issues
    end
    
    # Check atom usage
    issues = if atom_usage > 80 do
      ["⚠️  High atom usage: #{atom_usage}%" | issues]
    else
      issues
    end
    
    if issues != [] do
      IO.puts("")
      IO.puts("🚨 POTENTIAL ISSUES DETECTED:")
      Enum.each(issues, &IO.puts/1)
    end
  end
  
  defp mb(bytes) when is_integer(bytes) do
    Float.round(bytes / 1_048_576, 2)
  end
  defp mb(_), do: 0.0
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
MemoryMonitor.start(interval)