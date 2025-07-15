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

            :root {
                --bg-primary: #0a0f1b;
                --bg-secondary: #0f1823;
                --bg-card: #1a2332;
                --bg-hover: #202937;
                --border-color: #2a3441;
                --text-primary: #e8eaed;
                --text-secondary: #9ca3af;
                --text-muted: #6b7280;
                --accent-primary: #60a5fa;
                --accent-secondary: #3b82f6;
                --success: #10b981;
                --warning: #f59e0b;
                --error: #ef4444;
                --gradient-primary: linear-gradient(135deg, #60a5fa 0%, #3b82f6 100%);
                --gradient-dark: linear-gradient(135deg, #1a2332 0%, #0f1823 100%);
            }

            body {
                font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Oxygen, Ubuntu, Cantarell, sans-serif;
                background: var(--bg-primary);
                color: var(--text-primary);
                line-height: 1.6;
                min-height: 100vh;
                background-image: 
                    radial-gradient(circle at 20% 50%, rgba(96, 165, 250, 0.05) 0%, transparent 50%),
                    radial-gradient(circle at 80% 80%, rgba(59, 130, 246, 0.05) 0%, transparent 50%);
            }

            .container {
                max-width: 1600px;
                margin: 0 auto;
                padding: 2rem;
            }

            /* Header Styles */
            .header {
                background: var(--gradient-dark);
                border-radius: 20px;
                padding: 3rem;
                margin-bottom: 3rem;
                position: relative;
                overflow: hidden;
                border: 1px solid var(--border-color);
                box-shadow: 0 10px 30px rgba(0, 0, 0, 0.5);
            }

            .header::before {
                content: '';
                position: absolute;
                top: -50%;
                right: -50%;
                width: 200%;
                height: 200%;
                background: radial-gradient(circle, rgba(96, 165, 250, 0.1) 0%, transparent 70%);
                animation: rotate 20s linear infinite;
            }

            @keyframes rotate {
                from { transform: rotate(0deg); }
                to { transform: rotate(360deg); }
            }

            .header-content {
                position: relative;
                z-index: 1;
                text-align: center;
            }

            .header h1 {
                font-size: 3rem;
                font-weight: 800;
                background: var(--gradient-primary);
                -webkit-background-clip: text;
                -webkit-text-fill-color: transparent;
                margin-bottom: 1.5rem;
                letter-spacing: -0.02em;
            }

            .status-grid {
                display: grid;
                grid-template-columns: repeat(auto-fit, minmax(180px, 1fr));
                gap: 1rem;
                margin-top: 2rem;
            }

            .status-item {
                background: rgba(255, 255, 255, 0.03);
                border: 1px solid rgba(255, 255, 255, 0.1);
                border-radius: 12px;
                padding: 1rem;
                text-align: center;
                backdrop-filter: blur(10px);
                transition: all 0.3s ease;
            }

            .status-item:hover {
                background: rgba(255, 255, 255, 0.05);
                transform: translateY(-2px);
                box-shadow: 0 5px 15px rgba(0, 0, 0, 0.3);
            }

            .status-icon {
                font-size: 2rem;
                margin-bottom: 0.5rem;
                display: block;
            }

            .status-label {
                font-size: 0.75rem;
                color: var(--text-muted);
                text-transform: uppercase;
                letter-spacing: 0.05em;
                margin-bottom: 0.25rem;
            }

            .status-value {
                font-size: 1.25rem;
                font-weight: 600;
                color: var(--text-primary);
            }

            /* Main Grid */
            .main-grid {
                display: grid;
                grid-template-columns: repeat(12, 1fr);
                gap: 1.5rem;
                margin-bottom: 2rem;
            }

            .card {
                background: var(--bg-card);
                border-radius: 16px;
                padding: 2rem;
                border: 1px solid var(--border-color);
                box-shadow: 0 4px 20px rgba(0, 0, 0, 0.3);
                transition: all 0.3s ease;
                position: relative;
                overflow: hidden;
            }

            .card::before {
                content: '';
                position: absolute;
                top: 0;
                left: 0;
                right: 0;
                height: 3px;
                background: var(--gradient-primary);
                opacity: 0;
                transition: opacity 0.3s ease;
            }

            .card:hover {
                transform: translateY(-4px);
                box-shadow: 0 8px 30px rgba(0, 0, 0, 0.4);
                border-color: var(--accent-primary);
            }

            .card:hover::before {
                opacity: 1;
            }

            .card-small { grid-column: span 4; }
            .card-medium { grid-column: span 6; }
            .card-large { grid-column: span 8; }
            .card-full { grid-column: span 12; }

            .card-header {
                display: flex;
                align-items: center;
                justify-content: space-between;
                margin-bottom: 1.5rem;
            }

            .card-title {
                font-size: 1.25rem;
                font-weight: 600;
                color: var(--text-primary);
                display: flex;
                align-items: center;
                gap: 0.75rem;
            }

            .card-icon {
                width: 40px;
                height: 40px;
                background: var(--gradient-primary);
                border-radius: 10px;
                display: flex;
                align-items: center;
                justify-content: center;
                font-size: 1.25rem;
            }

            /* Metrics */
            .metric-grid {
                display: grid;
                grid-template-columns: repeat(auto-fit, minmax(150px, 1fr));
                gap: 1rem;
            }

            .metric-item {
                background: rgba(255, 255, 255, 0.02);
                border: 1px solid rgba(255, 255, 255, 0.05);
                border-radius: 12px;
                padding: 1.5rem;
                text-align: center;
                transition: all 0.3s ease;
            }

            .metric-item:hover {
                background: rgba(255, 255, 255, 0.04);
                transform: scale(1.02);
            }

            .metric-value {
                font-size: 2rem;
                font-weight: 700;
                background: var(--gradient-primary);
                -webkit-background-clip: text;
                -webkit-text-fill-color: transparent;
                margin-bottom: 0.5rem;
            }

            .metric-label {
                font-size: 0.875rem;
                color: var(--text-secondary);
            }

            /* Progress Bars */
            .progress-container {
                margin: 1rem 0;
            }

            .progress-header {
                display: flex;
                justify-content: space-between;
                margin-bottom: 0.5rem;
            }

            .progress-label {
                font-size: 0.875rem;
                color: var(--text-secondary);
            }

            .progress-value {
                font-size: 0.875rem;
                font-weight: 600;
                color: var(--text-primary);
            }

            .progress-bar {
                width: 100%;
                height: 10px;
                background: rgba(255, 255, 255, 0.1);
                border-radius: 10px;
                overflow: hidden;
                position: relative;
            }

            .progress-fill {
                height: 100%;
                background: var(--gradient-primary);
                border-radius: 10px;
                transition: width 0.5s ease;
                position: relative;
                overflow: hidden;
            }

            .progress-fill::after {
                content: '';
                position: absolute;
                top: 0;
                left: 0;
                bottom: 0;
                right: 0;
                background: linear-gradient(
                    90deg,
                    transparent,
                    rgba(255, 255, 255, 0.3),
                    transparent
                );
                animation: shimmer 2s infinite;
            }

            @keyframes shimmer {
                0% { transform: translateX(-100%); }
                100% { transform: translateX(100%); }
            }

            .progress-fill.warning {
                background: linear-gradient(135deg, var(--warning) 0%, #f59e0b 100%);
            }

            .progress-fill.danger {
                background: linear-gradient(135deg, var(--error) 0%, #ef4444 100%);
            }

            /* Status Indicators */
            .status-indicator {
                display: inline-flex;
                align-items: center;
                gap: 0.5rem;
                padding: 0.5rem 1rem;
                background: rgba(255, 255, 255, 0.05);
                border-radius: 20px;
                font-size: 0.875rem;
            }

            .status-dot {
                width: 8px;
                height: 8px;
                border-radius: 50%;
                animation: pulse 2s infinite;
            }

            .status-dot.success {
                background: var(--success);
                box-shadow: 0 0 10px var(--success);
            }

            .status-dot.warning {
                background: var(--warning);
                box-shadow: 0 0 10px var(--warning);
            }

            .status-dot.error {
                background: var(--error);
                box-shadow: 0 0 10px var(--error);
            }

            @keyframes pulse {
                0%, 100% { opacity: 1; }
                50% { opacity: 0.5; }
            }

            /* Charts */
            .chart-container {
                height: 200px;
                background: rgba(255, 255, 255, 0.02);
                border-radius: 12px;
                padding: 1rem;
                border: 1px solid rgba(255, 255, 255, 0.05);
                position: relative;
                overflow: hidden;
            }

            .chart-grid {
                position: absolute;
                inset: 0;
                background-image: 
                    linear-gradient(rgba(255, 255, 255, 0.03) 1px, transparent 1px),
                    linear-gradient(90deg, rgba(255, 255, 255, 0.03) 1px, transparent 1px);
                background-size: 20px 20px;
            }

            /* Info Lists */
            .info-list {
                display: flex;
                flex-direction: column;
                gap: 0.75rem;
            }

            .info-item {
                display: flex;
                justify-content: space-between;
                align-items: center;
                padding: 0.75rem;
                background: rgba(255, 255, 255, 0.02);
                border-radius: 8px;
                transition: all 0.2s ease;
            }

            .info-item:hover {
                background: rgba(255, 255, 255, 0.04);
            }

            .info-label {
                color: var(--text-secondary);
                font-size: 0.875rem;
            }

            .info-value {
                color: var(--text-primary);
                font-weight: 600;
                font-size: 0.875rem;
            }

            /* Activity Feed */
            .activity-feed {
                max-height: 300px;
                overflow-y: auto;
                padding-right: 0.5rem;
            }

            .activity-feed::-webkit-scrollbar {
                width: 6px;
            }

            .activity-feed::-webkit-scrollbar-track {
                background: rgba(255, 255, 255, 0.05);
                border-radius: 3px;
            }

            .activity-feed::-webkit-scrollbar-thumb {
                background: rgba(255, 255, 255, 0.1);
                border-radius: 3px;
            }

            .activity-item {
                padding: 1rem;
                margin-bottom: 0.75rem;
                background: rgba(255, 255, 255, 0.02);
                border-radius: 8px;
                border-left: 3px solid var(--accent-primary);
                transition: all 0.2s ease;
            }

            .activity-item:hover {
                background: rgba(255, 255, 255, 0.04);
                transform: translateX(4px);
            }

            .activity-time {
                font-size: 0.75rem;
                color: var(--text-muted);
            }

            /* Footer */
            .footer {
                text-align: center;
                padding: 2rem;
                margin-top: 3rem;
                border-top: 1px solid var(--border-color);
            }

            .footer-content {
                display: flex;
                flex-direction: column;
                align-items: center;
                gap: 1rem;
            }

            .refresh-controls {
                display: flex;
                align-items: center;
                gap: 1rem;
            }

            .btn {
                padding: 0.75rem 1.5rem;
                background: var(--gradient-primary);
                color: white;
                border: none;
                border-radius: 8px;
                font-weight: 600;
                cursor: pointer;
                transition: all 0.3s ease;
            }

            .btn:hover {
                transform: translateY(-2px);
                box-shadow: 0 5px 15px rgba(96, 165, 250, 0.3);
            }

            .countdown {
                color: var(--text-secondary);
                font-size: 0.875rem;
            }

            /* Responsive */
            @media (max-width: 1024px) {
                .main-grid {
                    grid-template-columns: repeat(6, 1fr);
                }
                .card-small { grid-column: span 6; }
                .card-medium { grid-column: span 6; }
                .card-large { grid-column: span 6; }
            }

            @media (max-width: 768px) {
                .container {
                    padding: 1rem;
                }
                .header {
                    padding: 2rem 1.5rem;
                }
                .header h1 {
                    font-size: 2rem;
                }
                .status-grid {
                    grid-template-columns: repeat(2, 1fr);
                }
                .main-grid {
                    grid-template-columns: 1fr;
                    gap: 1rem;
                }
                .card-small,
                .card-medium,
                .card-large {
                    grid-column: span 1;
                }
            }
        </style>
    </head>
    <body>
        <div class="container">
            #{render_header(data, uptime_formatted)}

            <div class="main-grid">
                #{render_system_overview_card(data)}
                #{render_websocket_status_card(data)}
                #{render_tracking_metrics_card(data)}
                #{render_notification_stats_card(data)}
                #{render_performance_metrics_card(data)}
                #{render_cache_performance_card(data)}
                #{render_memory_usage_card(data)}
                #{render_activity_feed_card(data)}
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
                    countdownElement.textContent = countdown;
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

            // Animate numbers on load
            function animateValue(element, start, end, duration) {
                const range = end - start;
                const increment = range / (duration / 16);
                let current = start;
                
                const timer = setInterval(() => {
                    current += increment;
                    if ((increment > 0 && current >= end) || (increment < 0 && current <= end)) {
                        current = end;
                        clearInterval(timer);
                    }
                    element.textContent = Math.floor(current).toLocaleString();
                }, 16);
            }

            // Animate all metric values on load
            document.addEventListener('DOMContentLoaded', () => {
                document.querySelectorAll('.animate-number').forEach(el => {
                    const value = parseInt(el.textContent.replace(/,/g, ''));
                    if (!isNaN(value)) {
                        animateValue(el, 0, value, 1000);
                    }
                });
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
    websocket_connected = data.websocket.client_alive

    """
    <div class="header">
        <div class="header-content">
            <h1>Wanderer Notifier</h1>
            <div class="status-grid">
                <div class="status-item">
                    <span class="status-icon">📦</span>
                    <div class="status-label">Version</div>
                    <div class="status-value">v#{data.server_version}</div>
                </div>
                <div class="status-item">
                    <span class="status-icon">⏰</span>
                    <div class="status-label">Uptime</div>
                    <div class="status-value">#{uptime_formatted}</div>
                </div>
                <div class="status-item">
                    <span class="status-icon">🌐</span>
                    <div class="status-label">Port</div>
                    <div class="status-value">#{data.web_server.port}</div>
                </div>
                <div class="status-item">
                    <span class="status-icon">#{if websocket_connected, do: "🟢", else: "🔴"}</span>
                    <div class="status-label">WebSocket</div>
                    <div class="status-value">#{if websocket_connected, do: "Connected", else: "Disconnected"}</div>
                </div>
                <div class="status-item">
                    <span class="status-icon">🕐</span>
                    <div class="status-label">Time</div>
                    <div class="status-value">#{format_time(current_time)}</div>
                </div>
            </div>
        </div>
    </div>
    """
  end

  defp render_system_overview_card(data) do
    memory_usage = max(data.system.memory.processes_percent, data.system.memory.system_percent)
    memory_mb = Float.round((data.system.memory.total_kb || 0) / 1024, 1)

    health_status =
      cond do
        memory_usage >= 80 -> "error"
        memory_usage >= 60 -> "warning"
        true -> "success"
      end

    """
    <div class="card card-medium">
        <div class="card-header">
            <div class="card-title">
                <div class="card-icon">💻</div>
                System Overview
            </div>
            <div class="status-indicator">
                <div class="status-dot #{health_status}"></div>
                #{String.capitalize(health_status)}
            </div>
        </div>
        
        <div class="progress-container">
            <div class="progress-header">
                <span class="progress-label">Memory Usage</span>
                <span class="progress-value">#{Float.round(memory_usage, 1)}%</span>
            </div>
            <div class="progress-bar">
                <div class="progress-fill #{if(memory_usage >= 80, do: "danger", else: if(memory_usage >= 60, do: "warning", else: ""))}"
                     style="width: #{memory_usage}%"></div>
            </div>
        </div>
        
        <div class="info-list">
            <div class="info-item">
                <span class="info-label">Total Memory</span>
                <span class="info-value">#{memory_mb} MB</span>
            </div>
            <div class="info-item">
                <span class="info-label">CPU Cores</span>
                <span class="info-value">#{data.system.scheduler_count}</span>
            </div>
        </div>
    </div>
    """
  end

  defp render_websocket_status_card(data) do
    websocket_connected = data.websocket.client_alive
    status_class = if websocket_connected, do: "success", else: "error"
    status_text = if websocket_connected, do: "Connected", else: "Disconnected"
    uptime = Map.get(data.websocket, :connection_uptime_formatted, "Unknown")

    """
    <div class="card card-medium">
        <div class="card-header">
            <div class="card-title">
                <div class="card-icon">🔌</div>
                WebSocket Connection
            </div>
            <div class="status-indicator">
                <div class="status-dot #{status_class}"></div>
                #{status_text}
            </div>
        </div>
        
        #{if websocket_connected do
      """
      <div class="metric-grid" style="grid-template-columns: 1fr;">
          <div class="metric-item">
              <div class="metric-value">#{uptime}</div>
              <div class="metric-label">Connection Duration</div>
          </div>
      </div>
      """
    else
      """
      <div style="text-align: center; padding: 2rem; color: var(--text-secondary);">
          <div style="font-size: 3rem; margin-bottom: 1rem;">🔴</div>
          <div>WebSocket disconnected</div>
      </div>
      """
    end}
        
        <div class="info-list">
            <div class="info-item">
                <span class="info-label">Status</span>
                <span class="info-value">#{status_text}</span>
            </div>
            #{if websocket_connected do
      """
      <div class="info-item">
          <span class="info-label">Uptime</span>
          <span class="info-value">#{uptime}</span>
      </div>
      """
    end}
        </div>
    </div>
    """
  end

  defp render_tracking_metrics_card(data) do
    """
    <div class="card card-medium">
        <div class="card-header">
            <div class="card-title">
                <div class="card-icon">📡</div>
                Tracking Metrics
            </div>
        </div>
        
        <div class="metric-grid">
            <div class="metric-item">
                <div class="metric-value animate-number">#{data.tracking.systems_count}</div>
                <div class="metric-label">Systems</div>
            </div>
            <div class="metric-item">
                <div class="metric-value animate-number">#{data.tracking.characters_count}</div>
                <div class="metric-label">Characters</div>
            </div>
            <div class="metric-item">
                <div class="metric-value animate-number">#{data.tracking.killmails_received}</div>
                <div class="metric-label">Killmails</div>
            </div>
        </div>
    </div>
    """
  end

  defp render_notification_stats_card(data) do
    """
    <div class="card card-medium">
        <div class="card-header">
            <div class="card-title">
                <div class="card-icon">📬</div>
                Notifications
            </div>
        </div>
        
        <div class="metric-grid">
            <div class="metric-item">
                <div class="metric-value animate-number">#{data.notifications.total}</div>
                <div class="metric-label">Total Sent</div>
            </div>
            <div class="metric-item">
                <div class="metric-value animate-number">#{data.notifications.kills}</div>
                <div class="metric-label">Kill Alerts</div>
            </div>
            <div class="metric-item">
                <div class="metric-value animate-number">#{data.notifications.systems}</div>
                <div class="metric-label">System Alerts</div>
            </div>
            <div class="metric-item">
                <div class="metric-value animate-number">#{data.notifications.characters}</div>
                <div class="metric-label">Character Alerts</div>
            </div>
        </div>
    </div>
    """
  end

  defp render_performance_metrics_card(data) do
    performance = data.performance

    success_rate =
      if performance.success_rate == 0.0, do: "0", else: "#{performance.success_rate}"

    notification_rate =
      if performance.notification_rate == 0.0, do: "0", else: "#{performance.notification_rate}"

    processing_efficiency =
      if performance.processing_efficiency == 0.0,
        do: "0",
        else: "#{performance.processing_efficiency}"

    """
    <div class="card card-medium">
        <div class="card-header">
            <div class="card-title">
                <div class="card-icon">📊</div>
                Performance Metrics
            </div>
        </div>
        
        <div class="metric-grid">
            <div class="metric-item">
                <div class="metric-value">#{success_rate}%</div>
                <div class="metric-label">Success Rate</div>
            </div>
            <div class="metric-item">
                <div class="metric-value">#{notification_rate}%</div>
                <div class="metric-label">Notification Rate</div>
            </div>
            <div class="metric-item">
                <div class="metric-value">#{processing_efficiency}%</div>
                <div class="metric-label">Efficiency</div>
            </div>
        </div>
        
        <div class="info-list" style="margin-top: 2rem;">
            <div class="info-item">
                <span class="info-label">Last Activity</span>
                <span class="info-value">#{performance.last_activity}</span>
            </div>
        </div>
    </div>
    """
  end

  defp render_cache_performance_card(data) do
    cache = data.cache_stats
    has_activity = cache_has_activity?(cache)

    """
    <div class="card card-medium">
        <div class="card-header">
            <div class="card-title">
                <div class="card-icon">💾</div>
                Cache Performance
            </div>
            #{render_cache_status_indicator(has_activity, cache)}
        </div>
        
        #{render_cache_content(has_activity, cache)}
    </div>
    """
  end

  defp cache_has_activity?(cache) do
    cache.hits > 0 || cache.misses > 0 || cache.size > 0 || Map.get(cache, :writes, 0) > 0
  end

  defp render_cache_status_indicator(true, cache) do
    hit_rate_color = get_cache_hit_rate_color(cache.hit_rate)

    """
    <div class="status-indicator">
        <div class="status-dot #{hit_rate_color}"></div>
        #{cache.hit_rate}% Hit Rate
    </div>
    """
  end

  defp render_cache_status_indicator(false, _cache) do
    """
    <div class="status-indicator">
        <div class="status-dot warning"></div>
        No Activity
    </div>
    """
  end

  defp render_cache_content(true, cache) do
    progress_fill_class = get_cache_progress_fill_class(cache.hit_rate)

    """
    <div class="progress-container">
        <div class="progress-header">
            <span class="progress-label">Cache Hit Rate</span>
            <span class="progress-value">#{cache.hit_rate}%</span>
        </div>
        <div class="progress-bar">
            <div class="progress-fill #{progress_fill_class}"
                 style="width: #{cache.hit_rate}%"></div>
        </div>
    </div>

    <div class="info-list">
        <div class="info-item">
            <span class="info-label">Cache Size</span>
            <span class="info-value">#{cache.size} entries</span>
        </div>
        <div class="info-item">
            <span class="info-label">Hits / Misses</span>
            <span class="info-value">#{cache.hits} / #{cache.misses}</span>
        </div>
        <div class="info-item">
            <span class="info-label">Evictions</span>
            <span class="info-value">#{cache.evictions}</span>
        </div>
        <div class="info-item">
            <span class="info-label">Writes</span>
            <span class="info-value">#{Map.get(cache, :writes, 0)}</span>
        </div>
    </div>
    """
  end

  defp render_cache_content(false, _cache) do
    """
    <div style="text-align: center; padding: 2rem; color: var(--text-secondary);">
        <div style="font-size: 3rem; margin-bottom: 1rem;">💤</div>
        <div>No cache activity yet</div>
    </div>
    """
  end

  defp get_cache_hit_rate_color(hit_rate) when hit_rate >= 80, do: "success"
  defp get_cache_hit_rate_color(hit_rate) when hit_rate >= 60, do: "warning"
  defp get_cache_hit_rate_color(_hit_rate), do: "error"

  defp get_cache_progress_fill_class(hit_rate) when hit_rate >= 80, do: ""
  defp get_cache_progress_fill_class(hit_rate) when hit_rate >= 60, do: "warning"
  defp get_cache_progress_fill_class(_hit_rate), do: "danger"

  defp render_memory_usage_card(data) do
    memory = data.system.memory
    processes_mb = Float.round((memory.processes_kb || 0) / 1024, 1)
    system_mb = Float.round((memory.system_kb || 0) / 1024, 1)

    """
    <div class="card card-medium">
        <div class="card-header">
            <div class="card-title">
                <div class="card-icon">🧠</div>
                Memory Details
            </div>
        </div>
        
        <div class="progress-container">
            <div class="progress-header">
                <span class="progress-label">Process Memory</span>
                <span class="progress-value">#{Float.round(memory.processes_percent, 1)}%</span>
            </div>
            <div class="progress-bar">
                <div class="progress-fill #{if(memory.processes_percent >= 80, do: "danger", else: if(memory.processes_percent >= 60, do: "warning", else: ""))}"
                     style="width: #{memory.processes_percent}%"></div>
            </div>
        </div>
        
        <div class="progress-container">
            <div class="progress-header">
                <span class="progress-label">System Memory</span>
                <span class="progress-value">#{Float.round(memory.system_percent, 1)}%</span>
            </div>
            <div class="progress-bar">
                <div class="progress-fill #{if(memory.system_percent >= 80, do: "danger", else: if(memory.system_percent >= 60, do: "warning", else: ""))}"
                     style="width: #{memory.system_percent}%"></div>
            </div>
        </div>
        
        <div class="info-list">
            <div class="info-item">
                <span class="info-label">Processes</span>
                <span class="info-value">#{processes_mb} MB</span>
            </div>
            <div class="info-item">
                <span class="info-label">System</span>
                <span class="info-value">#{system_mb} MB</span>
            </div>
        </div>
    </div>
    """
  end

  defp render_activity_feed_card(data) do
    recent_activity = Map.get(data, :recent_activity, [])

    """
    <div class="card card-medium">
        <div class="card-header">
            <div class="card-title">
                <div class="card-icon">📈</div>
                Recent Activity
            </div>
        </div>
        
        #{if length(recent_activity) > 0 do
      """
      <div class="activity-feed">
          #{Enum.map(recent_activity, fn activity -> """
        <div class="activity-item">
            <div>#{activity.message}</div>
            <div class="activity-time">#{activity.timestamp}</div>
        </div>
        """ end) |> Enum.join("")}
      </div>
      """
    else
      """
      <div style="text-align: center; padding: 3rem; color: var(--text-secondary);">
          <div style="font-size: 4rem; margin-bottom: 1rem;">📊</div>
          <div style="font-size: 1.25rem; margin-bottom: 0.5rem;">All Quiet</div>
          <div style="font-size: 0.875rem;">No recent activity to display</div>
      </div>
      """
    end}
    </div>
    """
  end

  defp render_footer(data) do
    """
    <div class="footer">
        <div class="footer-content">
            <div style="color: var(--text-secondary); font-size: 0.875rem;">
                Last updated: #{data.timestamp}
            </div>
            <div class="refresh-controls">
                <button onclick="manualRefresh()" class="btn">Refresh Now</button>
                <div class="countdown">Refreshing in <span id="refresh-countdown">--</span>s</div>
            </div>
            <div style="color: var(--text-muted); font-size: 0.75rem;">
                Press Ctrl+R for manual refresh
            </div>
        </div>
    </div>
    """
  end

  match _ do
    send_error(conn, 404, "not_found")
  end
end
