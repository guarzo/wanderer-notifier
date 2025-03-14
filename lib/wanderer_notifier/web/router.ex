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
  alias WandererNotifier.Helpers.CacheHelpers
  alias WandererNotifier.Config

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
    tracked_systems = get_tracked_systems()
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
        },
        config: %{
          character_tracking_enabled: Config.character_tracking_enabled?(),
          character_notifications_enabled: Config.character_notifications_enabled?(),
          system_notifications_enabled: Config.system_notifications_enabled?()
        }
      }
    }

    conn
    |> put_resp_content_type("application/json")
    |> send_resp(200, Jason.encode!(response))
  end

  # Endpoint to trigger a test kill notification
  get "/api/test-notification" do
    Logger.info("Test notification endpoint called")

    result = WandererNotifier.Service.KillProcessor.send_test_kill_notification()

    response = case result do
      {:ok, kill_id} ->
        %{
          success: true,
          message: "Test notification sent for kill_id: #{kill_id}",
          details: "The notification was processed through the normal notification path. Check your Discord for the message."
        }

      {:error, :enrichment_failed} ->
        %{
          success: false,
          message: "Failed to send test notification: Could not enrich kill data",
          details: "There was an error processing the kill data. Check the application logs for more details."
        }

      {:error, :no_kill_id} ->
        %{
          success: false,
          message: "Failed to send test notification: Invalid kill data",
          details: "The kill data does not contain a valid kill ID. Check the application logs for more details."
        }

      {:error, reason} ->
        %{
          success: false,
          message: "Failed to send test notification: #{inspect(reason)}",
          details: "There was an error processing the notification. Check the application logs for more details."
        }
    end

    conn
    |> put_resp_content_type("application/json")
    |> send_resp(200, Jason.encode!(response))
  end

  # Endpoint to trigger a test character notification
  get "/api/test-character-notification" do
    Logger.info("Test character notification endpoint called")

    result = send_test_character_notification()

    response = case result do
      {:ok, character_id, character_name} ->
        %{
          success: true,
          message: "Test character notification sent for character: #{character_name} (ID: #{character_id})",
          details: "The notification was processed through the normal notification path. Check your Discord for the message."
        }

      {:error, :no_characters_available} ->
        %{
          success: false,
          message: "Failed to send test notification: No tracked characters available",
          details: "The system needs to have tracked characters before test notifications can be sent. Wait for character tracking to update or check your configuration."
        }

      {:error, reason} ->
        %{
          success: false,
          message: "Failed to send test notification: #{inspect(reason)}",
          details: "There was an error processing the notification. Check the application logs for more details."
        }
    end

    conn
    |> put_resp_content_type("application/json")
    |> send_resp(200, Jason.encode!(response))
  end

  # Endpoint to trigger a test system notification
  get "/api/test-system-notification" do
    Logger.info("Test system notification endpoint called")

    result = send_test_system_notification()

    response = case result do
      {:ok, system_id, system_name} ->
        %{
          success: true,
          message: "Test system notification sent for system: #{system_name} (ID: #{system_id})",
          details: "The notification was processed through the normal notification path. Check your Discord for the message."
        }

      {:error, :no_systems_available} ->
        %{
          success: false,
          message: "Failed to send test notification: No tracked systems available",
          details: "The system needs to have tracked systems before test notifications can be sent. Wait for system tracking to update or check your configuration."
        }

      {:error, reason} ->
        %{
          success: false,
          message: "Failed to send test notification: #{inspect(reason)}",
          details: "There was an error processing the notification. Check the application logs for more details."
        }
    end

    conn
    |> put_resp_content_type("application/json")
    |> send_resp(200, Jason.encode!(response))
  end

  # Endpoint to check characters endpoint availability
  get "/api/check-characters-endpoint" do
    Logger.info("Characters endpoint check requested")

    result = WandererNotifier.Map.Characters.check_characters_endpoint_availability()

    response = case result do
      {:ok, message} ->
        %{
          success: true,
          message: "Characters endpoint is available",
          details: message
        }

      {:error, reason} ->
        %{
          success: false,
          message: "Characters endpoint is not available",
          details: "Error: #{inspect(reason)}"
        }
    end

    conn
    |> put_resp_content_type("application/json")
    |> send_resp(200, Jason.encode!(response))
  end

  # Endpoint to revalidate the license
  get "/api/revalidate-license" do
    Logger.info("License revalidation requested")

    # Call the License.validate function to revalidate
    result = WandererNotifier.License.validate()

    response = case result do
      %{valid: true} ->
        %{
          success: true,
          message: "License validation successful",
          details: "The license is valid and has been revalidated with the license server."
        }

      %{valid: false, error_message: error_message} ->
        %{
          success: false,
          message: "License validation failed",
          details: "Error: #{error_message}"
        }
    end

    conn
    |> put_resp_content_type("application/json")
    |> send_resp(200, Jason.encode!(response))
  end

  defp calculate_percentage(_current, limit) when is_nil(limit), do: nil
  defp calculate_percentage(current, limit) when limit > 0, do: min(100, round(current / limit * 100))
  defp calculate_percentage(_, _), do: 0

  defp get_tracked_systems do
    CacheHelpers.get_tracked_systems()
  end

  # Helper function to send a test character notification
  defp send_test_character_notification do
    Logger.info("TEST NOTIFICATION: Manually triggering a test character notification")

    # Get the tracked characters from cache
    tracked_characters = CacheRepo.get("map:characters") || []
    Logger.info("TEST NOTIFICATION: Found #{length(tracked_characters)} tracked characters in cache")

    case tracked_characters do
      [] ->
        Logger.error("TEST NOTIFICATION: No tracked characters available for test notification")
        {:error, :no_characters_available}

      characters ->
        # Select a random character from the list
        character = Enum.random(characters)
        character_id = Map.get(character, "character_id") || Map.get(character, "eve_id")
        character_name = Map.get(character, "character_name") || "Unknown Character"

        Logger.info("TEST NOTIFICATION: Using character #{character_name} (ID: #{character_id}) for test notification")

        # Send the notification through the normal notification path
        Logger.info("TEST NOTIFICATION: Processing character through normal notification path")
        WandererNotifier.Discord.Notifier.send_new_tracked_character_notification(character)

        Logger.info("TEST NOTIFICATION: Successfully completed test character notification process")
        {:ok, character_id, character_name}
    end
  end

  # Helper function to send a test system notification
  defp send_test_system_notification do
    Logger.info("TEST NOTIFICATION: Manually triggering a test system notification")

    # Get the tracked systems from cache
    tracked_systems = get_tracked_systems()
    Logger.info("TEST NOTIFICATION: Found #{length(tracked_systems)} tracked systems in cache")

    case tracked_systems do
      [] ->
        Logger.error("TEST NOTIFICATION: No tracked systems available for test notification")
        {:error, :no_systems_available}

      systems ->
        # Select a random system from the list
        system = Enum.random(systems)

        # Log the full system data for debugging
        Logger.info("TEST NOTIFICATION: Full system data: #{inspect(system, pretty: true)}")

        system_id = Map.get(system, "system_id") || Map.get(system, :system_id)
        system_name = Map.get(system, "system_name") || Map.get(system, :alias) || Map.get(system, "name") || "Unknown System"
        original_name = Map.get(system, "original_name")
        temporary_name = Map.get(system, "temporary_name")

        Logger.info("TEST NOTIFICATION: Using system #{system_name} (ID: #{system_id}) for test notification")
        Logger.info("TEST NOTIFICATION: System details - original_name: #{inspect(original_name)}, temporary_name: #{inspect(temporary_name)}")

        # Send the notification through the normal notification path
        Logger.info("TEST NOTIFICATION: Processing system through normal notification path")
        WandererNotifier.Discord.Notifier.send_new_system_notification(system)

        Logger.info("TEST NOTIFICATION: Successfully completed test system notification process")
        {:ok, system_id, system_name}
    end
  end

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
        .progress-container {
          width: 100%;
          background-color: #e9ecef;
          border-radius: 4px;
          margin: 5px 0;
          height: 10px;
        }
        .progress-bar {
          height: 100%;
          border-radius: 4px;
          background-color: #4caf50;
        }
        .progress-bar.warning {
          background-color: #ff9800;
        }
        .progress-bar.danger {
          background-color: #f44336;
        }
        .stat-box {
          margin-bottom: 10px;
        }
        .stat-label {
          font-weight: bold;
          margin-right: 5px;
        }
        .refresh-button {
          background-color: #4caf50;
          color: white;
          border: none;
          padding: 10px 15px;
          border-radius: 4px;
          cursor: pointer;
          font-size: 16px;
          margin-top: 20px;
        }
        .refresh-button:hover {
          background-color: #45a049;
        }
        .action-button {
          background-color: #2196F3;
          color: white;
          border: none;
          padding: 10px 15px;
          border-radius: 4px;
          cursor: pointer;
          font-size: 14px;
          margin-right: 10px;
          margin-bottom: 15px;
        }
        .action-button:hover {
          background-color: #0b7dda;
        }
        .result-success {
          background-color: #d4edda;
          color: #155724;
          padding: 10px;
          border-radius: 4px;
          margin-top: 10px;
        }
        .result-error {
          background-color: #f8d7da;
          color: #721c24;
          padding: 10px;
          border-radius: 4px;
          margin-top: 10px;
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
          <button class="action-button" onclick="revalidateLicense()">Revalidate License</button>
          <div id="license-revalidation-result"></div>
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

      <div class="card">
        <h2>Test Notifications</h2>
        <p>Use these buttons to test different types of notifications:</p>
        <button class="action-button" onclick="sendTestNotification()">Send Test Kill Notification</button>
        <button class="action-button" onclick="sendTestCharacterNotification()">Send Test Character Notification</button>
        <button class="action-button" onclick="sendTestSystemNotification()">Send Test System Notification</button>
        <div id="test-notification-result"></div>
      </div>

      <button class="refresh-button" onclick="refreshData()">Refresh Data</button>

      <script>
        // Fetch status data from the API
        function fetchStatus() {
          fetch('/api/status')
            .then(response => response.json())
            .then(data => {
              updateLicenseStatus(data.license);
              updateSystemStatus(data.stats);
              updateFeatureStatus(data.features);
              updateResourceUsage(data.features.usage);
              updateNotificationStats(data.stats);
            })
            .catch(error => {
              console.error('Error fetching status:', error);
            });
        }

        // Send a test kill notification
        function sendTestNotification() {
          const resultElement = document.getElementById('test-notification-result');
          resultElement.innerHTML = 'Sending test notification...';

          fetch('/api/test-notification')
            .then(response => response.json())
            .then(data => {
              if (data.success) {
                resultElement.innerHTML = `
                  <div class="result-success">
                    <p><strong>${data.message}</strong></p>
                    <p>${data.details || ''}</p>
                  </div>`;
              } else {
                resultElement.innerHTML = `
                  <div class="result-error">
                    <p><strong>${data.message}</strong></p>
                    <p>${data.details || ''}</p>
                  </div>`;
              }
            })
            .catch(error => {
              console.error('Error sending test notification:', error);
              resultElement.innerHTML = `<div class="result-error">Error: ${error.message}</div>`;
            });
        }

        // Send a test character notification
        function sendTestCharacterNotification() {
          const resultElement = document.getElementById('test-notification-result');
          resultElement.innerHTML = 'Sending test character notification...';

          fetch('/api/test-character-notification')
            .then(response => response.json())
            .then(data => {
              if (data.success) {
                resultElement.innerHTML = `
                  <div class="result-success">
                    <p><strong>${data.message}</strong></p>
                    <p>${data.details || ''}</p>
                  </div>`;
              } else {
                resultElement.innerHTML = `
                  <div class="result-error">
                    <p><strong>${data.message}</strong></p>
                    <p>${data.details || ''}</p>
                  </div>`;
              }
            })
            .catch(error => {
              console.error('Error sending test character notification:', error);
              resultElement.innerHTML = `<div class="result-error">Error: ${error.message}</div>`;
            });
        }

        // Send a test system notification
        function sendTestSystemNotification() {
          const resultElement = document.getElementById('test-notification-result');
          resultElement.innerHTML = 'Sending test system notification...';

          fetch('/api/test-system-notification')
            .then(response => response.json())
            .then(data => {
              if (data.success) {
                resultElement.innerHTML = `
                  <div class="result-success">
                    <p><strong>${data.message}</strong></p>
                    <p>${data.details || ''}</p>
                  </div>`;
              } else {
                resultElement.innerHTML = `
                  <div class="result-error">
                    <p><strong>${data.message}</strong></p>
                    <p>${data.details || ''}</p>
                  </div>`;
              }
            })
            .catch(error => {
              console.error('Error sending test system notification:', error);
              resultElement.innerHTML = `<div class="result-error">Error: ${error.message}</div>`;
            });
        }

        // Revalidate license with the license server
        function revalidateLicense() {
          const resultElement = document.getElementById('license-revalidation-result');
          resultElement.innerHTML = 'Revalidating license...';

          fetch('/api/revalidate-license')
            .then(response => response.json())
            .then(data => {
              if (data.success) {
                resultElement.innerHTML = `
                  <div class="result-success">
                    <p><strong>${data.message}</strong></p>
                    <p>${data.details || ''}</p>
                  </div>`;
                // Refresh the license status display
                fetchStatus();
              } else {
                resultElement.innerHTML = `
                  <div class="result-error">
                    <p><strong>${data.message}</strong></p>
                    <p>${data.details || ''}</p>
                  </div>`;
              }
            })
            .catch(error => {
              console.error('Error revalidating license:', error);
              resultElement.innerHTML = `<div class="result-error">Error: ${error.message}</div>`;
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
          const featuresElement = document.getElementById('feature-status');

          if (!features || !features.enabled) {
            featuresElement.innerHTML = 'No feature information available';
            return;
          }

          const enabled = features.enabled;
          const config = features.config || {};

          let featuresHtml = '<h3>Features</h3>';

          // Add feature status
          featuresHtml += createFeatureStatusItem('Basic Notifications', enabled.basic_notifications);
          featuresHtml += createFeatureStatusItem('Tracked Systems Notifications', enabled.tracked_systems_notifications);
          featuresHtml += createFeatureStatusItem('Tracked Characters Notifications', enabled.tracked_characters_notifications);
          featuresHtml += createFeatureStatusItem('Backup Kills Processing', enabled.backup_kills_processing);
          featuresHtml += createFeatureStatusItem('Web Dashboard (Full)', enabled.web_dashboard_full);
          featuresHtml += createFeatureStatusItem('Advanced Statistics', enabled.advanced_statistics);

          // Add configuration status
          if (Object.keys(config).length > 0) {
            featuresHtml += '<h3>Configuration</h3>';
            featuresHtml += createFeatureStatusItem('Character Tracking', config.character_tracking_enabled);
            featuresHtml += createFeatureStatusItem('Character Notifications', config.character_notifications_enabled);
            featuresHtml += createFeatureStatusItem('System Notifications', config.system_notifications_enabled);
            featuresHtml += '<div class="info-box"><p>To change these settings, update your environment variables:</p>' +
                           '<ul>' +
                           '<li><code>ENABLE_CHARACTER_TRACKING=false</code> - Disable character tracking</li>' +
                           '<li><code>ENABLE_CHARACTER_NOTIFICATIONS=false</code> - Disable character notifications</li>' +
                           '<li><code>ENABLE_SYSTEM_NOTIFICATIONS=false</code> - Disable system notifications</li>' +
                           '</ul></div>';
          }

          featuresElement.innerHTML = featuresHtml;
        }

        function createFeatureStatusItem(name, enabled) {
          return `
            <div class="feature-item">
              <div class="feature-status ${enabled ? 'feature-enabled' : 'feature-disabled'}"></div>
              <span>${name}</span>
            </div>
          `;
        }

        // Update resource usage display
        function updateResourceUsage(usage) {
          const usageElement = document.getElementById('resource-usage');

          if (!usage) {
            usageElement.innerHTML = 'No usage information available';
            return;
          }

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

        // Update notification statistics display
        function updateNotificationStats(stats) {
          const notificationElement = document.getElementById('notification-stats');

          if (!stats || !stats.notifications) {
            notificationElement.innerHTML = 'No notification statistics available';
            return;
          }

          const notifications = stats.notifications;
          let notificationHtml = '';

          notificationHtml += `<div class="stat-box"><span class="stat-label">Total:</span> ${notifications.total}</div>`;
          notificationHtml += `<div class="stat-box"><span class="stat-label">Kills:</span> ${notifications.kills}</div>`;
          notificationHtml += `<div class="stat-box"><span class="stat-label">Systems:</span> ${notifications.systems}</div>`;
          notificationHtml += `<div class="stat-box"><span class="stat-label">Characters:</span> ${notifications.characters}</div>`;
          notificationHtml += `<div class="stat-box"><span class="stat-label">Errors:</span> ${notifications.errors}</div>`;

          notificationElement.innerHTML = notificationHtml;
        }

        // Update system status display
        function updateSystemStatus(stats) {
          const uptimeElement = document.getElementById('uptime');
          const websocketElement = document.getElementById('websocket-status');

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
