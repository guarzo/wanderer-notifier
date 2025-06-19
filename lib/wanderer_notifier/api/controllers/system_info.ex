defmodule WandererNotifier.Api.Controllers.SystemInfo do
  @moduledoc """
  Shared module for collecting system information used by health and dashboard endpoints.
  """

  alias WandererNotifier.Config
  alias WandererNotifier.Web.Server
  alias WandererNotifier.Utils.TimeUtils

  @doc """
  Collects detailed system information including server status, memory usage, and uptime.
  """
  def collect_detailed_status do
    web_server_status =
      try do
        Server.running?()
      rescue
        # Assume running if we can't check
        _ -> true
      end

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
        memory: %{
          total_kb: div(memory_info[:total], 1024),
          processes_kb: div(memory_info[:processes], 1024),
          system_kb: div(memory_info[:system], 1024),
          processes_percent: Float.round(memory_info[:processes] / memory_info[:total] * 100, 1),
          system_percent: Float.round(memory_info[:system] / memory_info[:total] * 100, 1)
        },
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
      processing: extract_processing_stats(stats)
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

    %{
      kills_processed: processing[:kills_processed] || 0,
      kills_notified: processing[:kills_notified] || 0
    }
  end
end
