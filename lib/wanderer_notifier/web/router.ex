defmodule WandererNotifier.Web.Router do
  @moduledoc """
  Web router for the WandererNotifier dashboard.
  """
  use Plug.Router
  require Logger
  alias WandererNotifier.License
  alias WandererNotifier.Stats
  alias WandererNotifier.Features
  alias WandererNotifier.Cache.Repository, as: CacheRepo

  plug(Plug.Logger)
  plug(:match)
  plug(Plug.Parsers, parsers: [:json], json_decoder: Jason)
  plug(:dispatch)

  get "/" do
    conn
    |> put_resp_content_type("text/html")
    |> send_resp(200, dashboard_html())
  end

  get "/api/status" do
    license_status = License.status()
    
    # Extract license information
    license_info = %{
      valid: license_status[:valid],
      bot_assigned: license_status[:bot_assigned],
      details: license_status[:details],
      error: license_status[:error],
      error_message: license_status[:error_message]
    }

    # Get application stats
    stats = Stats.get_stats()

    # Get feature limitations
    limits = Features.get_all_limits()
    
    # Get current usage
    tracked_systems = CacheRepo.get("map:systems") || []
    tracked_characters = CacheRepo.get("map:characters") || []
    
    # Calculate usage percentages
    usage = %{
      tracked_systems: %{
        current: length(tracked_systems),
        limit: limits.tracked_systems,
        percentage: calculate_percentage(length(tracked_systems), limits.tracked_systems)
      },
      tracked_characters: %{
        current: length(tracked_characters),
        limit: limits.tracked_characters,
        percentage: calculate_percentage(length(tracked_characters), limits.tracked_characters)
      },
      notification_history: %{
        limit: limits.notification_history
      }
    }

    # Combine stats, license info, and feature info
    response = %{
      stats: stats,
      license: license_info,
      features: %{
        limits: limits,
        usage: usage,
        enabled: %{
          basic_notifications: Features.enabled?(:basic_notifications),
          tracked_systems_notifications: Features.enabled?(:tracked_systems_notifications),
          tracked_characters_notifications: Features.enabled?(:tracked_characters_notifications),
          backup_kills_processing: Features.enabled?(:backup_kills_processing),
          web_dashboard_full: Features.enabled?(:web_dashboard_full),
          advanced_statistics: Features.enabled?(:advanced_statistics)
        }
      }
    }

    conn
    |> put_resp_content_type("application/json")
    |> send_resp(200, Jason.encode!(response))
  end

  defp calculate_percentage(_current, limit) when is_nil(limit), do: nil
  defp calculate_percentage(current, limit) when limit > 0, do: min(100, round(current / limit * 100))
  defp calculate_percentage(_, _), do: 0

  match _ do
    send_resp(conn, 404, "Not found")
  end

  defp dashboard_html do
    """
    <!DOCTYPE html>
    <html lang="en">
    <head>
      <meta charset="UTF-8">
      <meta name="viewport" content="width=device-width, initial-scale=1.0">
      <title>WandererNotifier Dashboard</title>
      <style>
        body {
          font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif;
          line-height: 1.6;
          color: #333;
          max-width: 1200px;
          margin: 0 auto;
          padding: 20px;
          background-color: #f5f5f5;
        }
        h1, h2, h3 {
          color: #2c3e50;
        }
        .container {
          display: flex;
          flex-wrap: wrap;
          gap: 20px;
        }
        .card {
          background: white;
          border-radius: 8px;
          box-shadow: 0 2px 4px rgba(0,0,0,0.1);
          padding: 20px;
          flex: 1;
          min-width: 300px;
          margin-bottom: 20px;
        }
        .status {
          display: inline-block;
          padding: 5px 10px;
          border-radius: 4px;
          font-weight: bold;
        }
        .status-valid {
          background-color: #d4edda;
          color: #155724;
        }
        .status-invalid {
          background-color: #f8d7da;
          color: #721c24;
        }
        .status-warning {
          background-color: #fff3cd;
          color: #856404;
        }
        .stat-box {
          display: flex;
          justify-content: space-between;
          margin-bottom: 10px;
          padding: 10px;
          background-color: #f8f9fa;
          border-radius: 4px;
        }
        .stat-label {
          font-weight: bold;
        }
        .refresh-button {
          background-color: #4CAF50;
          border: none;
          color: white;
          padding: 10px 20px;
          text-align: center;
          text-decoration: none;
          display: inline-block;
          font-size: 16px;
          margin: 20px 0;
          cursor: pointer;
          border-radius: 4px;
        }
        .progress-container {
          width: 100%;
          background-color: #e9ecef;
          border-radius: 4px;
          margin-top: 5px;
        }
        .progress-bar {
          height: 10px;
          border-radius: 4px;
          background-color: #4CAF50;
        }
        .progress-bar.warning {
          background-color: #ffc107;
        }
        .progress-bar.danger {
          background-color: #dc3545;
        }
        .feature-grid {
          display: grid;
          grid-template-columns: repeat(auto-fill, minmax(200px, 1fr));
          gap: 10px;
          margin-top: 10px;
        }
        .feature-item {
          padding: 10px;
          border-radius: 4px;
          background-color: #f8f9fa;
          display: flex;
          align-items: center;
        }
        .feature-status {
          width: 12px;
          height: 12px;
          border-radius: 50%;
          margin-right: 10px;
        }
        .feature-enabled {
          background-color: #4CAF50;
        }
        .feature-disabled {
          background-color: #dc3545;
        }
      </style>
    </head>
    <body>
      <h1>WandererNotifier Dashboard</h1>
      
      <div class="container">
        <div class="card">
          <h2>License Status</h2>
          <div id="license-status">Loading...</div>
          <div id="license-details"></div>
        </div>
        
        <div class="card">
          <h2>System Status</h2>
          <div id="uptime">Loading...</div>
          <div id="websocket-status">Loading...</div>
        </div>
      </div>
      
      <div class="card">
        <h2>Feature Status</h2>
        <div id="feature-status">Loading...</div>
      </div>
      
      <div class="card">
        <h2>Resource Usage</h2>
        <div id="resource-usage">Loading...</div>
      </div>
      
      <div class="card">
        <h2>Notification Statistics</h2>
        <div id="notification-stats">Loading...</div>
      </div>
      
      <button class="refresh-button" onclick="refreshData()">Refresh Data</button>
      
      <script>
        // Fetch status data from the API
        function fetchStatus() {
          fetch('/api/status')
            .then(response => response.json())
            .then(data => {
              updateLicenseStatus(data.license);
              updateStats(data.stats);
              updateFeatureStatus(data.features);
              updateResourceUsage(data.features);
            })
            .catch(error => {
              console.error('Error fetching status:', error);
            });
        }
        
        // Update license status display
        function updateLicenseStatus(license) {
          const statusElement = document.getElementById('license-status');
          const detailsElement = document.getElementById('license-details');
          
          if (license.valid) {
            let statusClass = 'status-valid';
            let statusText = 'Valid';
            
            if (!license.bot_assigned) {
              statusClass = 'status-warning';
              statusText = 'Valid (Bot Not Assigned)';
            }
            
            statusElement.innerHTML = `<span class="status ${statusClass}">${statusText}</span>`;
            
            let details = '';
            if (license.details) {
              if (license.details.license_name) {
                details += `<div class="stat-box"><span class="stat-label">Name:</span> ${license.details.license_name}</div>`;
              }
              if (license.details.valid_to) {
                details += `<div class="stat-box"><span class="stat-label">Valid Until:</span> ${license.details.valid_to}</div>`;
              }
              if (license.details.bots && license.details.bots.length > 0) {
                const botNames = license.details.bots.map(bot => bot.name).join(', ');
                details += `<div class="stat-box"><span class="stat-label">Assigned Bots:</span> ${botNames}</div>`;
              }
            }
            
            detailsElement.innerHTML = details;
          } else {
            statusElement.innerHTML = '<span class="status status-invalid">Invalid</span>';
            
            let errorDetails = '';
            if (license.error_message) {
              errorDetails += `<div class="stat-box"><span class="stat-label">Error:</span> ${license.error_message}</div>`;
            } else if (license.error) {
              errorDetails += `<div class="stat-box"><span class="stat-label">Error:</span> ${license.error}</div>`;
            } else {
              errorDetails += `<div class="stat-box"><span class="stat-label">Error:</span> Unknown license error</div>`;
            }
            
            detailsElement.innerHTML = errorDetails;
          }
        }
        
        // Update feature status display
        function updateFeatureStatus(features) {
          const featureElement = document.getElementById('feature-status');
          
          if (!features || !features.enabled) {
            featureElement.innerHTML = 'No feature information available';
            return;
          }
          
          let featureHtml = '<div class="feature-grid">';
          
          for (const [feature, enabled] of Object.entries(features.enabled)) {
            const displayName = feature
              .split('_')
              .map(word => word.charAt(0).toUpperCase() + word.slice(1))
              .join(' ');
              
            featureHtml += `
              <div class="feature-item">
                <div class="feature-status ${enabled ? 'feature-enabled' : 'feature-disabled'}"></div>
                <span>${displayName}</span>
              </div>
            `;
          }
          
          featureHtml += '</div>';
          featureElement.innerHTML = featureHtml;
        }
        
        // Update resource usage display
        function updateResourceUsage(features) {
          const usageElement = document.getElementById('resource-usage');
          
          if (!features || !features.usage) {
            usageElement.innerHTML = 'No usage information available';
            return;
          }
          
          const usage = features.usage;
          let usageHtml = '';
          
          // Tracked Systems
          usageHtml += createResourceBar(
            'Tracked Systems', 
            usage.tracked_systems.current, 
            usage.tracked_systems.limit,
            usage.tracked_systems.percentage
          );
          
          // Tracked Characters
          usageHtml += createResourceBar(
            'Tracked Characters', 
            usage.tracked_characters.current, 
            usage.tracked_characters.limit,
            usage.tracked_characters.percentage
          );
          
          // Notification History
          if (usage.notification_history.limit) {
            usageHtml += `
              <div class="stat-box">
                <span class="stat-label">Notification History:</span>
                <span>${usage.notification_history.limit} hours</span>
              </div>
            `;
          }
          
          usageElement.innerHTML = usageHtml;
        }
        
        function createResourceBar(label, current, limit, percentage) {
          let limitText = limit === null ? 'Unlimited' : limit;
          let barHtml = '';
          
          if (percentage !== null) {
            let barClass = 'progress-bar';
            if (percentage > 90) barClass += ' danger';
            else if (percentage > 70) barClass += ' warning';
            
            barHtml = `
              <div class="progress-container">
                <div class="${barClass}" style="width: ${percentage}%"></div>
              </div>
            `;
          }
          
          return `
            <div class="stat-box">
              <span class="stat-label">${label}:</span>
              <span>${current} / ${limitText}</span>
            </div>
            ${barHtml}
          `;
        }
        
        // Update statistics display
        function updateStats(stats) {
          const uptimeElement = document.getElementById('uptime');
          const websocketElement = document.getElementById('websocket-status');
          const notificationElement = document.getElementById('notification-stats');
          
          // Update uptime
          uptimeElement.innerHTML = `<div class="stat-box"><span class="stat-label">Uptime:</span> ${stats.uptime}</div>`;
          
          // Update websocket status
          const wsConnected = stats.websocket.connected;
          websocketElement.innerHTML = `
            <div class="stat-box">
              <span class="stat-label">Websocket:</span> 
              <span class="${wsConnected ? 'status-valid' : 'status-invalid'}">${wsConnected ? 'Connected' : 'Disconnected'}</span>
            </div>
            <div class="stat-box"><span class="stat-label">Reconnects:</span> ${stats.websocket.reconnects}</div>
          `;
          
          // Update notification stats
          let notificationHtml = '';
          const notifications = stats.notifications;
          
          notificationHtml += `<div class="stat-box"><span class="stat-label">Total:</span> ${notifications.total}</div>`;
          notificationHtml += `<div class="stat-box"><span class="stat-label">Kills:</span> ${notifications.kills}</div>`;
          notificationHtml += `<div class="stat-box"><span class="stat-label">Systems:</span> ${notifications.systems}</div>`;
          notificationHtml += `<div class="stat-box"><span class="stat-label">Characters:</span> ${notifications.characters}</div>`;
          notificationHtml += `<div class="stat-box"><span class="stat-label">Errors:</span> ${notifications.errors}</div>`;
          
          notificationElement.innerHTML = notificationHtml;
        }
        
        // Refresh data
        function refreshData() {
          fetchStatus();
        }
        
        // Initial data fetch
        document.addEventListener('DOMContentLoaded', fetchStatus);
        
        // Auto-refresh every 30 seconds
        setInterval(fetchStatus, 30000);
      </script>
    </body>
    </html>
    """
  end
end 