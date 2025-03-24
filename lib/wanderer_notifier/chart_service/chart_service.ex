defmodule WandererNotifier.ChartService do
  @moduledoc """
  Unified service for chart generation and delivery.

  This module provides a centralized interface for all chart-related functionality,
  including configuration, image generation, and delivery to various platforms.
  It consolidates functionality previously spread across multiple adapters.

  By default, this service will try to use the Node.js chart service if available,
  falling back to QuickChart.io if not.
  """

  alias WandererNotifier.Logger, as: AppLogger
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
        do_generate_chart_url(
          chart_map,
          chart_config.width,
          chart_config.height,
          chart_config.background_color
        )

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
    if url?(image_binary) do
      # It's a URL, use it directly in an embed
      chart_url = image_binary
      AppLogger.api_debug("URL detected for chart - using in embed", chart_title: title)

      # Create rich embed with the chart URL as the image
      embed = %{
        title: title,
        description: description,
        # Discord blue
        color: 3_447_003,
        image: %{
          url: chart_url
        },
        footer: %{
          text: "Generated by WandererNotifier"
        },
        timestamp: DateTime.utc_now() |> DateTime.to_iso8601()
      }

      DiscordClient.send_embed(embed, channel_id)
    else
      # It's binary image data, we need to upload it somewhere first
      AppLogger.api_debug("Binary image data detected - converting to URL for embed", chart_title: title)

      # Try to generate a URL using chart config approach first
      case generate_chart_url(extract_config_from_binary(image_binary)) do
        {:ok, url} ->
          # Use the URL in an embed
          embed = %{
            title: title,
            description: description,
            # Discord blue
            color: 3_447_003,
            image: %{
              url: url
            },
            footer: %{
              text: "Generated by WandererNotifier"
            },
            timestamp: DateTime.utc_now() |> DateTime.to_iso8601()
          }

          DiscordClient.send_embed(embed, channel_id)

        {:error, _url_error} ->
          # Last resort - send as file if we can't get a URL
          AppLogger.api_warn("Could not generate URL for image. Falling back to file upload.")

          # Generate a unique filename
          filename = "chart_#{:os.system_time(:millisecond)}.png"
          # Send the file to Discord
          DiscordClient.send_file(filename, image_binary, title, description, channel_id)
      end
    end
  end

  # Handle ChartConfig or map config
  def send_chart_to_discord(config, title, description, channel_id) do
    # Generate a chart URL directly instead of trying to generate an image
    case generate_chart_url(config) do
      {:ok, url} ->
        # Create rich embed with the chart URL as the image
        embed = %{
          title: title,
          description: description,
          # Discord blue
          color: 3_447_003,
          image: %{
            url: url
          },
          footer: %{
            text: "Generated by WandererNotifier"
          },
          timestamp: DateTime.utc_now() |> DateTime.to_iso8601()
        }

        DiscordClient.send_embed(embed, channel_id)

      {:error, reason} ->
        AppLogger.api_error("Failed to generate chart URL", error: inspect(reason))
        {:error, reason}
    end
  end

  # Helper to check if a binary is a URL
  defp url?(binary) do
    String.starts_with?(binary, "http://") or String.starts_with?(binary, "https://")
  end

  # Private helpers

  # Core function to generate chart URL from a map
  defp do_generate_chart_url(chart_map, width, height, background_color) do
    try do
      # Try to encode the chart configuration to JSON
      case Jason.encode(chart_map) do
        {:ok, json} ->
          # Check JSON size to determine approach
          json_size = byte_size(json)
          AppLogger.api_debug("Chart config prepared", json_size_bytes: json_size)

          if json_size > 8000 or String.length(json) > 2000 do
            AppLogger.api_warn("Chart JSON is large, using POST method instead", json_size_bytes: json_size)
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
            AppLogger.api_debug("Generated chart URL", url_length: url_length)

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

        {:error, reason} ->
          AppLogger.api_error("Failed to encode chart configuration", error: inspect(reason))
          {:error, "Failed to encode chart configuration: #{inspect(reason)}"}
      end
    rescue
      e ->
        AppLogger.api_error("Exception encoding chart", exception: inspect(e))
        {:error, "Exception encoding chart: #{inspect(e)}"}
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
        AppLogger.api_error("Failed to encode chart configuration for POST", error: inspect(reason))
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

  # Extract chart config from binary image data (if possible)
  defp extract_config_from_binary(_image_data) do
    # This is a placeholder function
    # In reality, we can't easily extract the config from a rendered image
    # This would normally use the last known config from the chart generation process

    # For now, just create a simple chart config that ensures we get a URL
    %{
      "type" => "bar",
      "data" => %{
        "labels" => ["Fallback"],
        "datasets" => [
          %{
            "label" => "Data",
            "data" => [1],
            "backgroundColor" => "rgba(54, 162, 235, 0.8)"
          }
        ]
      },
      "options" => %{
        "title" => %{
          "display" => true,
          "text" => "Chart Data"
        }
      }
    }
  end
end
