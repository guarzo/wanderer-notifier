defmodule WandererNotifier.ChartService do
  @moduledoc """
  Unified service for chart generation and delivery.

  This module provides a centralized interface for all chart-related functionality,
  including configuration, image generation, and delivery to various platforms.
  It consolidates functionality previously spread across multiple adapters.

  By default, this service will try to use the Node.js chart service if available,
  falling back to QuickChart.io if not.
  """

  alias WandererNotifier.Api.Http.Client, as: HttpClient
  alias WandererNotifier.ChartService.ChartConfig
  alias WandererNotifier.ChartService.ChartConfigHandler
  alias WandererNotifier.ChartService.ChartTypes
  alias WandererNotifier.ChartService.NodeChartAdapter
  alias WandererNotifier.Config.Notifications
  alias WandererNotifier.Logger.Logger, as: AppLogger
  alias WandererNotifier.Notifiers.Discord.NeoClient, as: DiscordClient

  # Chart service configuration
  @quickchart_url "https://quickchart.io/chart"
  # These defaults have been moved to ChartConfigHandler
  # @default_width 800
  # @default_height 400
  # @default_background_color "rgb(47, 49, 54)" # Discord dark theme
  # White text
  @default_text_color "rgb(255, 255, 255)"
  # Directory to store temporary chart files
  # @tmp_chart_dir "/tmp/wanderer_notifier_charts"

  @doc """
  Generates a chart URL from a configuration.
  This method still uses QuickChart.io for backward compatibility.
  For new code, consider using generate_chart_image/1 instead.

  ## Parameters
    - config: A %ChartConfig{} struct or a map with chart configuration

  ## Returns
    - {:ok, url} on success
    - {:error, reason} on failure
  """
  def generate_chart_url(config) do
    # Use the handler to normalize the configuration
    case ChartConfigHandler.normalize_config(config) do
      {:ok, %ChartConfig{} = chart_config} ->
        # Convert the config to a JSON-compatible map
        chart_map = ChartConfig.to_json_map(chart_config)

        AppLogger.api_debug("Generating chart URL with configuration",
          chart_type: chart_map["type"],
          data: chart_map["data"],
          options: chart_map["options"]
        )

        # Generate the URL
        result =
          do_generate_chart_url(
            chart_map,
            chart_config.width,
            chart_config.height,
            chart_config.background_color
          )

        case result do
          {:ok, url} ->
            AppLogger.api_debug("Generated QuickChart URL", url: url)
            result

          error ->
            AppLogger.api_error("Failed to generate QuickChart URL", error: inspect(error))
            error
        end

      {:error, reason} ->
        AppLogger.api_error("Failed to normalize chart config", error: inspect(reason))
        {:error, reason}
    end
  end

  @doc """
  Generates a chart image from a configuration using the Node.js chart service.

  ## Parameters
    - config: A %ChartConfig{} struct or a map with chart configuration

  ## Returns
    - {:ok, image_binary} on success
    - {:error, reason} on failure
  """
  def generate_chart_image(config) do
    alias WandererNotifier.ChartService.FallbackStrategy

    # Use the handler to normalize the configuration
    case ChartConfigHandler.normalize_config(config) do
      {:ok, %ChartConfig{} = chart_config} ->
        # Define the primary and fallback strategies
        primary_fn = fn -> NodeChartAdapter.generate_chart_image(chart_config) end

        fallback_fn = fn ->
          # First try QuickChart.io URL generation
          with {:ok, url} <- generate_chart_url(chart_config),
               {:ok, image_data} <- FallbackStrategy.download_with_retry(url) do
            {:ok, image_data}
          else
            {:error, reason} ->
              AppLogger.api_error("QuickChart fallback failed", error: inspect(reason))
              # Create a placeholder as last resort
              title = chart_config.title || "Chart"
              FallbackStrategy.generate_placeholder_chart(title, "Chart generation failed")
          end
        end

        # Execute the strategy with fallbacks
        FallbackStrategy.with_fallback(primary_fn, fallback_fn)

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
    - {:ok, url} with the chart URL when using QuickChart
    - {:ok, image_binary} with the chart image when using Node.js service
  """
  def create_no_data_chart(title, message \\ "No data available for this chart") do
    alias WandererNotifier.ChartService.FallbackStrategy

    # Define the primary and fallback strategies
    primary_fn = fn -> NodeChartAdapter.create_no_data_chart(title, message) end
    fallback_fn = fn -> create_no_data_chart_quickchart(title, message) end

    # Execute the strategy with fallbacks
    FallbackStrategy.with_fallback(primary_fn, fallback_fn)
  end

  # Creates a no-data chart using QuickChart.io
  defp create_no_data_chart_quickchart(title, message) do
    # Create a minimalist chart displaying the message
    chart_data = %{
      "labels" => [message],
      "datasets" => [
        %{
          "label" => "",
          "data" => [0],
          "backgroundColor" => "rgba(200, 200, 200, 0.2)",
          "borderColor" => "rgba(200, 200, 200, 0.2)",
          "borderWidth" => 0
        }
      ]
    }

    # Options for a clean, message-focused chart
    options = %{
      "plugins" => %{
        "title" => %{
          "display" => true,
          "text" => title,
          "color" => @default_text_color,
          "font" => %{
            "size" => 18
          }
        },
        "legend" => %{
          "display" => false
        }
      },
      "scales" => %{
        "x" => %{
          "display" => false
        },
        "y" => %{
          "display" => false
        }
      }
    }

    # Create a bar chart (simplest option)
    case ChartConfig.new(ChartTypes.bar(), chart_data, title, options) do
      {:ok, config} -> generate_chart_url(config)
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Sends a chart to Discord using either a URL or binary image data.
  """
  def send_chart_to_discord(chart_data, title, description \\ nil, channel_id \\ nil) do
    # Determine the channel ID to use
    actual_channel_id = get_target_channel_id(channel_id)

    # Early return if no channel ID
    if is_nil(actual_channel_id) do
      {:error, "No Discord channel configured"}
    else
      do_send_chart_to_discord(chart_data, title, description, actual_channel_id)
    end
  end

  # Handle sending chart based on data type
  defp do_send_chart_to_discord(chart_data, title, description, channel_id)
       when is_binary(chart_data) do
    # If the data is a URL, create an embed
    if String.starts_with?(chart_data, "http") do
      send_chart_url_to_discord(chart_data, title, description, channel_id)
    else
      # Otherwise treat it as binary data
      send_chart_binary_to_discord(chart_data, title, description, channel_id)
    end
  end

  defp do_send_chart_to_discord(chart_data, _title, _description, _channel_id) do
    {:error, "Invalid chart data type: #{inspect(chart_data)}"}
  end

  # Send chart URL as an embed
  defp send_chart_url_to_discord(url, title, description, channel_id) do
    embed = %{
      title: title,
      description: description,
      image: %{
        url: url
      }
    }

    case DiscordClient.send_embed(embed, channel_id) do
      :ok -> {:ok, %{title: title}}
      {:error, reason} -> {:error, reason}
    end
  end

  # Send chart binary as a file
  defp send_chart_binary_to_discord(binary_data, title, description, channel_id) do
    filename = "#{title}.png"

    case DiscordClient.send_file(filename, binary_data, channel_id, description) do
      :ok -> {:ok, %{title: title}}
      {:error, reason} -> {:error, reason}
    end
  end

  # Get target Discord channel ID
  defp get_target_channel_id(nil) do
    Notifications.get_discord_channel_id_for(:default)
  end

  defp get_target_channel_id(channel_id) when is_binary(channel_id), do: channel_id

  defp get_target_channel_id(chart_type) when is_atom(chart_type) do
    Notifications.get_discord_channel_id_for(chart_type)
  end

  # Private helpers

  # Core function to generate chart URL from a map
  defp do_generate_chart_url(chart_map, width, height, background_color) do
    AppLogger.api_debug("Starting chart URL generation",
      width: width,
      height: height,
      background_color: background_color,
      chart_type: get_in(chart_map, ["type"]),
      data_preview: get_in(chart_map, ["data"]),
      options_preview: get_in(chart_map, ["options"])
    )

    with {:ok, json_config} <- encode_chart_config(chart_map),
         {:ok, encoded_config} <- encode_config_to_base64(json_config) do
      build_chart_url(encoded_config, width, height, background_color, chart_map)
    end
  rescue
    e ->
      AppLogger.api_error("Exception in chart URL generation",
        exception: inspect(e),
        stacktrace: Exception.format_stacktrace(__STACKTRACE__),
        chart_map: inspect(chart_map, pretty: true, limit: 5000)
      )

      {:error, "Exception encoding chart: #{inspect(e)}"}
  end

  # Encode chart config to JSON
  defp encode_chart_config(chart_map) do
    case Jason.encode(chart_map) do
      {:ok, json_config} = result ->
        AppLogger.api_debug("Successfully encoded chart JSON",
          json_length: String.length(json_config),
          json_preview: String.slice(json_config, 0, 500)
        )

        result

      {:error, reason} ->
        AppLogger.api_error("Failed to encode chart configuration to JSON",
          error: inspect(reason),
          chart_map: inspect(chart_map, pretty: true, limit: 5000)
        )

        {:error, "Failed to encode chart configuration: #{inspect(reason)}"}
    end
  end

  # Encode config to base64
  defp encode_config_to_base64(json_config) do
    case Base.encode64(json_config) do
      encoded_config when is_binary(encoded_config) ->
        AppLogger.api_debug("Successfully encoded config to base64",
          encoded_length: String.length(encoded_config)
        )

        {:ok, encoded_config}

      _ ->
        AppLogger.api_error("Failed to base64 encode chart configuration")
        {:error, "Failed to encode chart configuration"}
    end
  end

  # Helper to build the chart URL with all parameters
  defp build_chart_url(encoded_config, width, height, background_color, chart_map) do
    # Construct URL with query parameters
    url = "#{@quickchart_url}?c=#{encoded_config}"
    url = "#{url}&backgroundColor=#{URI.encode_www_form(background_color)}"
    url = "#{url}&width=#{width}&height=#{height}"

    # Check URL length
    url_length = String.length(url)

    AppLogger.api_debug("Generated chart URL",
      url_length: url_length,
      url: url
    )

    if url_length > 2000 do
      AppLogger.api_warn(
        "Chart URL is very long, using POST method instead",
        url_length: url_length
      )

      create_chart_via_post(chart_map, width, height, background_color)
    else
      {:ok, url}
    end
  end

  # Creates a chart via POST with custom dimensions and background color
  defp create_chart_via_post(chart_config, width, height, background_color) do
    AppLogger.api_debug("Creating chart via POST request", width: width, height: height)

    # Prepare the full configuration with custom dimensions
    full_config = %{
      chart: chart_config,
      options: %{
        width: width,
        height: height,
        devicePixelRatio: 2.0,
        format: "png",
        backgroundColor: background_color
      }
    }

    # Send the POST request to QuickChart API
    post_url = "#{@quickchart_url}/create"

    headers = [
      {"Content-Type", "application/json"},
      {"Accept", "application/json"}
    ]

    # Encode to JSON
    case Jason.encode(full_config) do
      {:ok, json_body} ->
        # Make the HTTP POST request
        make_chart_post_request(post_url, headers, json_body)

      {:error, reason} ->
        AppLogger.api_error("Failed to encode chart configuration for POST",
          error: inspect(reason)
        )

        {:error, "Failed to encode chart configuration for POST"}
    end
  end

  # Helper function to make the POST request to the chart service
  defp make_chart_post_request(url, headers, body) do
    case HttpClient.request("POST", url, headers, body) do
      {:ok, %{status_code: 200, body: response_body}} ->
        # Parse the response to get the chart URL
        parse_chart_response(response_body)

      {:ok, %{status_code: status, body: error_body}} ->
        AppLogger.api_error("QuickChart API error", status_code: status, body: error_body)
        {:error, "QuickChart API error (HTTP #{status})"}

      {:error, reason} ->
        AppLogger.api_error("HTTP request to QuickChart failed", error: inspect(reason))
        {:error, "HTTP request to QuickChart failed"}
    end
  end

  # Helper function to parse the chart service response
  defp parse_chart_response(response_body) do
    case Jason.decode(response_body) do
      {:ok, %{"success" => true, "url" => chart_url}} ->
        AppLogger.api_debug("Successfully created chart via POST request")
        {:ok, chart_url}

      {:ok, %{"success" => false, "message" => message}} ->
        AppLogger.api_error("QuickChart API error", message: message)
        {:error, "QuickChart API error: #{message}"}

      {:error, reason} ->
        AppLogger.api_error("Failed to parse QuickChart response", error: inspect(reason))
        {:error, "Failed to parse QuickChart response"}
    end
  end
end
