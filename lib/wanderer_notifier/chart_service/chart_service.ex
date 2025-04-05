defmodule WandererNotifier.ChartService do
  @moduledoc """
  Unified service for chart generation and delivery.

  This module provides a centralized interface for all chart-related functionality,
  including configuration, image generation, and delivery to various platforms.
  It consolidates functionality previously spread across multiple adapters.
  """

  alias WandererNotifier.ChartService.ChartConfig
  alias WandererNotifier.ChartService.ChartConfigHandler
  alias WandererNotifier.ChartService.NodeChartAdapter
  alias WandererNotifier.Config.Notifications
  alias WandererNotifier.Notifiers.Discord.NeoClient, as: DiscordClient

  @doc """
  Generates a chart image from a configuration using the Node.js chart service.

  ## Parameters
    - config: A %ChartConfig{} struct or a map with chart configuration

  ## Returns
    - {:ok, image_binary} on success
    - {:error, reason} on failure
  """
  def generate_chart_image(config) do
    # Use the handler to normalize the configuration
    case ChartConfigHandler.normalize_config(config) do
      {:ok, %ChartConfig{} = chart_config} ->
        NodeChartAdapter.generate_chart_image(chart_config)

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
    - {:ok, image_binary} with the chart image
  """
  def create_no_data_chart(title, message \\ "No data available for this chart") do
    NodeChartAdapter.create_no_data_chart(title, message)
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
end
