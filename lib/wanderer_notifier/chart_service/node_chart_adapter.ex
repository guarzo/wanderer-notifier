defmodule WandererNotifier.ChartService.NodeChartAdapter do
  @moduledoc """
  Adapter for generating charts using the Node.js Chart.js service.

  This adapter communicates with a Node.js service that uses Chart.js to generate
  charts server-side. It handles the HTTP communication and data conversion between
  Elixir and the Node.js service.
  """

  require Logger
  alias WandererNotifier.Api.Http.Client, as: HttpClient
  # ChartConfig no longer used directly, handled by ChartConfigHandler
  # alias WandererNotifier.ChartService.ChartConfig
  alias WandererNotifier.ChartService.ChartConfigHandler

  # Configuration
  @tmp_chart_dir "/tmp/wanderer_notifier_charts"

  # Get the chart service URL from the manager
  defp get_chart_service_url do
    # If the manager is running, get the URL from it
    if Process.whereis(WandererNotifier.ChartService.ChartServiceManager) do
      try do
        # Add timeout to prevent hanging if the manager is not responding
        case GenServer.call(WandererNotifier.ChartService.ChartServiceManager, :get_url, 1000) do
          url when is_binary(url) ->
            url

          _ ->
            Logger.warning("ChartServiceManager returned invalid URL, using default")
            "http://localhost:3001"
        end
      rescue
        # Just handle general exceptions
        e ->
          Logger.warning("Error getting URL from ChartServiceManager: #{inspect(e)}")
          "http://localhost:3001"
      catch
        :exit, {:timeout, _} ->
          Logger.warning("Timeout getting URL from ChartServiceManager")
          "http://localhost:3001"

        :exit, reason ->
          Logger.warning("Exit when getting URL from ChartServiceManager: #{inspect(reason)}")
          "http://localhost:3001"
      end
    else
      # Fallback to default URL if manager is not available
      Logger.debug("ChartServiceManager process not found, using default URL")
      "http://localhost:3001"
    end
  end

  @doc """
  Generates a chart image from a chart configuration.

  ## Parameters
    - config: A %ChartConfig{} struct or a map with chart configuration

  ## Returns
    - {:ok, image_binary} on success
    - {:error, reason} on failure
  """
  def generate_chart_image(config) do
    # Use the handler to normalize and prepare the configuration
    case ChartConfigHandler.prepare_for_node_service(config) do
      {:ok, %{chart: chart_map, width: width, height: height, background_color: bg_color}} ->
        # Call the chart service
        call_chart_service_generate(chart_map, width, height, bg_color)

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Creates a "No Data Available" chart with customized message.

  ## Parameters
    - title: Chart title
    - message: Custom message to display (optional)

  ## Returns
    - {:ok, image_binary} with the chart image binary
  """
  def create_no_data_chart(title, message \\ "No data available for this chart") do
    # Prepare the request body
    body = %{
      "title" => title,
      "message" => message
    }

    # Call the chart service
    url = "#{get_chart_service_url()}/generate-no-data"
    headers = [{"Content-Type", "application/json"}]

    case HttpClient.request("POST", url, headers, Jason.encode!(body)) do
      {:ok, %{status_code: 200, body: response_body}} ->
        case Jason.decode(response_body) do
          {:ok, %{"success" => true, "imageData" => image_data}} ->
            {:ok, Base.decode64!(image_data)}

          {:ok, %{"success" => false, "message" => message}} ->
            Logger.error("Node chart service error: #{message}")
            {:error, "Node chart service error: #{message}"}

          {:error, reason} ->
            Logger.error("Failed to parse chart service response: #{inspect(reason)}")
            {:error, "Failed to parse chart service response"}
        end

      {:ok, %{status_code: status_code, body: body}} ->
        Logger.error("Chart service returned status #{status_code}: #{body}")
        {:error, "Chart service error (HTTP #{status_code})"}

      {:error, reason} ->
        Logger.error("Failed to communicate with chart service: #{inspect(reason)}")
        {:error, "Failed to communicate with chart service"}
    end
  end

  @doc """
  Generates a chart and saves it to a temporary file.

  ## Parameters
    - config: A %ChartConfig{} struct or a map with chart configuration
    - filename: The filename to save the chart as (without path)

  ## Returns
    - {:ok, file_path} on success
    - {:error, reason} on failure
  """
  def generate_chart_file(config, filename) do
    # Use the handler to normalize and prepare the configuration
    case ChartConfigHandler.prepare_for_node_service(config) do
      {:ok, %{chart: chart_map, width: width, height: height, background_color: bg_color}} ->
        # Generate a proper filename with extension
        final_filename = ChartConfigHandler.generate_filename(filename)

        # Call the chart service
        call_chart_service_save(chart_map, final_filename, width, height, bg_color)

      {:error, reason} ->
        {:error, reason}
    end
  end

  # Private helpers

  defp call_chart_service_generate(chart_map, width, height, background_color) do
    try do
      # Prepare the request body
      body = %{
        "chart" => chart_map,
        "width" => width,
        "height" => height,
        "backgroundColor" => background_color
      }

      # Call the chart service
      url = "#{get_chart_service_url()}/generate"
      headers = [{"Content-Type", "application/json"}]

      case HttpClient.request("POST", url, headers, Jason.encode!(body)) do
        {:ok, %{status_code: 200, body: response_body}} ->
          case Jason.decode(response_body) do
            {:ok, %{"success" => true, "imageData" => image_data}} ->
              {:ok, Base.decode64!(image_data)}

            {:ok, %{"success" => false, "message" => message}} ->
              Logger.error("Node chart service error: #{message}")
              {:error, "Node chart service error: #{message}"}

            {:error, reason} ->
              Logger.error("Failed to parse chart service response: #{inspect(reason)}")
              {:error, "Failed to parse chart service response"}
          end

        {:ok, %{status_code: status_code, body: body}} ->
          Logger.error("Chart service returned status #{status_code}: #{body}")
          {:error, "Chart service error (HTTP #{status_code})"}

        {:error, reason} ->
          Logger.error("Failed to communicate with chart service: #{inspect(reason)}")
          {:error, "Failed to communicate with chart service"}
      end
    rescue
      e ->
        Logger.error("Exception calling chart service: #{inspect(e)}")
        {:error, "Exception calling chart service: #{inspect(e)}"}
    end
  end

  defp call_chart_service_save(chart_map, filename, width, height, background_color) do
    try do
      # Ensure the temporary directory exists
      File.mkdir_p!(@tmp_chart_dir)

      # filename has already been processed by ChartConfigHandler.generate_filename

      # Prepare the request body
      body = %{
        "chart" => chart_map,
        "fileName" => filename,
        "width" => width,
        "height" => height,
        "backgroundColor" => background_color
      }

      # Call the chart service
      url = "#{get_chart_service_url()}/save"
      headers = [{"Content-Type", "application/json"}]

      case HttpClient.request("POST", url, headers, Jason.encode!(body)) do
        {:ok, %{status_code: 200, body: response_body}} ->
          case Jason.decode(response_body) do
            {:ok, %{"success" => true, "filePath" => file_path}} ->
              # Use the file path returned by the service
              # We could copy to our own directory, but we'll just use the service's path
              # _local_path = Path.join(@tmp_chart_dir, final_filename)

              {:ok, file_path}

            {:ok, %{"success" => false, "message" => message}} ->
              Logger.error("Node chart service error: #{message}")
              {:error, "Node chart service error: #{message}"}

            {:error, reason} ->
              Logger.error("Failed to parse chart service response: #{inspect(reason)}")
              {:error, "Failed to parse chart service response"}
          end

        {:ok, %{status_code: status_code, body: body}} ->
          Logger.error("Chart service returned status #{status_code}: #{body}")
          {:error, "Chart service error (HTTP #{status_code})"}

        {:error, reason} ->
          Logger.error("Failed to communicate with chart service: #{inspect(reason)}")
          {:error, "Failed to communicate with chart service"}
      end
    rescue
      e ->
        Logger.error("Exception calling chart service: #{inspect(e)}")
        {:error, "Exception calling chart service: #{inspect(e)}"}
    end
  end
end
