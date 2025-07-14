defmodule WandererNotifier.Api.Controllers.DashboardController do
  @moduledoc """
  Controller for the web dashboard.
  """
  use WandererNotifier.Api.ApiPipeline
  use WandererNotifier.Api.Controllers.ControllerHelpers

  alias WandererNotifier.Api.Controllers.SystemInfo

  # Dashboard endpoint - renders HTML
  get "/" do
    # Get the same data as /health/details plus extended stats
    detailed_status = SystemInfo.collect_extended_status()

    # Render HTML
    html = render_dashboard(detailed_status)

    conn
    |> put_resp_content_type("text/html")
    |> send_resp(200, html)
  end

  defp render_dashboard(data) do
    uptime_formatted = format_uptime(data.system.uptime_seconds)
    refresh_interval = get_refresh_interval()

    """
    <!DOCTYPE html>
    <html lang="en">
    <head>
        #{render_head()}
        <style>
            * {
                margin: 0;
                padding: 0;
                box-sizing: border-box;
            }

            body {
                font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Oxygen, Ubuntu, Cantarell, sans-serif;
                background-color: #0f172a;
                color: #e2e8f0;
                line-height: 1.6;
                padding: 2rem;
            }

            .container {
                max-width: 1200px;
                margin: 0 auto;
            }

            .header {
                text-align: center;
                margin-bottom: 3rem;
            }

            .header h1 {
                font-size: 2.5rem;
                color: #60a5fa;
                margin-bottom: 0.5rem;
            }

            .header p {
                color: #94a3b8;
                font-size: 1.1rem;
            }

            .grid {
                display: grid;
                grid-template-columns: repeat(auto-fit, minmax(350px, 1fr));
                gap: 2rem;
                margin-bottom: 2rem;
            }

            .card {
                background-color: #1e293b;
                border-radius: 12px;
                padding: 1.5rem;
                box-shadow: 0 4px 6px rgba(0, 0, 0, 0.3);
                border: 1px solid #334155;
            }

            .card h2 {
                color: #60a5fa;
                font-size: 1.5rem;
                margin-bottom: 1rem;
                display: flex;
                align-items: center;
                gap: 0.5rem;
            }

            .card h2::before {
                content: '';
                display: inline-block;
                width: 4px;
                height: 20px;
                background-color: #60a5fa;
                border-radius: 2px;
            }

            .info-row {
                display: flex;
                justify-content: space-between;
                padding: 0.75rem 0;
                border-bottom: 1px solid #334155;
            }

            .info-row:last-child {
                border-bottom: none;
            }

            .info-label {
                color: #94a3b8;
            }

            .info-value {
                color: #e2e8f0;
                font-weight: 500;
            }

            .status-badge {
                display: inline-block;
                padding: 0.25rem 0.75rem;
                border-radius: 9999px;
                font-size: 0.875rem;
                font-weight: 600;
            }

            .status-ok {
                background-color: #166534;
                color: #86efac;
            }

            .status-running {
                background-color: #166534;
                color: #86efac;
            }

            .status-stopped {
                background-color: #7f1d1d;
                color: #fca5a5;
            }
            
            .status-unknown {
                background-color: #44403c;
                color: #d6d3d1;
            }

            .progress-bar {
                width: 100%;
                height: 8px;
                background-color: #334155;
                border-radius: 4px;
                overflow: hidden;
                margin-top: 0.5rem;
            }

            .progress-fill {
                height: 100%;
                background-color: #60a5fa;
                transition: width 0.3s ease;
            }

            .progress-fill.high {
                background-color: #ef4444;
            }

            .progress-fill.medium {
                background-color: #f59e0b;
            }

            .metric-box {
                background: linear-gradient(135deg, #1e293b 0%, #334155 100%);
                border-radius: 8px;
                padding: 1rem;
                margin: 0.5rem 0;
                border-left: 4px solid #60a5fa;
                transition: all 0.3s ease;
            }

            .metric-box:hover {
                transform: translateY(-2px);
                box-shadow: 0 8px 12px rgba(0, 0, 0, 0.4);
            }

            .metric-value {
                font-size: 1.5rem;
                font-weight: 700;
                color: #60a5fa;
                margin-bottom: 0.25rem;
            }

            .metric-label {
                font-size: 0.875rem;
                color: #94a3b8;
                text-transform: uppercase;
                letter-spacing: 0.5px;
            }

            .health-indicator {
                display: inline-block;
                width: 12px;
                height: 12px;
                border-radius: 50%;
                margin-right: 0.5rem;
                animation: pulse 2s infinite;
            }

            .health-good {
                background-color: #10b981;
            }

            .health-warning {
                background-color: #f59e0b;
            }

            .health-error {
                background-color: #ef4444;
            }

            @keyframes pulse {
                0% {
                    opacity: 1;
                }
                50% {
                    opacity: 0.5;
                }
                100% {
                    opacity: 1;
                }
            }

            .chart-container {
                margin-top: 1rem;
                height: 100px;
                background: #0f172a;
                border-radius: 8px;
                padding: 1rem;
                border: 1px solid #334155;
            }

            .mini-chart {
                width: 100%;
                height: 60px;
                background: linear-gradient(to right, #1e293b, #334155);
                border-radius: 4px;
                position: relative;
                overflow: hidden;
            }

            .chart-bar {
                position: absolute;
                bottom: 0;
                background: linear-gradient(to top, #60a5fa, #3b82f6);
                width: 8px;
                margin-right: 2px;
                border-radius: 2px 2px 0 0;
            }

            .alert-box {
                background: rgba(239, 68, 68, 0.1);
                border: 1px solid #ef4444;
                border-radius: 8px;
                padding: 1rem;
                margin: 1rem 0;
                color: #fca5a5;
            }

            .success-box {
                background: rgba(16, 185, 129, 0.1);
                border: 1px solid #10b981;
                border-radius: 8px;
                padding: 1rem;
                margin: 1rem 0;
                color: #86efac;
            }

            .recent-activity {
                max-height: 200px;
                overflow-y: auto;
                background: #0f172a;
                border-radius: 8px;
                padding: 1rem;
                margin-top: 1rem;
            }

            .activity-item {
                padding: 0.5rem;
                border-bottom: 1px solid #334155;
                font-size: 0.875rem;
            }

            .activity-item:last-child {
                border-bottom: none;
            }

            .activity-time {
                color: #64748b;
                font-size: 0.75rem;
            }

            .footer {
                text-align: center;
                color: #64748b;
                margin-top: 3rem;
                padding-top: 2rem;
                border-top: 1px solid #334155;
            }

            @media (max-width: 768px) {
                body {
                    padding: 1rem;
                }

                .header h1 {
                    font-size: 2rem;
                }

                .grid {
                    grid-template-columns: 1fr;
                }
            }
        </style>
    </head>
    <body>
        <div class="container">
            #{render_header()}

            #{render_health_overview(data)}

            <div class="grid">
                #{render_system_status_card(data, uptime_formatted)}

                #{render_web_server_card(data)}

                #{render_memory_card(data)}

                #{render_tracking_card(data)}

                #{render_notifications_card(data)}

                #{render_processing_card(data)}

                #{render_performance_card(data)}

                #{render_websocket_card(data)}

                #{render_realtime_metrics_card(data)}

                #{render_system_health_card(data)}

                #{render_recent_activity_card(data)}
            </div>

            #{render_footer(data)}
        </div>

        <script>
            // Auto-refresh with visual countdown
            let refreshInterval = #{refresh_interval};
            let countdown = refreshInterval / 1000;
            
            function updateCountdown() {
                const countdownElement = document.getElementById('refresh-countdown');
                if (countdownElement) {
                    countdownElement.textContent = `Refreshing in ${countdown}s`;
                }
                
                if (countdown <= 0) {
                    location.reload();
                } else {
                    countdown--;
                    setTimeout(updateCountdown, 1000);
                }
            }
            
            // Start countdown
            updateCountdown();
            
            // Add manual refresh button functionality
            function manualRefresh() {
                location.reload();
            }
            
            // Add keyboard shortcuts
            document.addEventListener('keydown', function(e) {
                if (e.key === 'r' && (e.ctrlKey || e.metaKey)) {
                    e.preventDefault();
                    manualRefresh();
                }
            });
        </script>
    </body>
    </html>
    """
  end

  defp format_uptime(seconds) do
    days = div(seconds, 86_400)
    hours = div(rem(seconds, 86_400), 3600)
    minutes = div(rem(seconds, 3600), 60)

    []
    |> then(fn parts -> if days > 0, do: ["#{days}d" | parts], else: parts end)
    |> then(fn parts -> if hours > 0, do: ["#{hours}h" | parts], else: parts end)
    |> then(fn parts -> if minutes > 0, do: ["#{minutes}m" | parts], else: parts end)
    |> Enum.reverse()
    |> Enum.join(" ")
    |> case do
      "" -> "< 1m"
      joined -> joined
    end
  end

  defp format_kb(kb) when kb >= 1024 * 1024 do
    gb = kb / (1024 * 1024)
    "#{Float.round(gb, 2)} GB"
  end

  defp format_kb(kb) when kb >= 1024 do
    mb = kb / 1024
    "#{Float.round(mb, 2)} MB"
  end

  defp format_kb(kb) do
    "#{kb} KB"
  end

  defp get_memory_class(percent) when percent >= 80, do: "high"
  defp get_memory_class(percent) when percent >= 60, do: "medium"
  defp get_memory_class(_), do: ""

  defp get_refresh_interval do
    Application.get_env(:wanderer_notifier, :dashboard_refresh_interval, 5000)
  end

  defp render_head do
    """
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Wanderer Notifier Dashboard</title>
    """
  end

  defp render_header do
    current_time = DateTime.utc_now() |> DateTime.to_string()

    """
    <div class="header">
        <h1>🚀 Wanderer Notifier Dashboard</h1>
        <p>System Status Overview • #{current_time} UTC</p>
    </div>
    """
  end

  defp render_system_status_card(data, uptime_formatted) do
    # Get detailed version info from git
    {git_version, git_commit} = get_git_version_info()

    """
    <div class="card">
        <h2>System Status</h2>
        <div class="info-row">
            <span class="info-label">Status</span>
            <span class="info-value">
                <span class="status-badge status-ok">#{data.status}</span>
            </span>
        </div>
        <div class="info-row">
            <span class="info-label">App Version</span>
            <span class="info-value">#{data.server_version}</span>
        </div>
        <div class="info-row">
            <span class="info-label">Git Version</span>
            <span class="info-value">#{git_version}</span>
        </div>
        <div class="info-row">
            <span class="info-label">Git Commit</span>
            <span class="info-value">#{git_commit}</span>
        </div>
        <div class="info-row">
            <span class="info-label">Uptime</span>
            <span class="info-value">#{uptime_formatted}</span>
        </div>
        <div class="info-row">
            <span class="info-label">Schedulers</span>
            <span class="info-value">#{data.system.scheduler_count}</span>
        </div>
    </div>
    """
  end

  defp render_web_server_card(data) do
    {status_class, status_text} =
      case data.web_server.running do
        true -> {"status-running", "Running"}
        false -> {"status-stopped", "Stopped"}
        :unknown -> {"status-unknown", "Unknown"}
      end

    """
    <div class="card">
        <h2>Web Server</h2>
        <div class="info-row">
            <span class="info-label">Status</span>
            <span class="info-value">
                <span class="status-badge #{status_class}">
                    #{status_text}
                </span>
            </span>
        </div>
        <div class="info-row">
            <span class="info-label">Bind Address</span>
            <span class="info-value">#{data.web_server.bind_address}</span>
        </div>
        <div class="info-row">
            <span class="info-label">Port</span>
            <span class="info-value">#{data.web_server.port}</span>
        </div>
    </div>
    """
  end

  defp render_memory_card(data) do
    """
    <div class="card">
        <h2>Memory Usage</h2>
        <div class="info-row">
            <span class="info-label">Total Memory</span>
            <span class="info-value">#{format_kb(data.system.memory.total_kb)}</span>
        </div>
        <div class="info-row">
            <span class="info-label">Processes</span>
            <span class="info-value">
                #{format_kb(data.system.memory.processes_kb)} (#{data.system.memory.processes_percent}%)
            </span>
        </div>
        <div class="progress-bar">
            <div class="progress-fill #{get_memory_class(data.system.memory.processes_percent)}"
                 style="width: #{data.system.memory.processes_percent}%"></div>
        </div>
        <div class="info-row" style="margin-top: 1rem;">
            <span class="info-label">System</span>
            <span class="info-value">
                #{format_kb(data.system.memory.system_kb)} (#{data.system.memory.system_percent}%)
            </span>
        </div>
        <div class="progress-bar">
            <div class="progress-fill #{get_memory_class(data.system.memory.system_percent)}"
                 style="width: #{data.system.memory.system_percent}%"></div>
        </div>
    </div>
    """
  end

  defp render_tracking_card(data) do
    """
    <div class="card">
        <h2>Tracking</h2>
        <div class="info-row">
            <span class="info-label">Systems Tracked</span>
            <span class="info-value">#{data.tracking.systems_count}</span>
        </div>
        <div class="info-row">
            <span class="info-label">Characters Tracked</span>
            <span class="info-value">#{data.tracking.characters_count}</span>
        </div>
        <div class="info-row">
            <span class="info-label">Killmails Received</span>
            <span class="info-value">#{data.tracking.killmails_received}</span>
        </div>
    </div>
    """
  end

  defp render_notifications_card(data) do
    """
    <div class="card">
        <h2>Notifications Sent</h2>
        <div class="info-row">
            <span class="info-label">Total</span>
            <span class="info-value">#{data.notifications.total}</span>
        </div>
        <div class="info-row">
            <span class="info-label">Kill Notifications</span>
            <span class="info-value">#{data.notifications.kills}</span>
        </div>
        <div class="info-row">
            <span class="info-label">System Notifications</span>
            <span class="info-value">#{data.notifications.systems}</span>
        </div>
        <div class="info-row">
            <span class="info-label">Character Notifications</span>
            <span class="info-value">#{data.notifications.characters}</span>
        </div>
    </div>
    """
  end

  defp render_processing_card(data) do
    processing = data.processing

    """
    <div class="card">
        <h2>Processing Stats</h2>
        <div class="info-row">
            <span class="info-label">Kills Processed</span>
            <span class="info-value">#{processing.kills_processed}</span>
        </div>
        <div class="info-row">
            <span class="info-label">Kills Notified</span>
            <span class="info-value">#{processing.kills_notified}</span>
        </div>
        <div class="info-row">
            <span class="info-label">Processing Started</span>
            <span class="info-value">#{processing.processing_start}</span>
        </div>
        <div class="info-row">
            <span class="info-label">Processing Complete</span>
            <span class="info-value">#{processing.processing_complete}</span>
        </div>
        <div class="info-row">
            <span class="info-label">Processing Success</span>
            <span class="info-value">#{processing.processing_complete_success}</span>
        </div>
        <div class="info-row">
            <span class="info-label">Processing Errors</span>
            <span class="info-value">#{processing.processing_complete_error}</span>
        </div>
        <div class="info-row">
            <span class="info-label">Processing Skipped</span>
            <span class="info-value">#{processing.processing_skipped}</span>
        </div>
    </div>
    """
  end

  defp render_footer(data) do
    """
    <div class="footer">
        <p>Last updated: #{data.timestamp}</p>
        <p id="refresh-countdown">Refreshing...</p>
        <p>
            <button onclick="manualRefresh()" style="background: #60a5fa; color: white; border: none; padding: 0.5rem 1rem; border-radius: 4px; cursor: pointer; margin-right: 0.5rem;">Refresh Now</button>
            <span style="color: #64748b; font-size: 0.875rem;">Press Ctrl+R for manual refresh</span>
        </p>
    </div>
    """
  end

  defp render_performance_card(data) do
    performance = data.performance

    """
    <div class="card">
        <h2>Performance Metrics</h2>
        <div class="info-row">
            <span class="info-label">Success Rate</span>
            <span class="info-value">#{performance.success_rate}%</span>
        </div>
        <div class="info-row">
            <span class="info-label">Notification Rate</span>
            <span class="info-value">#{performance.notification_rate}%</span>
        </div>
        <div class="info-row">
            <span class="info-label">Processing Efficiency</span>
            <span class="info-value">#{performance.processing_efficiency}%</span>
        </div>
        <div class="info-row">
            <span class="info-label">Last Activity</span>
            <span class="info-value">#{performance.last_activity}</span>
        </div>
    </div>
    """
  end

  defp render_websocket_card(data) do
    websocket = data.websocket

    {status_class, status_text} =
      case websocket.client_alive do
        true -> {"status-running", "Connected"}
        false -> {"status-stopped", "Disconnected"}
      end

    health_class = if websocket.client_alive, do: "health-good", else: "health-error"

    """
    <div class="card">
        <h2><span class="health-indicator #{health_class}"></span>WebSocket Client</h2>
        <div class="info-row">
            <span class="info-label">Status</span>
            <span class="info-value">
                <span class="status-badge #{status_class}">#{status_text}</span>
            </span>
        </div>
        <div class="info-row">
            <span class="info-label">Connection</span>
            <span class="info-value">#{websocket.connection_status}</span>
        </div>
        <div class="info-row">
            <span class="info-label">Killmails Received</span>
            <span class="info-value">#{data.tracking.killmails_received}</span>
        </div>
    </div>
    """
  end

  defp render_health_overview(data) do
    system_health = calculate_system_health(data)

    health_class =
      case system_health.status do
        :healthy -> "success-box"
        :warning -> "alert-box"
        :critical -> "alert-box"
      end

    """
    <div class="#{health_class}">
        <h3>System Health: #{String.upcase(to_string(system_health.status))}</h3>
        <p>#{system_health.message}</p>
        #{if system_health.issues != [], do: "<ul>#{Enum.map(system_health.issues, &"<li>#{&1}</li>") |> Enum.join()}</ul>", else: ""}
    </div>
    """
  end

  defp render_realtime_metrics_card(data) do
    processing = data.processing

    """
    <div class="card">
        <h2>Real-time Metrics</h2>
        <div class="metric-box">
            <div class="metric-value">#{processing.kills_processed}</div>
            <div class="metric-label">Total Processed</div>
        </div>
        <div class="metric-box">
            <div class="metric-value">#{processing.kills_notified}</div>
            <div class="metric-label">Notifications Sent</div>
        </div>
        <div class="metric-box">
            <div class="metric-value">#{data.performance.success_rate}%</div>
            <div class="metric-label">Success Rate</div>
        </div>
        <div class="chart-container">
            <div class="mini-chart">
                #{render_activity_chart(data)}
            </div>
        </div>
    </div>
    """
  end

  defp render_system_health_card(data) do
    memory_usage = data.system.memory.processes_percent + data.system.memory.system_percent
    uptime_hours = div(data.system.uptime_seconds, 3600)

    """
    <div class="card">
        <h2>System Health</h2>
        <div class="info-row">
            <span class="info-label">Memory Usage</span>
            <span class="info-value">#{Float.round(memory_usage, 1)}%</span>
        </div>
        <div class="progress-bar">
            <div class="progress-fill #{get_memory_health_class(memory_usage)}"
                 style="width: #{memory_usage}%"></div>
        </div>
        <div class="info-row" style="margin-top: 1rem;">
            <span class="info-label">Uptime</span>
            <span class="info-value">#{uptime_hours} hours</span>
        </div>
        <div class="info-row">
            <span class="info-label">Processing Health</span>
            <span class="info-value">#{get_processing_health_status(data.processing)}</span>
        </div>
    </div>
    """
  end

  defp render_activity_chart(data) do
    # Simple visualization bars based on recent activity
    kills_processed = data.processing.kills_processed
    max_height = 50

    # Create 10 bars with some sample data (in real implementation, you'd use actual time-series data)
    bars =
      for i <- 1..10 do
        height = rem(kills_processed + i * 7, max_height) + 5
        left_position = (i - 1) * 10
        "<div class='chart-bar' style='left: #{left_position}%; height: #{height}px;'></div>"
      end

    Enum.join(bars)
  end

  defp calculate_system_health(data) do
    issues = []

    issues = check_websocket_health(data.websocket, issues)
    issues = check_memory_health(data.system.memory, issues)
    issues = check_processing_health(data.processing, issues)

    {status, message} = determine_overall_health(issues)

    %{
      status: status,
      message: message,
      issues: issues
    }
  end

  defp check_websocket_health(websocket, issues) do
    if websocket.client_alive do
      issues
    else
      ["WebSocket client disconnected" | issues]
    end
  end

  defp check_memory_health(memory, issues) do
    memory_usage = memory.processes_percent + memory.system_percent

    if memory_usage > 80 do
      ["High memory usage (#{Float.round(memory_usage, 1)}%)" | issues]
    else
      issues
    end
  end

  defp check_processing_health(processing, issues) do
    processing_errors = processing.processing_complete_error
    processing_success = processing.processing_complete_success

    if processing_errors > 0 and processing_success == 0 do
      ["Processing errors detected" | issues]
    else
      issues
    end
  end

  defp determine_overall_health(issues) do
    case length(issues) do
      0 -> {:healthy, "All systems operational"}
      1 -> {:warning, "Minor issues detected"}
      _ -> {:critical, "Multiple issues require attention"}
    end
  end

  defp get_memory_health_class(usage) when usage >= 90, do: "high"
  defp get_memory_health_class(usage) when usage >= 70, do: "medium"
  defp get_memory_health_class(_), do: ""

  defp get_processing_health_status(processing) do
    success = processing.processing_complete_success
    errors = processing.processing_complete_error

    cond do
      success == 0 and errors == 0 -> "No activity"
      errors == 0 -> "Healthy"
      success > errors * 10 -> "Good"
      success > errors -> "Warning"
      true -> "Critical"
    end
  end

  defp render_recent_activity_card(data) do
    activities = Map.get(data, :recent_activity, [])

    activity_items =
      activities
      |> Enum.map(fn activity ->
        icon = get_activity_icon(activity.type)
        color = get_activity_color(activity.type)

        """
        <div class="activity-item">
            <span style="color: #{color};">#{icon}</span>
            #{activity.message}
            <div class="activity-time">#{activity.time_ago}</div>
        </div>
        """
      end)
      |> Enum.join()

    """
    <div class="card">
        <h2>Recent Activity</h2>
        <div class="recent-activity">
            #{if Enum.empty?(activities), do: "<p style='color: #64748b; text-align: center; padding: 2rem;'>No recent activity</p>", else: activity_items}
        </div>
    </div>
    """
  end

  defp get_activity_icon(type) do
    case type do
      :info -> "📝"
      :websocket -> "🔌"
      :websocket_error -> "⚠️"
      :error -> "❌"
      :success -> "✅"
      _ -> "📊"
    end
  end

  defp get_activity_color(type) do
    case type do
      :info -> "#60a5fa"
      :websocket -> "#10b981"
      :websocket_error -> "#f59e0b"
      :error -> "#ef4444"
      :success -> "#10b981"
      _ -> "#94a3b8"
    end
  end

  defp get_git_version_info do
    try do
      # Try to get the latest git tag
      {git_version, 0} =
        System.cmd("git", ["describe", "--tags", "--abbrev=0"], stderr_to_stdout: true)

      git_version = String.trim(git_version)

      # Try to get the current commit hash
      {git_commit, 0} =
        System.cmd("git", ["rev-parse", "--short", "HEAD"], stderr_to_stdout: true)

      git_commit = String.trim(git_commit)

      {git_version, git_commit}
    rescue
      _ -> {"unknown", "unknown"}
    end
  end

  match _ do
    send_error(conn, 404, "not_found")
  end
end
