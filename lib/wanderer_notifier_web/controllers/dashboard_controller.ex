defmodule WandererNotifierWeb.DashboardController do
  @moduledoc """
  Phoenix controller for the web dashboard.
  """
  use WandererNotifierWeb, :controller

  alias WandererNotifier.Api.Controllers.SystemInfo

  def index(conn, _params) do
    # Get the same data as /health/details plus extended stats
    detailed_status = SystemInfo.collect_extended_status()
    refresh_interval = Application.get_env(:wanderer_notifier, :dashboard_refresh_interval, 30)

    # Since we don't have Phoenix.HTML, render a simple HTML response
    html_content = build_dashboard_html(detailed_status, refresh_interval)

    conn
    |> put_resp_content_type("text/html")
    |> send_resp(200, html_content)
  end

  defp build_dashboard_html(data, refresh_interval) do
    """
    <!DOCTYPE html>
    <html lang="en">
    <head>
        <meta charset="UTF-8">
        <meta name="viewport" content="width=device-width, initial-scale=1.0">
        <meta http-equiv="refresh" content="#{refresh_interval}">
        <title>Wanderer Notifier Dashboard</title>
        <link rel="stylesheet" href="/css/dashboard.css">
    </head>
    <body>
        <div class="container">
            #{render_header(data)}
            <main class="content">
                #{render_connection_status(data)}
                #{render_system_health(data)}
                #{render_processing_stats(data)}
                #{render_tracking_summary(data)}
                #{render_recent_activity(data)}
            </main>
            #{render_footer(refresh_interval)}
        </div>
        <script src="/js/dashboard.js"></script>
    </body>
    </html>
    """
  end

  defp render_header(data) do
    """
    <header class="header">
        <h1>Wanderer Notifier Dashboard</h1>
        <div class="header-stats">
            <div class="stat">
                <span class="label">Uptime</span>
                <span class="value">#{format_uptime(data.system.uptime_seconds)}</span>
            </div>
            <div class="stat">
                <span class="label">Version</span>
                <span class="value">#{data.version}</span>
            </div>
            <div class="stat">
                <span class="label">Environment</span>
                <span class="value">#{data.environment}</span>
            </div>
        </div>
    </header>
    """
  end

  defp render_connection_status(data) do
    """
    <section class="section">
        <h2>Connection Status</h2>
        <div class="grid">
            #{render_connection_card(data.connections.websocket)}
            #{render_connection_card(data.connections.sse)}
        </div>
    </section>
    """
  end

  defp render_connection_card(connection) do
    """
    <div class="connection-card">
        <div class="connection-header">
            <h3>#{String.upcase(to_string(connection.type))}</h3>
            <span class="status status-#{status_color(connection.status)}">
                #{connection.status}
            </span>
        </div>
        <div class="connection-body">
            <div class="metric">
                <span class="label">Quality</span>
                <span class="value text-#{status_color(connection.quality)}">
                    #{connection.quality}
                </span>
            </div>
            <div class="metric">
                <span class="label">Uptime</span>
                <span class="value text-#{percentage_color(connection.uptime_percentage)}">
                    #{connection.uptime_percentage}%
                </span>
            </div>
            <div class="metric">
                <span class="label">Connected Since</span>
                <span class="value">
                    #{format_timestamp(connection.connected_at)}
                </span>
            </div>
            <div class="metric">
                <span class="label">Last Heartbeat</span>
                <span class="value">
                    #{format_timestamp(connection.last_heartbeat)}
                </span>
            </div>
        </div>
    </div>
    """
  end

  defp render_system_health(data) do
    """
    <section class="section">
        <h2>System Health</h2>
        <div class="grid">
            #{render_health_metric("Memory Usage", data.system.memory_mb, "MB", 1024, memory_status(data.system.memory_mb))}
            #{render_health_metric("Process Count", data.system.process_count, "", 10000, process_status(data.system.process_count))}
            #{render_health_metric("Message Queue", data.system.message_queue_length, "", 1000, queue_status(data.system.message_queue_length))}
        </div>
    </section>
    """
  end

  defp render_health_metric(title, value, unit, max, status) do
    percentage = Kernel.min(100, value / max * 100)

    """
    <div class="health-metric">
        <div class="metric-header">
            <h4>#{title}</h4>
            <span class="badge badge-#{status}">#{status}</span>
        </div>
        <div class="metric-value">
            <span class="value">#{value}</span>
            <span class="unit">#{unit}</span>
        </div>
        <div class="progress-bar">
            <div class="progress-fill progress-#{status}" style="width: #{percentage}%"></div>
        </div>
    </div>
    """
  end

  defp render_processing_stats(data) do
    """
    <section class="section">
        <h2>Processing Statistics</h2>
        <div class="stats-grid">
            #{render_stat_card("Events Processed", data.metrics.events_processed)}
            #{render_stat_card("Notifications Sent", data.metrics.notifications_sent)}
            #{render_stat_card("Processing Rate", "#{data.metrics.processing_rate}/min")}
            #{render_stat_card("Success Rate", "#{data.metrics.success_rate}%")}
        </div>
    </section>
    """
  end

  defp render_stat_card(label, value) do
    """
    <div class="stat-card">
        <div class="stat-label">#{label}</div>
        <div class="stat-value">#{value}</div>
    </div>
    """
  end

  defp render_tracking_summary(data) do
    """
    <section class="section">
        <h2>Tracking Summary</h2>
        <div class="tracking-grid">
            <div class="tracking-card">
                <h3>Systems</h3>
                <div class="tracking-stats">
                    <div>Total: #{data.tracking.total_systems}</div>
                    <div>Priority: #{data.tracking.priority_systems}</div>
                    <div>K-Space: #{if data.tracking.kspace_enabled, do: "Enabled", else: "Disabled"}</div>
                </div>
            </div>
            <div class="tracking-card">
                <h3>Characters</h3>
                <div class="tracking-stats">
                    <div>Total: #{data.tracking.total_characters}</div>
                    <div>Active: #{data.tracking.active_characters}</div>
                </div>
            </div>
        </div>
    </section>
    """
  end

  defp render_recent_activity(data) do
    events_html =
      data.recent_events
      |> Enum.take(10)
      |> Enum.map(&render_activity_item/1)
      |> Enum.join("")

    events_html =
      if events_html == "",
        do: ~s(<div class="empty-state">No recent activity</div>),
        else: events_html

    """
    <section class="section">
        <h2>Recent Activity</h2>
        <div class="activity-list">
            #{events_html}
        </div>
    </section>
    """
  end

  defp render_activity_item(event) do
    """
    <div class="activity-item">
        <div class="activity-timestamp">
            #{format_timestamp(event.timestamp)}
        </div>
        <div class="activity-content">
            <span class="activity-type activity-#{event.type}">
                #{event.type}
            </span>
            <span class="activity-message">
                #{event.message}
            </span>
        </div>
    </div>
    """
  end

  defp render_footer(refresh_interval) do
    """
    <footer class="footer">
        <div>Last updated: #{format_timestamp(DateTime.utc_now())}</div>
        <div>Auto-refresh: #{refresh_interval}s</div>
    </footer>
    """
  end

  # Helper functions
  defp format_uptime(seconds) when is_integer(seconds) do
    days = div(seconds, 86400)
    hours = div(rem(seconds, 86400), 3600)
    minutes = div(rem(seconds, 3600), 60)

    cond do
      days > 0 -> "#{days}d #{hours}h #{minutes}m"
      hours > 0 -> "#{hours}h #{minutes}m"
      true -> "#{minutes}m"
    end
  end

  defp format_uptime(_), do: "N/A"

  defp format_timestamp(%DateTime{} = timestamp) do
    format_relative_time(timestamp)
  end

  defp format_timestamp(timestamp) when is_binary(timestamp) do
    case DateTime.from_iso8601(timestamp) do
      {:ok, dt, _} -> format_relative_time(dt)
      _ -> timestamp
    end
  end

  defp format_timestamp(_), do: "N/A"

  defp format_relative_time(datetime) do
    now = DateTime.utc_now()
    diff_seconds = DateTime.diff(now, datetime, :second)

    cond do
      diff_seconds < 60 -> "#{diff_seconds}s ago"
      diff_seconds < 3600 -> "#{div(diff_seconds, 60)}m ago"
      diff_seconds < 86400 -> "#{div(diff_seconds, 3600)}h ago"
      true -> "#{div(diff_seconds, 86400)}d ago"
    end
  end

  defp status_color("connected"), do: "success"
  defp status_color("active"), do: "success"
  defp status_color("healthy"), do: "success"
  defp status_color("degraded"), do: "warning"
  defp status_color("connecting"), do: "warning"
  defp status_color("disconnected"), do: "error"
  defp status_color("failed"), do: "error"
  defp status_color(_), do: "muted"

  defp percentage_color(value) when is_number(value) do
    cond do
      value >= 90 -> "success"
      value >= 70 -> "warning"
      true -> "error"
    end
  end

  defp percentage_color(_), do: "muted"

  defp memory_status(mb) when is_number(mb) do
    cond do
      mb < 500 -> "healthy"
      mb < 800 -> "degraded"
      true -> "critical"
    end
  end

  defp memory_status(_), do: "unknown"

  defp process_status(count) when is_number(count) do
    cond do
      count < 5000 -> "healthy"
      count < 8000 -> "degraded"
      true -> "critical"
    end
  end

  defp process_status(_), do: "unknown"

  defp queue_status(length) when is_number(length) do
    cond do
      length < 100 -> "healthy"
      length < 500 -> "degraded"
      true -> "critical"
    end
  end

  defp queue_status(_), do: "unknown"
end
