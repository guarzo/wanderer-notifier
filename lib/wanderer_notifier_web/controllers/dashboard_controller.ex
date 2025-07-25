defmodule WandererNotifierWeb.DashboardController do
  @moduledoc """
  Phoenix controller for the web dashboard.
  """
  use WandererNotifierWeb, :controller
  require Logger

  alias WandererNotifier.Api.Controllers.SystemInfo

  def index(conn, _params) do
    # Get the same data as /health/details plus extended stats with error handling
    try do
      detailed_status = SystemInfo.collect_extended_status()

      # For now, return a simple HTML dashboard with the data
      html_response = build_dashboard_html(detailed_status)

      conn
      |> put_resp_content_type("text/html")
      |> send_resp(200, html_response)
    rescue
      exception ->
        Logger.error("Failed to collect system status: #{inspect(exception)}")
        Logger.error("Stacktrace: #{Exception.format_stacktrace(__STACKTRACE__)}")

        conn
        |> put_resp_content_type("text/html")
        |> send_resp(
          500,
          "<html><body><h1>Error</h1><p>Unable to collect system status: #{Exception.message(exception)}</p><details><summary>Details</summary><pre>#{inspect(exception)}</pre></details></body></html>"
        )
    end
  end

  # TODO: Refactor this function to use Phoenix templates
  # Current implementation has inline HTML/CSS/JS which should be moved to:
  # - HTML structure: lib/wanderer_notifier_web/templates/dashboard/index.html.heex
  # - CSS styles: priv/static/css/dashboard.css  
  # - JavaScript: priv/static/js/dashboard.js or Phoenix LiveView/hooks
  # - Reusable components: lib/wanderer_notifier_web/components/dashboard_components.ex
  defp build_dashboard_html(data) do
    """
    <!DOCTYPE html>
    <html lang="en">
    <head>
        <meta charset="UTF-8">
        <meta name="viewport" content="width=device-width, initial-scale=1.0">
        <title>WandererNotifier Dashboard</title>
        <style>
            :root {
                --bg-primary: #0f1419;
                --bg-secondary: #1a1f2e;
                --bg-tertiary: #252a3a;
                --bg-card: #1e2530;
                --border-primary: #2d3748;
                --border-secondary: #4a5568;
                --text-primary: #f7fafc;
                --text-secondary: #e2e8f0;
                --text-muted: #a0aec0;
                --accent-blue: #4299e1;
                --accent-green: #48bb78;
                --accent-orange: #ed8936;
                --accent-red: #f56565;
                --accent-purple: #9f7aea;
                --shadow-sm: 0 1px 3px rgba(0,0,0,0.4);
                --shadow-md: 0 4px 6px rgba(0,0,0,0.5);
                --shadow-lg: 0 10px 15px rgba(0,0,0,0.6);
                --gradient-primary: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
                --gradient-secondary: linear-gradient(135deg, #f093fb 0%, #f5576c 100%);
                --gradient-tertiary: linear-gradient(135deg, #4facfe 0%, #00f2fe 100%);
            }
            
            * { box-sizing: border-box; }
            
            body { 
                font-family: 'Inter', -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; 
                margin: 0; 
                padding: 0;
                background: var(--bg-primary);
                color: var(--text-primary);
                line-height: 1.6;
                min-height: 100vh;
            }
            
            .container { 
                max-width: 1400px; 
                margin: 0 auto; 
                padding: 20px;
            }
            
            .header {
                text-align: center;
                margin-bottom: 40px;
                padding: 40px 0;
                background: var(--gradient-primary);
                border-radius: 16px;
                box-shadow: var(--shadow-lg);
                position: relative;
                overflow: hidden;
            }
            
            .header::before {
                content: '';
                position: absolute;
                top: 0;
                left: 0;
                right: 0;
                bottom: 0;
                background: url('data:image/svg+xml,<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100"><defs><pattern id="grid" width="10" height="10" patternUnits="userSpaceOnUse"><path d="M 10 0 L 0 0 0 10" fill="none" stroke="rgba(255,255,255,0.1)" stroke-width="0.5"/></pattern></defs><rect width="100" height="100" fill="url(%23grid)"/></svg>');
                opacity: 0.3;
            }
            
            .header h1 {
                color: white;
                font-size: 2.5rem;
                font-weight: 700;
                margin: 0;
                text-shadow: 0 2px 4px rgba(0,0,0,0.3);
                position: relative;
                z-index: 1;
            }
            
            .header-stats {
                display: flex;
                justify-content: center;
                gap: 40px;
                margin-top: 20px;
                position: relative;
                z-index: 1;
            }
            
            .header-stat {
                text-align: center;
                color: white;
            }
            
            .header-stat .label {
                display: block;
                font-size: 0.875rem;
                opacity: 0.9;
                font-weight: 500;
            }
            
            .header-stat .value {
                display: block;
                font-size: 1.25rem;
                font-weight: 700;
                margin-top: 4px;
            }
            
            .card { 
                background: var(--bg-card);
                border-radius: 12px; 
                padding: 24px; 
                margin: 20px 0; 
                box-shadow: var(--shadow-md);
                border: 1px solid var(--border-primary);
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
                background: var(--gradient-tertiary);
            }
            
            .card:hover {
                transform: translateY(-2px);
                box-shadow: var(--shadow-lg);
                border-color: var(--border-secondary);
            }
            
            .card h2 {
                color: var(--text-primary);
                font-size: 1.25rem;
                font-weight: 600;
                margin: 0 0 20px 0;
                display: flex;
                align-items: center;
                gap: 12px;
            }
            
            .card h2::before {
                content: '';
                width: 6px;
                height: 24px;
                background: var(--accent-blue);
                border-radius: 3px;
            }
            
            .status { 
                color: var(--accent-green); 
                font-weight: 600;
                display: inline-flex;
                align-items: center;
                gap: 6px;
            }
            
            .status::before {
                content: '●';
                font-size: 0.75rem;
            }
            
            .grid { 
                display: grid; 
                grid-template-columns: repeat(auto-fit, minmax(320px, 1fr)); 
                gap: 24px; 
            }
            
            .metric { 
                display: flex; 
                justify-content: space-between; 
                align-items: center;
                padding: 12px 0; 
                border-bottom: 1px solid var(--border-primary);
                transition: all 0.2s ease;
            }
            
            .metric:last-child { border-bottom: none; }
            
            .metric:hover {
                background: rgba(255,255,255,0.02);
                margin: 0 -12px;
                padding: 12px;
                border-radius: 6px;
            }
            
            .metric .label {
                color: var(--text-secondary);
                font-weight: 500;
            }
            
            .metric .value {
                color: var(--text-primary);
                font-weight: 600;
                font-family: 'JetBrains Mono', Monaco, 'Consolas', monospace;
            }
            
            .connection-status {
                display: inline-flex;
                align-items: center;
                gap: 8px;
                padding: 6px 12px;
                border-radius: 20px;
                font-size: 0.875rem;
                font-weight: 500;
            }
            
            .connection-status.connected {
                background: rgba(72, 187, 120, 0.2);
                color: var(--accent-green);
                border: 1px solid rgba(72, 187, 120, 0.3);
            }
            
            .connection-status.disconnected {
                background: rgba(245, 101, 101, 0.2);
                color: var(--accent-red);
                border: 1px solid rgba(245, 101, 101, 0.3);
            }
            
            .validation-controls {
                display: flex;
                gap: 12px;
                flex-wrap: wrap;
                margin: 20px 0;
            }
            
            .btn {
                background: var(--gradient-primary);
                color: white;
                border: none;
                padding: 12px 20px;
                border-radius: 8px;
                font-weight: 600;
                cursor: pointer;
                transition: all 0.3s ease;
                font-size: 0.875rem;
                display: inline-flex;
                align-items: center;
                gap: 8px;
                box-shadow: var(--shadow-sm);
            }
            
            .btn:hover {
                transform: translateY(-1px);
                box-shadow: var(--shadow-md);
            }
            
            .btn:active {
                transform: translateY(0);
            }
            
            .btn.btn-warning { background: linear-gradient(135deg, #ed8936 0%, #f6ad55 100%); }
            .btn.btn-info { background: linear-gradient(135deg, #4299e1 0%, #63b3ed 100%); }
            .btn.btn-secondary { background: linear-gradient(135deg, #718096 0%, #a0aec0 100%); }
            
            .btn:disabled {
                opacity: 0.6;
                cursor: not-allowed;
                transform: none;
            }
            
            .validation-feedback {
                margin-top: 16px;
                padding: 12px 16px;
                border-radius: 8px;
                font-weight: 500;
                display: none;
            }
            
            .footer {
                text-align: center;
                margin-top: 40px;
                padding: 20px;
                color: var(--text-muted);
                font-size: 0.875rem;
                border-top: 1px solid var(--border-primary);
            }
            
            /* Icons using CSS */
            .icon-system::before { content: '🗺️'; }
            .icon-character::before { content: '👤'; }
            .icon-status::before { content: '📊'; }
            .icon-memory::before { content: '💾'; }
            .icon-websocket::before { content: '🔌'; }
            .icon-cache::before { content: '⚡'; }
            .icon-processes::before { content: '⚙️'; }
            .icon-validation::before { content: '🧪'; }
            
            /* Responsive design */
            @media (max-width: 768px) {
                .container { padding: 12px; }
                .header h1 { font-size: 2rem; }
                .header-stats { flex-direction: column; gap: 20px; }
                .validation-controls { justify-content: center; }
                .grid { grid-template-columns: 1fr; }
            }
        </style>
        <script>
            setTimeout(() => window.location.reload(), 30000);
            
            function enableValidation(mode) {
                const feedback = document.getElementById('validation-feedback');
                const button = document.getElementById('validate-' + mode);
                
                button.disabled = true;
                button.textContent = 'Enabling...';
                
                fetch('/api/validation/enable/' + mode, { method: 'POST' })
                    .then(response => response.json())
                    .then(data => {
                        if (data.success) {
                            showFeedback('Validation enabled for ' + mode + ' notifications. Waiting for next killmail...', 'success');
                            button.textContent = 'Waiting for next kill...';
                        } else {
                            showFeedback('Error: ' + data.error, 'error');
                            button.disabled = false;
                            button.textContent = 'Test Next Kill as ' + (mode === 'system' ? 'System' : 'Character') + ' Notification';
                        }
                    })
                    .catch(error => {
                        showFeedback('Network error: ' + error.message, 'error');
                        button.disabled = false;
                        button.textContent = 'Test Next Kill as ' + (mode === 'system' ? 'System' : 'Character') + ' Notification';
                    });
            }
            
            function checkValidationStatus() {
                fetch('/api/validation/status')
                    .then(response => response.json())
                    .then(data => {
                        if (data.success) {
                            const status = data.status;
                            if (status.mode === 'disabled') {
                                showFeedback('Validation is currently disabled.', 'info');
                            } else {
                                const expiresAt = new Date(status.expires_at).toLocaleString();
                                showFeedback('Validation mode: ' + status.mode + ' (expires at ' + expiresAt + ')', 'info');
                            }
                        } else {
                            showFeedback('Error checking status: ' + data.error, 'error');
                        }
                    })
                    .catch(error => {
                        showFeedback('Network error: ' + error.message, 'error');
                    });
            }
            
            function showFeedback(message, type) {
                const feedback = document.getElementById('validation-feedback');
                feedback.style.display = 'block';
                feedback.textContent = message;
                
                switch(type) {
                    case 'success':
                        feedback.style.background = '#d4edda';
                        feedback.style.color = '#155724';
                        feedback.style.border = '1px solid #c3e6cb';
                        break;
                    case 'error':
                        feedback.style.background = '#f8d7da';
                        feedback.style.color = '#721c24';
                        feedback.style.border = '1px solid #f5c6cb';
                        break;
                    case 'info':
                        feedback.style.background = '#d1ecf1';
                        feedback.style.color = '#0c5460';
                        feedback.style.border = '1px solid #bee5eb';
                        break;
                }
                
                setTimeout(() => {
                    feedback.style.display = 'none';
                }, 10000);
            }
        </script>
    </head>
    <body>
        <div class="container">
            <div class="header">
                <h1>🚀 WandererNotifier Dashboard</h1>
                <div class="header-stats">
                    <div class="header-stat">
                        <span class="label">Status</span>
                        <span class="value">#{data.status}</span>
                    </div>
                    <div class="header-stat">
                        <span class="label">Version</span>
                        <span class="value">#{data.server_version}</span>
                    </div>
                    <div class="header-stat">
                        <span class="label">Uptime</span>
                        <span class="value">#{format_uptime(data.system.uptime_seconds)}</span>
                    </div>
                </div>
            </div>
            
            <div class="grid">
                <div class="card">
                    <h2 class="icon-websocket">WebSocket Status</h2>
                    <div class="metric">
                        <span class="label">Connection:</span>
                        <span class="connection-status #{if data.websocket.connection_status == "connected", do: "connected", else: "disconnected"}">
                            #{data.websocket.connection_status}
                        </span>
                    </div>
                    <div class="metric">
                        <span class="label">Uptime:</span>
                        <span class="value">#{data.websocket.connection_uptime_formatted}</span>
                    </div>
                </div>
                
                <div class="card">
                    <h2 class="icon-memory">Memory Usage</h2>
                    <div class="metric">
                        <span class="label">Total:</span>
                        <span class="value">#{data.system.memory.total_kb} KB</span>
                    </div>
                    <div class="metric">
                        <span class="label">Processes:</span>
                        <span class="value">#{data.system.memory.processes_kb} KB (#{data.system.memory.processes_percent}%)</span>
                    </div>
                </div>
                
                <div class="card">
                    <h2 class="icon-cache">Cache Stats</h2>
                    <div class="metric">
                        <span class="label">Size:</span>
                        <span class="value">#{data.cache_stats.size} entries</span>
                    </div>
                    <div class="metric">
                        <span class="label">Hit Rate:</span>
                        <span class="value">#{data.cache_stats.hit_rate}%</span>
                    </div>
                </div>
                
                <div class="card">
                    <h2 class="icon-status">Processing Stats</h2>
                    <div class="metric">
                        <span class="label">Kills Processed:</span>
                        <span class="value">#{data.processing.kills_processed}</span>
                    </div>
                    <div class="metric">
                        <span class="label">Notifications Sent:</span>
                        <span class="value">#{data.processing.notifications_sent}</span>
                    </div>
                </div>
            </div>
            
            <div class="card">
                <h2 class="icon-processes">Key Processes</h2>
                #{build_processes_html(data.processes.key_processes)}
            </div>
            
            <div class="card">
                <h2 class="icon-validation">Notification Validation</h2>
                <p style="color: var(--text-secondary); margin-bottom: 20px;">Test notification functionality with the next incoming killmail:</p>
                <div class="validation-controls">
                    <button id="validate-system" onclick="enableValidation('system')" class="btn btn-warning icon-system">
                        Test Next Kill as System Notification
                    </button>
                    <button id="validate-character" onclick="enableValidation('character')" class="btn btn-info icon-character">
                        Test Next Kill as Character Notification
                    </button>
                    <button id="validation-status" onclick="checkValidationStatus()" class="btn btn-secondary icon-status">
                        Check Status
                    </button>
                </div>
                <div id="validation-feedback" class="validation-feedback"></div>
            </div>
            
            <div class="footer">
                <div>Auto-refresh in 30 seconds | Last updated: #{data.timestamp}</div>
                <div style="margin-top: 8px; opacity: 0.7;">WandererNotifier v#{data.server_version} | EVE Online Killmail Monitoring</div>
            </div>
        </div>
    </body>
    </html>
    """
  end

  defp format_uptime(seconds) when seconds < 60, do: "#{seconds}s"

  defp format_uptime(seconds) when seconds < 3600 do
    minutes = div(seconds, 60)
    remaining = rem(seconds, 60)
    "#{minutes}m #{remaining}s"
  end

  defp format_uptime(seconds) do
    hours = div(seconds, 3600)
    minutes = div(rem(seconds, 3600), 60)
    "#{hours}h #{minutes}m"
  end

  defp build_processes_html(processes) do
    processes
    |> Enum.map(fn process ->
      status_class = if process.status == "running", do: "connected", else: "disconnected"

      """
      <div class="metric">
        <span class="label">#{process.name}:</span>
        <span class="connection-status #{status_class}">
          #{process.status} (#{process.memory_kb} KB)
        </span>
      </div>
      """
    end)
    |> Enum.join("")
  end
end
