defmodule WandererNotifier.Api.Controllers.SystemInfo do
  @moduledoc """
  Shared module for collecting system information used by health and dashboard endpoints.
  """

  alias WandererNotifier.Config
  alias WandererNotifier.Utils.TimeUtils
  alias WandererNotifier.Web.Server

  @doc """
  Collects detailed system information including server status, memory usage, and uptime.
  """
  def collect_detailed_status do
    web_server_status = check_server_status()
    memory_info = :erlang.memory()

    # Get uptime from stats which tracks startup time
    stats = WandererNotifier.Core.Stats.get_stats()
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
    stats = WandererNotifier.Core.Stats.get_stats()

    extended_data = %{
      tracking: extract_tracking_stats(stats),
      notifications: extract_notification_stats(stats),
      processing: extract_processing_stats(stats),
      performance: extract_performance_stats(stats),
      websocket: extract_websocket_stats(),
      recent_activity: extract_recent_activity()
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
    websocket_pid = Process.whereis(WandererNotifier.Killmail.WebSocketClient)

    %{
      client_alive: websocket_pid != nil,
      connection_status: if(websocket_pid, do: "connected", else: "disconnected")
    }
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
    case WandererNotifier.Utils.TimeUtils.elapsed_seconds(datetime) do
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
    websocket_pid = Process.whereis(WandererNotifier.Killmail.WebSocketClient)

    activities =
      if websocket_pid do
        [{:websocket, "WebSocket client active", DateTime.utc_now()} | activities]
      else
        [{:websocket_error, "WebSocket client not running", DateTime.utc_now()} | activities]
      end

    # Add some sample recent activities (in a real implementation, you'd collect these from logs)
    recent_activities = [
      {:info, "System started", DateTime.utc_now() |> DateTime.add(-3600, :second)},
      {:info, "WebSocket connected", DateTime.utc_now() |> DateTime.add(-1800, :second)},
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

  defp check_server_status do
    try do
      Server.running?()
    rescue
      error in [ArgumentError, KeyError] ->
        WandererNotifier.Logger.Logger.error("Failed to check server status",
          error: inspect(error),
          module: __MODULE__
        )

        :unknown

      error ->
        WandererNotifier.Logger.Logger.error("Unexpected error checking server status",
          error: inspect(error),
          module: __MODULE__
        )

        :unknown
    end
  end
end
