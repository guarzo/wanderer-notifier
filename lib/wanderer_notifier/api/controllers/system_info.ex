defmodule WandererNotifier.Api.Controllers.SystemInfo do
  require Logger

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

    # Get uptime from metrics
    uptime_seconds = WandererNotifier.Shared.Metrics.get_uptime_seconds()

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
    stats = WandererNotifier.Shared.Metrics.get_stats()

    extended_data = %{
      tracking: extract_tracking_stats(stats),
      notifications: extract_notification_stats(stats),
      processing: extract_processing_stats(stats),
      performance: extract_performance_stats(stats),
      websocket: extract_websocket_stats(),
      sse: extract_sse_stats(),
      connections: extract_connection_monitor_stats(),
      recent_activity: extract_recent_activity(),
      memory_detailed: extract_detailed_memory_stats(),
      processes: extract_process_stats(),
      cache_stats: extract_cache_stats(),
      gc_stats: extract_gc_stats(),
      killmail_activity: extract_killmail_activity(),
      discord_health: extract_discord_health()
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
          stats = WandererNotifier.Shared.Metrics.get_stats()
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

  defp extract_sse_stats do
    # Try to get SSE client status - check for any registered SSE clients
    try do
      map_name = WandererNotifier.Shared.Config.map_name()
      # If map_name is configured, it will have a value; if not, get_required will raise
      try do
        status = WandererNotifier.Map.SSEClient.get_status(map_name)

        %{
          client_alive: true,
          connection_status: to_string(status),
          map_name: map_name
        }
      catch
        :exit, _ ->
          %{
            client_alive: false,
            connection_status: "not_running",
            map_name: map_name
          }
      end
    rescue
      _ ->
        # Config.map_name() raised because it's not configured
        %{
          client_alive: false,
          connection_status: "not_configured",
          map_name: nil
        }
    end
  end

  defp extract_connection_monitor_stats do
    try do
      case WandererNotifier.Infrastructure.Messaging.ConnectionMonitor.get_connections() do
        {:ok, connections} ->
          %{
            total_connections: length(connections),
            connections: Enum.map(connections, &format_connection_info/1)
          }

        _ ->
          %{total_connections: 0, connections: []}
      end
    rescue
      _ -> %{total_connections: 0, connections: []}
    end
  end

  defp format_connection_info(connection) do
    %{
      id: connection.id,
      type: connection.type,
      status: connection.status,
      quality: connection.quality,
      uptime_percentage: connection.uptime_percentage,
      ping_time: connection.ping_time
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
    websocket = stats[:websocket] || %{}

    case websocket[:last_message] do
      nil -> "never"
      dt -> TimeUtils.format_time_ago(dt)
    end
  end

  defp extract_killmail_activity do
    activity = WandererNotifier.Shared.Metrics.get_killmail_activity()

    %{
      last_received_at: format_datetime(activity[:last_received_at]),
      last_received_ago: TimeUtils.format_time_ago(activity[:last_received_at]),
      last_received_id: activity[:last_received_id],
      received_count: activity[:received_count] || 0,
      last_notified_at: format_datetime(activity[:last_notified_at]),
      last_notified_ago: TimeUtils.format_time_ago(activity[:last_notified_at]),
      last_notified_id: activity[:last_notified_id],
      notified_count: activity[:notified_count] || 0
    }
  end

  defp format_datetime(nil), do: "never"
  defp format_datetime(datetime), do: DateTime.to_iso8601(datetime)

  defp extract_discord_health do
    alias WandererNotifier.Domains.Notifications.Discord.ConnectionHealth

    case ConnectionHealth.get_health_status() do
      {:ok, health} -> build_discord_health_map(health)
      {:error, _reason} -> %{healthy: :unknown, error: "Discord health monitor not available"}
    end
  end

  defp build_discord_health_map(health) do
    %{
      healthy: health[:healthy],
      consecutive_timeouts: health[:consecutive_timeouts],
      consecutive_failures: health[:consecutive_failures],
      last_success_at: format_datetime(health[:last_success_at]),
      last_success_ago: TimeUtils.format_time_ago(health[:last_success_at]),
      last_failure_at: format_datetime(health[:last_failure_at]),
      last_failure_ago: TimeUtils.format_time_ago(health[:last_failure_at]),
      last_failure_reason: health[:last_failure_reason],
      total_successes: health[:total_successes],
      total_failures: health[:total_failures],
      total_timeouts: health[:total_timeouts],
      recovery_attempts: health[:recovery_attempts],
      failed_kills: format_failed_kills(health[:failed_kills]),
      ratelimiter: extract_ratelimiter_info(health[:diagnostics])
    }
  end

  defp format_failed_kills(nil), do: []

  defp format_failed_kills(failed_kills) when is_list(failed_kills) do
    Enum.map(failed_kills, fn kill ->
      %{
        killmail_id: kill[:killmail_id],
        reason: format_failure_reason(kill[:reason]),
        failed_at: format_datetime(kill[:failed_at]),
        failed_ago: TimeUtils.format_time_ago(kill[:failed_at])
      }
    end)
  end

  defp format_failure_reason(:timeout), do: "timeout"
  defp format_failure_reason({:format_error, reason}), do: "format_error: #{inspect(reason)}"
  defp format_failure_reason(reason), do: inspect(reason)

  defp extract_ratelimiter_info(nil), do: %{}

  defp extract_ratelimiter_info(diagnostics) do
    ratelimiter = diagnostics[:ratelimiter] || %{}

    %{
      exists: ratelimiter[:exists],
      state: ratelimiter[:state_name] || ratelimiter[:status],
      connection: ratelimiter[:connection],
      queues: ratelimiter[:queue_lengths]
    }
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
        time_ago: TimeUtils.format_time_ago(timestamp)
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
      cache_name = WandererNotifier.Infrastructure.Cache.cache_name()
      get_cache_stats_for_process(cache_name)
    rescue
      error ->
        Logger.error("Exception getting cache stats: #{inspect(error)}")

        empty_cache_stats()
    end
  end

  defp get_cache_stats_for_process(cache_name) do
    case Process.whereis(cache_name) do
      nil ->
        Logger.debug("Cache process not found with name: #{inspect(cache_name)}")
        handle_missing_cache_process(cache_name)

      pid ->
        Logger.debug("Cache process found: #{inspect(cache_name)} -> #{inspect(pid)}")
        fetch_cachex_stats(cache_name)
    end
  end

  defp handle_missing_cache_process(cache_name) do
    Logger.warning("Cache process not found: #{cache_name}")
    empty_cache_stats()
  end

  defp fetch_cachex_stats(cache_name) do
    case Cachex.stats(cache_name) do
      {:ok, stats} ->
        Logger.debug("Raw cache stats: #{inspect(stats)}")
        build_cache_stats_from_cachex(stats, cache_name)

      {:error, reason} ->
        Logger.debug("Cache stats error: #{inspect(reason)}")
        handle_cachex_error(reason)
    end
  end

  defp build_cache_stats_from_cachex(stats, cache_name) do
    # Cachex stats returns a map with :hits, :misses, etc.
    # Access them as map keys, not struct fields
    hits = Map.get(stats, :hits, 0)
    misses = Map.get(stats, :misses, 0)
    writes = Map.get(stats, :writes, 0)

    %{
      hits: hits,
      misses: misses,
      hit_rate: calculate_hit_rate(hits, misses),
      evictions: Map.get(stats, :evictions, 0),
      expirations: Map.get(stats, :expirations, 0),
      writes: writes,
      size: get_cache_size(cache_name)
    }
  end

  defp handle_cachex_error(reason) do
    # Don't warn for expected errors like stats_disabled
    if reason != :stats_disabled do
      Logger.warning("Failed to get cache stats: #{inspect(reason)}")
    end

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
      {"Pipeline Worker", WandererNotifier.Domains.Killmail.PipelineWorker}
    ]

    # Get standard processes
    standard_processes =
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

    # Add SSE client info
    sse_process = get_sse_client_process_info()

    standard_processes ++ [sse_process]
  end

  defp get_sse_client_process_info do
    try do
      map_name = WandererNotifier.Shared.Config.map_name()
      # If map_name is configured, it will have a value; if not, get_required will raise
      # Try to find SSE client via Registry
      case Registry.lookup(WandererNotifier.Registry, {:sse_client, map_name}) do
        [{pid, _}] ->
          info = Process.info(pid)
          memory_kb = div(info[:memory] || 0, 1024)
          message_queue_len = info[:message_queue_len] || 0

          %{
            name: "SSE Client (#{map_name})",
            status: "running",
            memory_kb: memory_kb,
            message_queue_len: message_queue_len,
            heap_size: info[:heap_size] || 0
          }

        _ ->
          %{
            name: "SSE Client",
            status: "not_running",
            memory_kb: 0,
            message_queue_len: 0,
            heap_size: 0
          }
      end
    rescue
      _ ->
        # Config.map_name() raised because it's not configured
        %{
          name: "SSE Client",
          status: "not_configured",
          memory_kb: 0,
          message_queue_len: 0,
          heap_size: 0
        }
    end
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
        Logger.error("Failed to check server status",
          error: inspect(error),
          category: :kill,
          module: __MODULE__
        )

        false
    end
  end
end
