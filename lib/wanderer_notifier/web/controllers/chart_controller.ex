defmodule WandererNotifier.Web.ChartController do
  @moduledoc """
  Controller for chart generation and preview.
  """
  require Logger
  alias WandererNotifier.CorpTools.JSChartAdapter
  alias WandererNotifier.CorpTools.TPSDataInspector
  alias WandererNotifier.CorpTools.Client, as: CorpToolsClient

  @doc """
  Handles GET requests to /charts
  Renders the chart dashboard page.
  """
  def index(conn) do
    conn
    |> Plug.Conn.put_resp_content_type("text/html")
    |> Plug.Conn.send_resp(200, render_chart_dashboard())
  end

  @doc """
  Handles GET requests to /charts/generate
  Generates a chart and returns the URL.
  """
  def generate(conn) do
    chart_type = conn.params["type"]
    title = conn.params["title"] || default_title_for_chart_type(chart_type)
    description = conn.params["description"] || default_description_for_chart_type(chart_type)

    Logger.info("Generating chart with type: #{inspect(chart_type)}, title: #{inspect(title)}, description: #{inspect(description)}")

    result = case chart_type do
      "damage_final_blows" ->
        Logger.info("Generating damage_final_blows chart")
        JSChartAdapter.generate_damage_final_blows_chart()
      "combined_losses" ->
        Logger.info("Generating combined_losses chart")
        JSChartAdapter.generate_combined_losses_chart()
      "kill_activity" ->
        Logger.info("Generating kill_activity chart")
        JSChartAdapter.generate_kill_activity_chart()
      _ ->
        Logger.error("Invalid chart type: #{inspect(chart_type)}")
        {:error, "Invalid chart type"}
    end

    Logger.info("Chart generation result: #{inspect(result)}")

    case result do
      {:ok, url} ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.send_resp(200, Jason.encode!(%{
          success: true,
          url: url,
          title: title,
          description: description
        }))
      {:error, reason} ->
        Logger.error("Chart generation failed: #{inspect(reason)}")
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.send_resp(400, Jason.encode!(%{
          success: false,
          error: reason
        }))
    end
  end

  @doc """
  Handles POST requests to /charts/send
  Sends a chart to Discord.
  """
  def send_chart(conn) do
    chart_type = conn.params["type"]
    title = conn.params["title"] || default_title_for_chart_type(chart_type)
    description = conn.params["description"] || default_description_for_chart_type(chart_type)

    chart_type_atom = case chart_type do
      "damage_final_blows" -> :damage_final_blows
      "combined_losses" -> :combined_losses
      "kill_activity" -> :kill_activity
      _ -> :invalid
    end

    if chart_type_atom == :invalid do
      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.send_resp(400, Jason.encode!(%{
        success: false,
        error: "Invalid chart type"
      }))
    else
      result = JSChartAdapter.send_chart_to_discord(chart_type_atom, title, description)

      case result do
        :ok ->
          conn
          |> Plug.Conn.put_resp_content_type("application/json")
          |> Plug.Conn.send_resp(200, Jason.encode!(%{
            success: true,
            message: "Chart sent to Discord"
          }))
        {:error, reason} ->
          conn
          |> Plug.Conn.put_resp_content_type("application/json")
          |> Plug.Conn.send_resp(400, Jason.encode!(%{
            success: false,
            error: reason
          }))
      end
    end
  end

  @doc """
  Handles GET requests to /charts/tps-data
  Returns the TPS data structure.
  """
  def tps_data(conn) do
    case CorpToolsClient.get_tps_data() do
      {:ok, data} ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.send_resp(200, Jason.encode!(%{
          success: true,
          data: data
        }))
      {:loading, message} ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.send_resp(202, Jason.encode!(%{
          success: false,
          status: "loading",
          message: message
        }))
      {:error, reason} ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.send_resp(400, Jason.encode!(%{
          success: false,
          error: reason
        }))
    end
  end

  @doc """
  Handles GET requests to /charts/debug-tps-structure
  Returns the TPS data structure for debugging.
  """
  def debug_tps_structure(conn) do
    result = JSChartAdapter.debug_tps_data_structure()

    case result do
      {:ok, data} ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.send_resp(200, Jason.encode!(%{
          success: true,
          message: "TPS data structure retrieved successfully",
          data: data
        }))
      {:loading, message} ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.send_resp(202, Jason.encode!(%{
          success: false,
          status: "loading",
          message: message
        }))
      {:error, reason} ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.send_resp(400, Jason.encode!(%{
          success: false,
          error: reason
        }))
    end
  end

  # Helper functions

  defp default_title_for_chart_type(chart_type) do
    case chart_type do
      "damage_final_blows" -> "Damage and Final Blows Analysis"
      "combined_losses" -> "Combined Losses Analysis"
      "kill_activity" -> "Kill Activity Over Time"
      _ -> "EVE Corp Tools Chart"
    end
  end

  defp default_description_for_chart_type(chart_type) do
    case chart_type do
      "damage_final_blows" -> "Top 20 characters by damage done and final blows"
      "combined_losses" -> "Top 10 characters by losses value and count"
      "kill_activity" -> "Kill activity trend over time"
      _ -> "Generated chart from EVE Corp Tools data"
    end
  end

  defp render_chart_dashboard do
    """
    <!DOCTYPE html>
    <html lang="en">
    <head>
      <meta charset="UTF-8">
      <meta name="viewport" content="width=device-width, initial-scale=1.0">
      <title>EVE Corp Tools Charts</title>
      <style>
        body {
          font-family: Arial, sans-serif;
          margin: 0;
          padding: 20px;
          background-color: #1e1e1e;
          color: #f0f0f0;
        }
        .container {
          max-width: 1200px;
          margin: 0 auto;
        }
        h1, h2 {
          color: #4da6ff;
        }
        .chart-controls {
          margin-bottom: 20px;
          padding: 15px;
          background-color: #2d2d2d;
          border-radius: 5px;
        }
        .form-group {
          margin-bottom: 15px;
        }
        label {
          display: block;
          margin-bottom: 5px;
          font-weight: bold;
        }
        select, input, textarea {
          width: 100%;
          padding: 8px;
          border: 1px solid #444;
          border-radius: 4px;
          background-color: #333;
          color: #f0f0f0;
        }
        button {
          padding: 10px 15px;
          background-color: #4da6ff;
          color: white;
          border: none;
          border-radius: 4px;
          cursor: pointer;
          margin-right: 10px;
        }
        button:hover {
          background-color: #3a8ad6;
        }
        .chart-preview {
          margin-top: 20px;
          padding: 15px;
          background-color: #2d2d2d;
          border-radius: 5px;
          min-height: 200px;
        }
        .chart-image {
          max-width: 100%;
          height: auto;
          display: block;
          margin: 0 auto;
        }
        .error {
          color: #ff6b6b;
          margin-top: 10px;
        }
        .success {
          color: #6bff6b;
          margin-top: 10px;
        }
        .loading {
          text-align: center;
          padding: 20px;
        }
        .button-group {
          display: flex;
          gap: 10px;
        }
        .tps-data {
          margin-top: 20px;
          padding: 15px;
          background-color: #2d2d2d;
          border-radius: 5px;
          overflow: auto;
          max-height: 300px;
        }
        pre {
          margin: 0;
          white-space: pre-wrap;
          word-wrap: break-word;
        }
        .debug-info {
          margin-top: 20px;
          padding: 15px;
          background-color: #2d2d2d;
          border-radius: 5px;
          font-family: monospace;
          font-size: 12px;
        }
      </style>
    </head>
    <body>
      <div class="container">
        <h1>EVE Corp Tools Charts</h1>

        <div class="chart-controls">
          <h2>Generate Chart</h2>
          <div class="form-group">
            <label for="chart-type">Chart Type:</label>
            <select id="chart-type">
              <option value="damage_final_blows">Damage and Final Blows</option>
              <option value="combined_losses">Combined Losses</option>
              <option value="kill_activity">Kill Activity Over Time</option>
            </select>
          </div>

          <div class="form-group">
            <label for="chart-title">Title:</label>
            <input type="text" id="chart-title" placeholder="Enter chart title">
          </div>

          <div class="form-group">
            <label for="chart-description">Description:</label>
            <textarea id="chart-description" rows="2" placeholder="Enter chart description"></textarea>
          </div>

          <div class="button-group">
            <button id="generate-btn">Generate Chart</button>
            <button id="send-btn">Send to Discord</button>
            <button id="view-tps-data-btn">View TPS Data</button>
            <button id="debug-tps-structure-btn">Debug TPS Structure</button>
          </div>

          <div id="status-message"></div>
        </div>

        <div class="chart-preview" id="chart-preview">
          <h2>Chart Preview</h2>
          <div id="chart-container"></div>
        </div>

        <div class="tps-data" id="tps-data-container" style="display: none;">
          <h2>TPS Data</h2>
          <pre id="tps-data-content"></pre>
        </div>

        <div class="debug-info">
          <h2>Debug Information</h2>
          <p>Current URL: <span id="current-url"></span></p>
          <p>API Base URL: <span id="api-base-url"></span></p>
        </div>
      </div>

      <script>
        document.addEventListener('DOMContentLoaded', function() {
          const chartTypeSelect = document.getElementById('chart-type');
          const chartTitleInput = document.getElementById('chart-title');
          const chartDescriptionInput = document.getElementById('chart-description');
          const generateBtn = document.getElementById('generate-btn');
          const sendBtn = document.getElementById('send-btn');
          const viewTpsDataBtn = document.getElementById('view-tps-data-btn');
          const debugTpsStructureBtn = document.getElementById('debug-tps-structure-btn');
          const statusMessage = document.getElementById('status-message');
          const chartContainer = document.getElementById('chart-container');
          const tpsDataContainer = document.getElementById('tps-data-container');
          const tpsDataContent = document.getElementById('tps-data-content');
          const currentUrlElement = document.getElementById('current-url');
          const apiBaseUrlElement = document.getElementById('api-base-url');

          // Set debug information
          currentUrlElement.textContent = window.location.href;

          // Determine the API base URL based on the current URL
          const currentUrl = new URL(window.location.href);
          const apiBaseUrl = `${currentUrl.protocol}//${currentUrl.hostname}:${currentUrl.port}`;
          apiBaseUrlElement.textContent = apiBaseUrl;

          // Update title and description based on chart type
          chartTypeSelect.addEventListener('change', function() {
            updateDefaultValues();
          });

          // Initialize with default values
          updateDefaultValues();

          // Generate chart
          generateBtn.addEventListener('click', function() {
            statusMessage.innerHTML = '<div class="loading">Generating chart...</div>';
            chartContainer.innerHTML = '';

            const chartType = chartTypeSelect.value;
            const title = chartTitleInput.value;
            const description = chartDescriptionInput.value;

            fetch(`${apiBaseUrl}/charts/generate?type=${chartType}&title=${encodeURIComponent(title)}&description=${encodeURIComponent(description)}`)
              .then(response => {
                if (!response.ok) {
                  return response.json().then(data => {
                    throw new Error(data.error || `HTTP error ${response.status}`);
                  });
                }
                return response.json();
              })
              .then(data => {
                if (data.success) {
                  statusMessage.innerHTML = '<div class="success">Chart generated successfully!</div>';
                  chartContainer.innerHTML = `<img src="${data.url}" alt="${data.title}" class="chart-image">`;
                } else {
                  statusMessage.innerHTML = `<div class="error">Error: ${data.error}</div>`;
                }
              })
              .catch(error => {
                statusMessage.innerHTML = `<div class="error">Error: ${error.message}</div>`;
                console.error('Error generating chart:', error);
              });
          });

          // Send chart to Discord
          sendBtn.addEventListener('click', function() {
            statusMessage.innerHTML = '<div class="loading">Sending chart to Discord...</div>';

            const chartType = chartTypeSelect.value;
            const title = chartTitleInput.value;
            const description = chartDescriptionInput.value;

            fetch(`${apiBaseUrl}/charts/send`, {
              method: 'POST',
              headers: {
                'Content-Type': 'application/json',
              },
              body: JSON.stringify({
                type: chartType,
                title: title,
                description: description
              })
            })
              .then(response => {
                if (!response.ok) {
                  return response.json().then(data => {
                    throw new Error(data.error || `HTTP error ${response.status}`);
                  });
                }
                return response.json();
              })
              .then(data => {
                if (data.success) {
                  statusMessage.innerHTML = '<div class="success">Chart sent to Discord successfully!</div>';
                } else {
                  statusMessage.innerHTML = `<div class="error">Error: ${data.error}</div>`;
                }
              })
              .catch(error => {
                statusMessage.innerHTML = `<div class="error">Error: ${error.message}</div>`;
                console.error('Error sending chart to Discord:', error);
              });
          });

          // View TPS data
          viewTpsDataBtn.addEventListener('click', function() {
            statusMessage.innerHTML = '<div class="loading">Fetching TPS data...</div>';
            tpsDataContainer.style.display = 'block';
            tpsDataContent.textContent = 'Loading...';

            fetch(`${apiBaseUrl}/charts/tps-data`)
              .then(response => {
                if (!response.ok) {
                  return response.json().then(data => {
                    throw new Error(data.error || `HTTP error ${response.status}`);
                  });
                }
                return response.json();
              })
              .then(data => {
                if (data.success) {
                  statusMessage.innerHTML = '<div class="success">TPS data fetched successfully!</div>';
                  tpsDataContent.textContent = JSON.stringify(data.data, null, 2);
                } else if (data.status === 'loading') {
                  statusMessage.innerHTML = `<div class="loading">TPS data is still loading: ${data.message}</div>`;
                  tpsDataContent.textContent = data.message;
                } else {
                  statusMessage.innerHTML = `<div class="error">Error: ${data.error}</div>`;
                  tpsDataContent.textContent = `Error: ${data.error}`;
                }
              })
              .catch(error => {
                statusMessage.innerHTML = `<div class="error">Error: ${error.message}</div>`;
                tpsDataContent.textContent = `Error: ${error.message}`;
                console.error('Error fetching TPS data:', error);
              });
          });

          // Debug TPS structure
          debugTpsStructureBtn.addEventListener('click', function() {
            statusMessage.innerHTML = '<div class="loading">Fetching TPS structure...</div>';
            tpsDataContainer.style.display = 'block';
            tpsDataContent.textContent = 'Loading...';

            fetch(`${apiBaseUrl}/charts/debug-tps-structure`)
              .then(response => {
                if (!response.ok) {
                  return response.json().then(data => {
                    throw new Error(data.error || `HTTP error ${response.status}`);
                  });
                }
                return response.json();
              })
              .then(data => {
                if (data.success) {
                  statusMessage.innerHTML = '<div class="success">TPS structure fetched successfully!</div>';
                  tpsDataContent.textContent = JSON.stringify(data.data, null, 2);
                } else if (data.status === 'loading') {
                  statusMessage.innerHTML = `<div class="loading">TPS data is still loading: ${data.message}</div>`;
                  tpsDataContent.textContent = data.message;
                } else {
                  statusMessage.innerHTML = `<div class="error">Error: ${data.error}</div>`;
                  tpsDataContent.textContent = `Error: ${data.error}`;
                }
              })
              .catch(error => {
                statusMessage.innerHTML = `<div class="error">Error: ${error.message}</div>`;
                tpsDataContent.textContent = `Error: ${error.message}`;
                console.error('Error fetching TPS structure:', error);
              });
          });

          // Helper function to update default values
          function updateDefaultValues() {
            const chartType = chartTypeSelect.value;

            switch (chartType) {
              case 'damage_final_blows':
                chartTitleInput.value = 'Damage and Final Blows Analysis';
                chartDescriptionInput.value = 'Top 20 characters by damage done and final blows';
                break;
              case 'combined_losses':
                chartTitleInput.value = 'Combined Losses Analysis';
                chartDescriptionInput.value = 'Top 10 characters by losses value and count';
                break;
              case 'kill_activity':
                chartTitleInput.value = 'Kill Activity Over Time';
                chartDescriptionInput.value = 'Kill activity trend over time';
                break;
              default:
                chartTitleInput.value = 'EVE Corp Tools Chart';
                chartDescriptionInput.value = 'Generated chart from EVE Corp Tools data';
            }
          }
        });
      </script>
    </body>
    </html>
    """
  end
end
