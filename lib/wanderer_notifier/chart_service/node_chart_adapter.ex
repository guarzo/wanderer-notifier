defmodule WandererNotifier.ChartService.NodeChartAdapter do
  @moduledoc """
  Adapter for generating charts using the Node.js Chart.js service.

  This adapter communicates with a Node.js service that uses Chart.js to generate
  charts server-side. It handles the HTTP communication and data conversion between
  Elixir and the Node.js service.
  """

  alias WandererNotifier.Api.Http.Client, as: HttpClient
  alias WandererNotifier.ChartService.ChartConfigHandler
  alias WandererNotifier.ChartService.ChartServiceManager
  alias WandererNotifier.Config.Web
  alias WandererNotifier.Logger.Logger, as: AppLogger

  # Configuration
  @tmp_chart_dir "/tmp/wanderer_notifier_charts"

  # Get the chart service URL from the manager
  defp get_chart_service_url do
    default_url = "http://localhost:#{Web.get_chart_service_port()}"

    if Process.whereis(ChartServiceManager) do
      try do
        # Add timeout to prevent hanging if the manager is not responding
        case GenServer.call(ChartServiceManager, :get_url, 1000) do
          url when is_binary(url) ->
            url

          _ ->
            AppLogger.api_warn("ChartServiceManager returned invalid URL, using default")
            default_url
        end
      rescue
        e ->
          AppLogger.api_warn("Error getting URL from ChartServiceManager", error: inspect(e))
          default_url
      catch
        :exit, {:timeout, _} ->
          AppLogger.api_warn("Timeout getting URL from ChartServiceManager")
          default_url

        :exit, reason ->
          AppLogger.api_warn("Exit when getting URL from ChartServiceManager",
            error: inspect(reason)
          )

          default_url
      end
    else
      AppLogger.api_debug("ChartServiceManager process not found, using default URL")
      default_url
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
            AppLogger.api_error("Node chart service error", message: message)
            {:error, "Node chart service error: #{message}"}

          {:error, reason} ->
            AppLogger.api_error("Failed to parse chart service response", error: inspect(reason))
            {:error, "Failed to parse chart service response"}
        end

      {:ok, %{status_code: status_code, body: body}} ->
        AppLogger.api_error("Chart service returned error status",
          status_code: status_code,
          response: body
        )

        {:error, "Chart service error (HTTP #{status_code})"}

      {:error, reason} ->
        AppLogger.api_error("Failed to communicate with chart service", error: inspect(reason))
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
            AppLogger.api_error("Node chart service error", message: message)
            {:error, "Node chart service error: #{message}"}

          {:error, reason} ->
            AppLogger.api_error("Failed to parse chart service response",
              error: inspect(reason)
            )

            {:error, "Failed to parse chart service response"}
        end

      {:ok, %{status_code: status_code, body: body}} ->
        AppLogger.api_error("Chart service returned error status",
          status_code: status_code,
          response: body
        )

        {:error, "Chart service error (HTTP #{status_code})"}

      {:error, reason} ->
        AppLogger.api_error("Failed to communicate with chart service", error: inspect(reason))
        {:error, "Failed to communicate with chart service"}
    end
  rescue
    e ->
      AppLogger.api_error("Exception calling chart service",
        error: inspect(e),
        stacktrace: Exception.format_stacktrace(__STACKTRACE__)
      )

      {:error, "Exception calling chart service: #{inspect(e)}"}
  end

  defp call_chart_service_save(chart_map, filename, width, height, background_color) do
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
            AppLogger.api_error("Node chart service error", message: message)
            {:error, "Node chart service error: #{message}"}

          {:error, reason} ->
            AppLogger.api_error("Failed to parse chart service response",
              error: inspect(reason)
            )

            {:error, "Failed to parse chart service response"}
        end

      {:ok, %{status_code: status_code, body: body}} ->
        AppLogger.api_error("Chart service returned error status",
          status_code: status_code,
          response: body
        )

        {:error, "Chart service error (HTTP #{status_code})"}

      {:error, reason} ->
        AppLogger.api_error("Failed to communicate with chart service", error: inspect(reason))
        {:error, "Failed to communicate with chart service"}
    end
  rescue
    e ->
      AppLogger.api_error("Exception calling chart service",
        error: inspect(e),
        stacktrace: Exception.format_stacktrace(__STACKTRACE__)
      )

      {:error, "Exception calling chart service: #{inspect(e)}"}
  end
end
