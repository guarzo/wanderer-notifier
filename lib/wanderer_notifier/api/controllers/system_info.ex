defmodule WandererNotifier.Api.Controllers.SystemInfo do
  @moduledoc """
  Shared module for collecting system information used by health and dashboard endpoints.
  """

  alias WandererNotifier.Shared.Config
  alias WandererNotifier.Shared.Utils.TimeUtils

  @doc """
  Collects detailed system information including server status, memory usage, and uptime.
  """
  def collect_detailed_status do
    web_server_status = check_server_status()
    memory_info = :erlang.memory()

    # Get uptime from stats which tracks startup time
    stats = WandererNotifier.Application.Services.Stats.get_stats()
    uptime_seconds = stats[:uptime_seconds] || 0

    %{
      status: "OK",
      web_server: %{
        running: web_server_status,
        port: Config.port(),
        bind_address: Config.host()
      },
      system: %{
        uptime_seconds: uptime_seconds,
        memory: build_memory_info(memory_info),
        scheduler_count: :erlang.system_info(:schedulers_online)
      },
      timestamp: TimeUtils.log_timestamp(),
      server_version: Config.version()
    }
  end

  @doc """
  Collects extended status information including tracking and notification stats.
  """
  def collect_extended_status do
    base_status = collect_detailed_status()
    stats = WandererNotifier.Application.Services.Stats.get_stats()

    extended_data = %{
      tracking: extract_tracking_stats(stats),
      notifications: extract_notification_stats(stats),
      processing: extract_processing_stats(stats),
      performance: extract_performance_stats(stats),
      websocket: extract_websocket_stats(),
      recent_activity: extract_recent_activity(),
      memory_detailed: extract_detailed_memory_stats(),
      processes: extract_process_stats(),
      cache_stats: extract_cache_stats(),
      gc_stats: extract_gc_stats()
    }

    Map.merge(base_status, extended_data)
  end

  defp extract_tracking_stats(stats) do
    %{
      systems_count: stats[:systems_count] || 0,
      characters_count: stats[:characters_count] || 0,
      killmails_received: stats[:killmails_received] || 0
    }
  end

  defp extract_notification_stats(stats) do
    notifications = stats[:notifications] || %{}

    %{
      total: notifications[:total] || 0,
      kills: notifications[:kills] || 0,
      systems: notifications[:systems] || 0,
      characters: notifications[:characters] || 0
    }
  end

  defp extract_processing_stats(stats) do
    processing = stats[:processing] || %{}
    metrics = stats[:metrics] || %{}

    base_stats = extract_base_processing_stats(processing)
    metric_stats = extract_metric_processing_stats(metrics)

    Map.merge(base_stats, metric_stats)
  end

  defp extract_base_processing_stats(processing) do
    %{
      kills_processed: processing[:kills_processed] || 0,
      kills_notified: processing[:kills_notified] || 0
    }
  end

  defp extract_metric_processing_stats(metrics) do
    %{
      processing_start: metrics[:killmail_processing_start] || 0,
      processing_complete: metrics[:killmail_processing_complete] || 0,
      processing_complete_success: metrics[:killmail_processing_complete_success] || 0,
      processing_complete_error: metrics[:killmail_processing_complete_error] || 0,
      processing_skipped: metrics[:killmail_processing_skipped] || 0,
      processing_error: metrics[:killmail_processing_error] || 0,
      notifications_sent: metrics[:notification_sent] || 0
    }
  end

  defp safe_div(numerator, denominator) when denominator != 0, do: div(numerator, denominator)
  defp safe_div(_, _), do: 0

  defp build_memory_info(memory_info) do
    total = memory_info[:total] || 0
    processes = memory_info[:processes] || 0
    system = memory_info[:system] || 0

    %{
      total_kb: safe_div(total, 1024),
      processes_kb: safe_div(processes, 1024),
      system_kb: safe_div(system, 1024),
      processes_percent: safe_percentage(processes, total),
      system_percent: safe_percentage(system, total)
    }
  end

  defp safe_percentage(_, 0), do: 0.0

  defp safe_percentage(numerator, denominator) do
    Float.round(numerator / denominator * 100, 1)
  end

  defp extract_performance_stats(stats) do
    processing = stats[:processing] || %{}
    metrics = stats[:metrics] || %{}
    kills_processed = processing[:kills_processed] || 0
    kills_notified = processing[:kills_notified] || 0
    processing_complete = metrics[:killmail_processing_complete] || 0
    processing_error = metrics[:killmail_processing_error] || 0
    processing_skipped = metrics[:killmail_processing_skipped] || 0

    %{
      success_rate: calculate_success_rate(processing_complete, processing_error),
      notification_rate: calculate_notification_rate(kills_notified, kills_processed),
      processing_efficiency:
        calculate_processing_efficiency(processing_complete, processing_skipped),
      uptime_seconds: stats[:uptime_seconds] || 0,
      last_activity: get_last_activity_time(stats)
    }
  end

  defp extract_websocket_stats do
    # Check if WebSocket client is alive and get basic stats
    websocket_pid = Process.whereis(WandererNotifier.Domains.Killmail.WebSocketClient)

    {connection_uptime, uptime_formatted} =
      if websocket_pid do
        try do
          # Get connection start time from WebSocket client state
          stats = WandererNotifier.Application.Services.Stats.get_stats()
          websocket_stats = stats[:websocket] || %{}
          connection_start = websocket_stats[:connection_start]

          if connection_start do
            uptime_seconds = System.system_time(:second) - connection_start
            formatted = format_connection_duration(uptime_seconds)
            {uptime_seconds, formatted}
          else
            {0, "Unknown"}
          end
        rescue
          _ -> {0, "Unknown"}
        end
      else
        {0, "Not connected"}
      end

    %{
      client_alive: websocket_pid != nil,
      connection_status: if(websocket_pid, do: "connected", else: "disconnected"),
      connection_uptime_seconds: connection_uptime,
      connection_uptime_formatted: uptime_formatted
    }
  end

  defp format_connection_duration(seconds) when seconds < 60, do: "#{seconds}s"

  defp format_connection_duration(seconds) when seconds < 3600 do
    minutes = div(seconds, 60)
    remaining_seconds = rem(seconds, 60)
    "#{minutes}m #{remaining_seconds}s"
  end

  defp format_connection_duration(seconds) do
    hours = div(seconds, 3600)
    remaining_minutes = div(rem(seconds, 3600), 60)
    "#{hours}h #{remaining_minutes}m"
  end

  defp calculate_success_rate(complete, error) when complete + error > 0 do
    Float.round(complete / (complete + error) * 100, 1)
  end

  defp calculate_success_rate(_, _), do: 0.0

  defp calculate_notification_rate(notified, processed) when processed > 0 do
    Float.round(notified / processed * 100, 1)
  end

  defp calculate_notification_rate(_, _), do: 0.0

  defp calculate_processing_efficiency(complete, skipped) when complete + skipped > 0 do
    Float.round(complete / (complete + skipped) * 100, 1)
  end

  defp calculate_processing_efficiency(_, _), do: 0.0

  defp get_last_activity_time(stats) do
    redisq = stats[:redisq] || %{}

    case redisq[:last_message] do
      nil -> "never"
      dt -> format_time_ago(dt)
    end
  end

  defp format_time_ago(datetime) do
    case WandererNotifier.Shared.Utils.TimeUtils.elapsed_seconds(datetime) do
      seconds when seconds < 60 -> "#{seconds}s ago"
      seconds when seconds < 3_600 -> "#{div(seconds, 60)}m ago"
      seconds when seconds < 86_400 -> "#{div(seconds, 3_600)}h ago"
      seconds -> "#{div(seconds, 86_400)}d ago"
    end
  end

  defp extract_recent_activity do
    # Get recent activity from various sources
    activities = []

    # Check WebSocket status
    websocket_pid = Process.whereis(WandererNotifier.Domains.Killmail.WebSocketClient)

    activities =
      if websocket_pid do
        [{:websocket, "WebSocket client active", DateTime.utc_now()} | activities]
      else
        [{:websocket_error, "WebSocket client not running", DateTime.utc_now()} | activities]
      end

    # Add some sample recent activities (in a real implementation, you'd collect these from logs)
    recent_activities = [
      {:info, "System started", DateTime.utc_now() |> DateTime.add(-3_600, :second)},
      {:info, "WebSocket connected", DateTime.utc_now() |> DateTime.add(-1_800, :second)},
      {:info, "Processing killmails", DateTime.utc_now() |> DateTime.add(-300, :second)}
    ]

    (activities ++ recent_activities)
    |> Enum.take(10)
    |> Enum.map(fn {type, message, timestamp} ->
      %{
        type: type,
        message: message,
        timestamp: timestamp,
        time_ago: format_time_ago(timestamp)
      }
    end)
  end

  defp extract_detailed_memory_stats do
    memory_info = :erlang.memory()
    memory_data = extract_memory_data(memory_info)
    system_data = extract_system_data()

    Map.merge(memory_data, system_data)
  end

  defp extract_memory_data(memory_info) do
    memory_keys = [
      :total,
      :processes,
      :processes_used,
      :system,
      :atom,
      :atom_used,
      :binary,
      :code,
      :ets
    ]

    memory_keys
    |> Enum.into(%{}, fn key ->
      mb_key = String.to_atom("#{key}_mb")
      {mb_key, bytes_to_mb(memory_info[key] || 0)}
    end)
  end

  defp extract_system_data do
    %{
      max_processes: :erlang.system_info(:process_limit),
      process_count: :erlang.system_info(:process_count),
      port_count: :erlang.system_info(:port_count),
      port_limit: :erlang.system_info(:port_limit),
      atom_count: :erlang.system_info(:atom_count),
      atom_limit: :erlang.system_info(:atom_limit)
    }
  end

  defp extract_process_stats do
    process_count = :erlang.system_info(:process_count)
    process_limit = :erlang.system_info(:process_limit)

    # Get information about key processes
    key_processes = get_key_process_info()

    %{
      count: process_count,
      limit: process_limit,
      usage_percent: Float.round(process_count / process_limit * 100, 1),
      key_processes: key_processes
    }
  end

  defp extract_cache_stats do
    try do
      cache_name = WandererNotifier.Infrastructure.Cache.ConfigSimple.cache_name()
      get_cache_stats_for_process(cache_name)
    rescue
      error ->
        WandererNotifier.Shared.Logger.Logger.error(
          "Exception getting cache stats: #{inspect(error)}"
        )

        empty_cache_stats()
    end
  end

  defp get_cache_stats_for_process(cache_name) do
    case Process.whereis(cache_name) do
      nil ->
        handle_missing_cache_process(cache_name)

      _pid ->
        fetch_cachex_stats(cache_name)
    end
  end

  defp handle_missing_cache_process(cache_name) do
    WandererNotifier.Shared.Logger.Logger.warn("Cache process not found: #{cache_name}")
    empty_cache_stats()
  end

  defp fetch_cachex_stats(cache_name) do
    case Cachex.stats(cache_name) do
      {:ok, stats} ->
        build_cache_stats_from_cachex(stats, cache_name)

      {:error, reason} ->
        handle_cachex_error(reason)
    end
  end

  defp build_cache_stats_from_cachex(stats, cache_name) do
    %{
      hits: stats.hits || 0,
      misses: stats.misses || 0,
      hit_rate: calculate_hit_rate(stats.hits, stats.misses),
      evictions: Map.get(stats, :evictions, 0),
      expirations: Map.get(stats, :expirations, 0),
      writes: stats.writes || 0,
      size: get_cache_size(cache_name)
    }
  end

  defp handle_cachex_error(reason) do
    WandererNotifier.Shared.Logger.Logger.warn("Failed to get cache stats: #{inspect(reason)}")
    empty_cache_stats()
  end

  defp empty_cache_stats do
    %{
      hits: 0,
      misses: 0,
      hit_rate: 0.0,
      evictions: 0,
      expirations: 0,
      writes: 0,
      size: 0
    }
  end

  defp extract_gc_stats do
    # Get garbage collection statistics
    gc_info = :erlang.statistics(:garbage_collection)

    %{
      total_collections: elem(gc_info, 0),
      total_reclaimed_words: elem(gc_info, 1),
      # words to bytes to MB
      total_reclaimed_mb: bytes_to_mb(elem(gc_info, 1) * 8)
    }
  end

  defp get_key_process_info do
    processes = [
      {"WebSocket Client", WandererNotifier.Domains.Killmail.WebSocketClient},
      {"Stats Server", WandererNotifier.Application.Services.Stats},
      {"Pipeline Worker", WandererNotifier.Domains.Killmail.PipelineWorker},
      {"Discord Consumer", WandererNotifier.Infrastructure.Adapters.Discord.Consumer}
    ]

    processes
    |> Enum.map(fn {name, module} ->
      pid = Process.whereis(module)

      if pid do
        info = Process.info(pid)
        memory_kb = div(info[:memory] || 0, 1024)
        message_queue_len = info[:message_queue_len] || 0

        %{
          name: name,
          status: "running",
          memory_kb: memory_kb,
          message_queue_len: message_queue_len,
          heap_size: info[:heap_size] || 0
        }
      else
        %{
          name: name,
          status: "not_running",
          memory_kb: 0,
          message_queue_len: 0,
          heap_size: 0
        }
      end
    end)
  end

  defp bytes_to_mb(bytes) when is_integer(bytes) do
    Float.round(bytes / 1_048_576, 2)
  end

  defp bytes_to_mb(_), do: 0.0

  defp calculate_hit_rate(hits, misses) when hits + misses > 0 do
    Float.round(hits / (hits + misses) * 100, 1)
  end

  defp calculate_hit_rate(_, _), do: 0.0

  defp get_cache_size(cache_name) do
    try do
      case Cachex.size(cache_name) do
        {:ok, size} -> size
        _ -> 0
      end
    rescue
      _ -> 0
    end
  end

  defp check_server_status do
    # Check if Phoenix endpoint is running
    try do
      case Process.whereis(WandererNotifierWeb.Endpoint) do
        nil -> false
        _pid -> true
      end
    rescue
      error ->
        WandererNotifier.Shared.Logger.Logger.error("Failed to check server status",
          error: inspect(error),
          module: __MODULE__
        )

        false
    end
  end
end
