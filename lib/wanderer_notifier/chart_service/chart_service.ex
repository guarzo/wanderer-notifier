defmodule WandererNotifier.ChartService do
  @moduledoc """
  Unified service for chart generation and delivery.

  This module provides a centralized interface for all chart-related functionality,
  including configuration, image generation, and delivery to various platforms.
  It consolidates functionality previously spread across multiple adapters.
  
  By default, this service will try to use the Node.js chart service if available,
  falling back to QuickChart.io if not.
  """

  require Logger
  alias WandererNotifier.ChartService.ChartConfig
  alias WandererNotifier.ChartService.ChartConfigHandler
  alias WandererNotifier.ChartService.ChartTypes
  alias WandererNotifier.ChartService.NodeChartAdapter
  alias WandererNotifier.Discord.Client, as: DiscordClient
  alias WandererNotifier.Api.Http.Client, as: HttpClient

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
        
        # Generate the URL
        do_generate_chart_url(chart_map, chart_config.width, chart_config.height, chart_config.background_color)
        
      {:error, reason} ->
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
              Logger.error("QuickChart fallback failed: #{inspect(reason)}")
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
  Sends a chart to Discord as an embed or file attachment.

  ## Parameters
    - chart_config_or_image: The chart configuration or image binary
    - title: The embed title
    - description: The embed description (optional)
    - channel_id: The Discord channel ID (optional, uses configured default if not provided)

  ## Returns
    - {:ok, response} on success
    - {:error, reason} on failure
  """
  @spec send_chart_to_discord(
          binary() | map() | ChartConfig.t(),
          binary(),
          binary() | nil,
          binary() | nil
        ) ::
          {:ok, any()} | {:error, any()}
  def send_chart_to_discord(chart_config_or_image, title, description \\ nil, channel_id \\ nil)

  # Handle image binary data
  def send_chart_to_discord(image_binary, title, description, channel_id)
      when is_binary(image_binary) do
    # Check if the binary is actually a URL
    if is_url(image_binary) do
      # It's a URL, handle it appropriately
      chart_url = image_binary
      Logger.debug("URL detected for chart - downloading and sending as file: #{title}")

      # Download the image and send as file
      case download_chart_image(chart_url) do
        {:ok, image_data} ->
          # Call ourselves recursively with the image data
          send_chart_to_discord(image_data, title, description, channel_id)
          
        {:error, reason} ->
          Logger.error("Failed to download chart image: #{inspect(reason)}")
          
          # Fall back to URL embed as a last resort
          embed = %{
            title: title,
            description: description,
            color: 3_447_003, # Discord blue
            image: %{
              url: chart_url
            },
            footer: %{
              text: "Generated by WandererNotifier"
            },
            timestamp: DateTime.utc_now() |> DateTime.to_iso8601()
          }
          
          DiscordClient.send_embed(embed, channel_id)
      end
    else
      # It's binary image data, send directly
      Logger.debug("Sending chart image binary to Discord: #{title}")

      # Generate a unique filename
      filename = "chart_#{:os.system_time(:millisecond)}.png"

      # Send the file to Discord
      DiscordClient.send_file(filename, image_binary, title, description, channel_id)
    end
  end

  # Handle ChartConfig or map config
  def send_chart_to_discord(config, title, description, channel_id) do
    # Always try to generate an image using Node.js service
    case generate_chart_image(config) do
      {:ok, image_binary} ->
        # Send the image binary
        send_chart_to_discord(image_binary, title, description, channel_id)
      
      {:error, reason} ->
        Logger.warning("Failed to generate chart image with Node.js service: #{reason}. Falling back to QuickChart.")
        
        # Fall back to URL method and then download the image
        case generate_chart_url(config) do
          {:ok, url} -> 
            # Download and send as file
            case download_chart_image(url) do
              {:ok, image_data} -> send_chart_to_discord(image_data, title, description, channel_id)
              {:error, download_reason} -> 
                Logger.error("Failed to download chart image: #{inspect(download_reason)}. Last resort: sending URL embed.")
                # Last resort - send URL as embed
                send_chart_to_discord(url, title, description, channel_id)
            end
            
          {:error, reason} -> {:error, reason}
        end
    end
  end

  # Helper to check if a binary is a URL
  defp is_url(binary) do
    String.starts_with?(binary, "http://") or String.starts_with?(binary, "https://")
  end

  # Private helpers

  # Download a chart image from a URL
  defp download_chart_image(url) do
    WandererNotifier.ChartService.FallbackStrategy.download_with_retry(url)
  end

  # Core function to generate chart URL from a map
  defp do_generate_chart_url(chart_map, width, height, background_color) do
    try do
      # Try to encode the chart configuration to JSON
      case Jason.encode(chart_map) do
        {:ok, json} ->
          # Check JSON size to determine approach
          json_size = byte_size(json)
          Logger.debug("Chart JSON size: #{json_size} bytes")

          if json_size > 8000 or String.length(json) > 2000 do
            Logger.warning("Chart JSON is large (#{json_size} bytes), using POST method instead")
            create_chart_via_post(chart_map, width, height, background_color)
          else
            # Standard encoding for normal-sized JSON
            encoded_config = URI.encode_www_form(json)

            # Construct URL with query parameters
            url = "#{@quickchart_url}?c=#{encoded_config}"
            url = "#{url}&backgroundColor=#{URI.encode_www_form(background_color)}"
            url = "#{url}&width=#{width}&height=#{height}"

            # Check URL length
            url_length = String.length(url)
            Logger.debug("Generated chart URL with length: #{url_length}")

            if url_length > 2000 do
              Logger.warning(
                "Chart URL is very long (#{url_length} chars), using POST method instead"
              )

              create_chart_via_post(chart_map, width, height, background_color)
            else
              {:ok, url}
            end
          end

        {:error, reason} ->
          Logger.error("Failed to encode chart configuration: #{inspect(reason)}")
          {:error, "Failed to encode chart configuration: #{inspect(reason)}"}
      end
    rescue
      e ->
        Logger.error("Exception encoding chart: #{inspect(e)}")
        {:error, "Exception encoding chart: #{inspect(e)}"}
    end
  end

  # Creates a chart via POST request when configuration is too large for URL
  defp create_chart_via_post(chart_map, width, height, background_color) do
    # Create the full chart configuration with dimensions and background
    full_config = %{
      "chart" => chart_map,
      "width" => width,
      "height" => height,
      "backgroundColor" => background_color,
      "format" => "png"
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
        case HttpClient.request("POST", post_url, headers, json_body) do
          {:ok, %{status_code: 200, body: response_body}} ->
            # Parse the response to get the chart URL
            case Jason.decode(response_body) do
              {:ok, %{"success" => true, "url" => chart_url}} ->
                Logger.debug("Successfully created chart via POST request")
                {:ok, chart_url}

              {:ok, %{"success" => false, "message" => message}} ->
                Logger.error("QuickChart API error: #{message}")
                {:error, "QuickChart API error: #{message}"}

              {:error, reason} ->
                Logger.error("Failed to parse QuickChart response: #{inspect(reason)}")
                {:error, "Failed to parse QuickChart response"}
            end

          {:ok, %{status_code: status, body: error_body}} ->
            Logger.error("QuickChart API returned #{status}: #{error_body}")
            {:error, "QuickChart API error (HTTP #{status})"}

          {:error, reason} ->
            Logger.error("HTTP request to QuickChart failed: #{inspect(reason)}")
            {:error, "HTTP request to QuickChart failed"}
        end

      {:error, reason} ->
        Logger.error("Failed to encode chart configuration for POST: #{inspect(reason)}")
        {:error, "Failed to encode chart configuration for POST"}
    end
  end
end