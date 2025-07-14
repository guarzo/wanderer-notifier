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
                background-color: #1e293b;
                border-radius: 12px;
                padding: 2rem;
                box-shadow: 0 4px 6px rgba(0, 0, 0, 0.3);
                border: 1px solid #334155;
            }

            .header h1 {
                font-size: 2.5rem;
                color: #60a5fa;
                margin-bottom: 1rem;
            }

            .header-status {
                color: #e2e8f0;
                font-size: 1rem;
                display: flex;
                justify-content: center;
                align-items: center;
                flex-wrap: wrap;
                gap: 1.5rem;
                margin-top: 1rem;
            }

            .status-item {
                white-space: nowrap;
                background: rgba(96, 165, 250, 0.1);
                padding: 0.5rem 1rem;
                border-radius: 6px;
                border: 1px solid rgba(96, 165, 250, 0.3);
                transition: all 0.3s ease;
            }

            .status-item:hover {
                background: rgba(96, 165, 250, 0.2);
                transform: translateY(-1px);
            }

            .status-divider {
                display: none;
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
                transition: all 0.3s ease;
            }

            .card:hover {
                transform: translateY(-2px);
                box-shadow: 0 8px 12px rgba(0, 0, 0, 0.4);
                border-color: #475569;
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

            .memory-grid {
                display: grid;
                grid-template-columns: repeat(auto-fit, minmax(200px, 1fr));
                gap: 1rem;
                margin-top: 1rem;
            }

            .memory-item {
                background: #0f172a;
                padding: 1rem;
                border-radius: 8px;
                border: 1px solid #334155;
            }

            .memory-label {
                font-size: 0.875rem;
                color: #94a3b8;
                margin-bottom: 0.25rem;
            }

            .memory-value {
                font-size: 1.25rem;
                font-weight: 600;
                color: #e2e8f0;
            }

            .memory-warning {
                color: #f59e0b !important;
            }

            .memory-critical {
                color: #ef4444 !important;
            }

            .process-table {
                width: 100%;
                border-collapse: collapse;
                margin-top: 1rem;
            }

            .process-table th,
            .process-table td {
                padding: 0.75rem;
                text-align: left;
                border-bottom: 1px solid #334155;
            }

            .process-table th {
                background: #0f172a;
                color: #94a3b8;
                font-weight: 600;
                font-size: 0.875rem;
            }

            .process-table td {
                color: #e2e8f0;
                font-size: 0.875rem;
            }

            .process-status-running {
                color: #10b981;
            }

            .process-status-not_running {
                color: #ef4444;
            }

            .large-number {
                font-size: 1.5rem;
                font-weight: 700;
                color: #60a5fa;
            }

            .warning-threshold {
                color: #f59e0b;
            }

            .critical-threshold {
                color: #ef4444;
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
            #{render_header(data, uptime_formatted)}

            <div class="grid">
                #{render_system_health_card(data)}

                #{render_tracking_card(data)}

                #{render_notifications_card(data)}

                #{render_performance_card(data)}

                #{render_cache_stats_card(data)}
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

  defp format_time(datetime) do
    # Format time as HH:MM:SS
    datetime
    |> DateTime.to_time()
    |> Time.to_string()
    |> String.split(".")
    |> List.first()
  end


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

  defp render_header(data, uptime_formatted) do
    current_time = DateTime.utc_now()

    # Determine WebSocket status
    websocket_status = if data.websocket.client_alive, do: "🟢 Connected", else: "🔴 Disconnected"

    """
    <div class="header">
        <h1>🚀 Wanderer Notifier Dashboard</h1>
        <div class="header-status">
            <span class="status-item">📦 v#{data.server_version}</span>
            <span class="status-item">⏱️ Uptime: #{uptime_formatted}</span>
            <span class="status-item">🔌 Port: #{data.web_server.port}</span>
            <span class="status-item">#{websocket_status}</span>
            <span class="status-item">🕐 #{format_time(current_time)}</span>
        </div>
    </div>
    """
  end


  defp render_tracking_card(data) do
    """
    <div class="card">
        <h2>📡 Tracking</h2>
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
        <h2>📬 Notifications Sent</h2>
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

    # Format metrics with better display for zero values
    success_rate = if performance.success_rate == 0.0, do: "No data", else: "#{performance.success_rate}%"
    notification_rate = if performance.notification_rate == 0.0, do: "No data", else: "#{performance.notification_rate}%"
    processing_efficiency = if performance.processing_efficiency == 0.0, do: "No data", else: "#{performance.processing_efficiency}%"

    """
    <div class="card">
        <h2>📊 Performance Metrics</h2>
        <div class="info-row">
            <span class="info-label">Success Rate</span>
            <span class="info-value">#{success_rate}</span>
        </div>
        <div class="info-row">
            <span class="info-label">Notification Rate</span>
            <span class="info-value">#{notification_rate}</span>
        </div>
        <div class="info-row">
            <span class="info-label">Processing Efficiency</span>
            <span class="info-value">#{processing_efficiency}</span>
        </div>
        <div class="info-row">
            <span class="info-label">Last Activity</span>
            <span class="info-value">#{performance.last_activity}</span>
        </div>
    </div>
    """
  end







  defp render_cache_stats_card(data) do
    cache = data.cache_stats

    # Add a note if cache stats are all zeros
    stats_note = if cache.hits == 0 && cache.misses == 0 && cache.size == 0 do
      "<div class=\"info-row\" style=\"background: rgba(245, 158, 11, 0.1); padding: 0.75rem; border-radius: 6px; margin-bottom: 1rem;\">\n            <span style=\"color: #f59e0b; font-size: 0.875rem;\">\u26a0️ Cache stats require app restart to enable</span>\n        </div>"
    else
      ""
    end

    """
    <div class="card">
        <h2>💾 Cache Statistics</h2>
        #{stats_note}
        <div class="info-row">
            <span class="info-label">Hit Rate</span>
            <span class="info-value #{get_hit_rate_class(cache.hit_rate)}">#{cache.hit_rate}%</span>
        </div>
        <div class="progress-bar">
            <div class="progress-fill #{get_hit_rate_class(cache.hit_rate)}"
                 style="width: #{cache.hit_rate}%"></div>
        </div>
        <div class="info-row">
            <span class="info-label">Cache Size</span>
            <span class="info-value">#{cache.size} entries</span>
        </div>
        <div class="info-row">
            <span class="info-label">Hits / Misses</span>
            <span class="info-value">#{cache.hits} / #{cache.misses}</span>
        </div>
        <div class="info-row">
            <span class="info-label">Evictions</span>
            <span class="info-value #{get_eviction_class(cache.evictions)}">#{cache.evictions}</span>
        </div>
        <div class="info-row">
            <span class="info-label">Expirations</span>
            <span class="info-value">#{cache.expirations}</span>
        </div>
    </div>
    """
  end


  defp get_hit_rate_class(hit_rate) do
    cond do
      hit_rate >= 80 -> ""
      hit_rate >= 60 -> "medium"
      true -> "high"
    end
  end

  defp get_eviction_class(evictions) do
    cond do
      evictions >= 1000 -> "critical-threshold"
      evictions >= 100 -> "warning-threshold"
      true -> ""
    end
  end



  defp render_system_health_card(data) do
    # Use the higher of the two memory percentages, not the sum
    memory_usage = max(data.system.memory.processes_percent, data.system.memory.system_percent)

    # Determine health status
    health_class = cond do
      memory_usage >= 80 -> "health-error"
      memory_usage >= 60 -> "health-warning"
      true -> "health-good"
    end

    memory_mb = Float.round((data.system.memory.total_kb || 0) / 1024, 1)

    """
    <div class="card">
        <h2><span class="health-indicator #{health_class}"></span>System Health</h2>
        <div class="info-row">
            <span class="info-label">Memory Usage</span>
            <span class="info-value">#{Float.round(memory_usage, 1)}%</span>
        </div>
        <div class="progress-bar">
            <div class="progress-fill #{get_memory_health_class(memory_usage)}"
                 style="width: #{memory_usage}%"></div>
        </div>
        <div class="info-row" style="margin-top: 1rem;">
            <span class="info-label">Total Memory</span>
            <span class="info-value">#{memory_mb} MB</span>
        </div>
        <div class="info-row">
            <span class="info-label">CPU Cores</span>
            <span class="info-value">#{data.system.scheduler_count}</span>
        </div>
    </div>
    """
  end

  defp get_memory_health_class(usage) when usage >= 90, do: "high"
  defp get_memory_health_class(usage) when usage >= 70, do: "medium"
  defp get_memory_health_class(_), do: ""

  match _ do
    send_error(conn, 404, "not_found")
  end
end
