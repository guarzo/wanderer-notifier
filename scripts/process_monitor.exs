#!/usr/bin/env elixir

# Process monitoring script for Wanderer Notifier
# Usage: elixir scripts/process_monitor.exs [interval_seconds]

defmodule ProcessMonitor do
  def start(interval \\ 10) do
    IO.puts("Starting process monitoring (interval: #{interval}s)")
    IO.puts("Press Ctrl+C to stop")
    IO.puts("")
    
    loop(interval)
  end
  
  defp loop(interval) do
    print_process_stats()
    :timer.sleep(interval * 1000)
    loop(interval)
  end
  
  defp print_process_stats do
    timestamp = DateTime.utc_now() |> DateTime.to_string()
    
    IO.puts("=== Process Report - #{timestamp} ===")
    
    # Key processes to monitor
    key_processes = [
      {"WebSocket Client", WandererNotifier.Killmail.WebSocketClient},
      {"Pipeline Worker", WandererNotifier.Killmail.PipelineWorker},
      {"Stats Server", WandererNotifier.Core.Stats},
      {"Web Server", WandererNotifier.Web.Server},
      {"Discord Consumer", WandererNotifier.Discord.Consumer},
      {"Cache", :wanderer_cache},
      {"Application", WandererNotifier.Application}
    ]
    
    IO.puts(String.pad_trailing("Process", 20) <> 
            String.pad_trailing("Status", 12) <> 
            String.pad_trailing("Memory", 10) <> 
            String.pad_trailing("Queue", 8) <> 
            String.pad_trailing("Heap", 12) <> 
            "Reductions")\n    IO.puts(String.duplicate("-", 70))\n    \n    Enum.each(key_processes, fn {name, module} ->\n      print_process_info(name, module)\n    end)\n    \n    IO.puts("")\n    print_memory_hogs()\n    print_high_queue_processes()\n    \n    IO.puts("")\n    IO.puts("----------------------------------------")\n    IO.puts("")\n  end\n  \n  defp print_process_info(name, module) do\n    pid = case module do\n      atom when is_atom(atom) -> Process.whereis(atom)\n      _ -> nil\n    end\n    \n    if pid do\n      try do\n        info = Process.info(pid)\n        memory_kb = div(info[:memory] || 0, 1024)\n        message_queue_len = info[:message_queue_len] || 0\n        heap_size = info[:heap_size] || 0\n        reductions = info[:reductions] || 0\n        \n        status = if Process.alive?(pid), do: "✅ Running", else: "❌ Dead"\n        \n        IO.puts(String.pad_trailing(name, 20) <> \n                String.pad_trailing(status, 12) <> \n                String.pad_trailing("#{memory_kb} KB", 10) <> \n                String.pad_trailing("#{message_queue_len}", 8) <> \n                String.pad_trailing("#{heap_size}", 12) <> \n                "#{reductions}")\n                \n        # Check for potential issues\n        check_process_issues(name, memory_kb, message_queue_len, heap_size)\n      rescue\n        _ -> \n          IO.puts(String.pad_trailing(name, 20) <> "❌ Error")\n      end\n    else\n      IO.puts(String.pad_trailing(name, 20) <> "❌ Not Found")\n    end\n  end\n  \n  defp check_process_issues(name, memory_kb, queue_len, heap_size) do\n    issues = []\n    \n    # Check high memory usage\n    issues = if memory_kb > 50_000 do\n      ["🚨 #{name}: High memory usage (#{memory_kb} KB)" | issues]\n    else\n      issues\n    end\n    \n    # Check high message queue\n    issues = if queue_len > 1000 do\n      ["🚨 #{name}: High message queue (#{queue_len} messages)" | issues]\n    else\n      issues\n    end\n    \n    # Check large heap size\n    issues = if heap_size > 100_000 do\n      ["⚠️  #{name}: Large heap size (#{heap_size} words)" | issues]\n    else\n      issues\n    end\n    \n    if issues != [] do\n      Enum.each(issues, &IO.puts/1)\n    end\n  end\n  \n  defp print_memory_hogs do\n    IO.puts("Top 10 Memory Consumers:")\n    IO.puts(String.pad_trailing("PID", 15) <> \n            String.pad_trailing("Memory", 12) <> \n            String.pad_trailing("Initial Call", 30) <> \n            "Current Function")\n    IO.puts(String.duplicate("-", 70))\n    \n    Process.list()\n    |> Enum.map(fn pid ->\n      info = Process.info(pid)\n      memory = info[:memory] || 0\n      {pid, memory, info}\n    end)\n    |> Enum.sort_by(fn {_, memory, _} -> memory end, :desc)\n    |> Enum.take(10)\n    |> Enum.each(fn {pid, memory, info} ->\n      initial_call = format_mfa(info[:initial_call])\n      current_function = format_mfa(info[:current_function])\n      \n      IO.puts(String.pad_trailing(inspect(pid), 15) <> \n              String.pad_trailing("#{div(memory, 1024)} KB", 12) <> \n              String.pad_trailing(initial_call, 30) <> \n              current_function)\n    end)\n  end\n  \n  defp print_high_queue_processes do\n    high_queue = Process.list()\n    |> Enum.map(fn pid ->\n      info = Process.info(pid)\n      queue_len = info[:message_queue_len] || 0\n      {pid, queue_len, info}\n    end)\n    |> Enum.filter(fn {_, queue_len, _} -> queue_len > 10 end)\n    |> Enum.sort_by(fn {_, queue_len, _} -> queue_len end, :desc)\n    \n    if high_queue != [] do\n      IO.puts("")\n      IO.puts("Processes with High Message Queues:")\n      IO.puts(String.pad_trailing("PID", 15) <> \n              String.pad_trailing("Queue", 8) <> \n              "Initial Call")\n      IO.puts(String.duplicate("-", 50))\n      \n      Enum.each(high_queue, fn {pid, queue_len, info} ->\n        initial_call = format_mfa(info[:initial_call])\n        \n        IO.puts(String.pad_trailing(inspect(pid), 15) <> \n                String.pad_trailing("#{queue_len}", 8) <> \n                initial_call)\n      end)\n    end\n  end\n  \n  defp format_mfa(nil), do: "unknown"\n  defp format_mfa({m, f, a}), do: "#{m}.#{f}/#{a}"\n  defp format_mfa(other), do: inspect(other)\nend\n\n# Parse command line arguments\n{interval, _} = case System.argv() do\n  [interval_str] -> \n    case Integer.parse(interval_str) do\n      {interval, ""} -> {interval, []}\n      _ -> {10, []}\n    end\n  _ -> {10, []}\nend\n\n# Start monitoring\nProcessMonitor.start(interval)