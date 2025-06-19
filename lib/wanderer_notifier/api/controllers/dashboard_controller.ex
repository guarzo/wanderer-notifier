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

    """
    <!DOCTYPE html>
    <html lang="en">
    <head>
        <meta charset="UTF-8">
        <meta name="viewport" content="width=device-width, initial-scale=1.0">
        <title>Wanderer Notifier Dashboard</title>
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
            <div class="header">
                <h1>Wanderer Notifier Dashboard</h1>
                <p>System Status Overview</p>
            </div>

            <div class="grid">
                <div class="card">
                    <h2>System Status</h2>
                    <div class="info-row">
                        <span class="info-label">Status</span>
                        <span class="info-value">
                            <span class="status-badge status-ok">#{data.status}</span>
                        </span>
                    </div>
                    <div class="info-row">
                        <span class="info-label">Version</span>
                        <span class="info-value">#{data.server_version}</span>
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

                <div class="card">
                    <h2>Web Server</h2>
                    <div class="info-row">
                        <span class="info-label">Status</span>
                        <span class="info-value">
                            <span class="status-badge #{if data.web_server.running, do: "status-running", else: "status-stopped"}">
                                #{if data.web_server.running, do: "Running", else: "Stopped"}
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

                <div class="card">
                    <h2>Processing Stats</h2>
                    <div class="info-row">
                        <span class="info-label">Kills Processed</span>
                        <span class="info-value">#{data.processing.kills_processed}</span>
                    </div>
                    <div class="info-row">
                        <span class="info-label">Kills Notified</span>
                        <span class="info-value">#{data.processing.kills_notified}</span>
                    </div>
                </div>
            </div>

            <div class="footer">
                <p>Last updated: #{data.timestamp}</p>
            </div>
        </div>

        <script>
            // Auto-refresh every 5 seconds
            setTimeout(function() {
                location.reload();
            }, 5000);
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

  match _ do
    send_error(conn, 404, "not_found")
  end
end
