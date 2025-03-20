defmodule WandererNotifier.ChartService.ChartConfigHandler do
  @moduledoc """
  Handles chart configuration conversion and normalization.

  This module provides utility functions for converting various chart configuration
  formats into standardized ChartConfig structs. It centralizes the logic for 
  working with chart configurations across the application.
  """

  alias WandererNotifier.ChartService.ChartConfig
  require Logger

  # Default chart settings
  @default_width 800
  @default_height 400
  @default_background_color "rgb(47, 49, 54)"  # Discord dark theme

  @doc """
  Normalizes a chart configuration to ensure it's a proper ChartConfig struct.
  
  This function handles both maps and existing ChartConfig structs, ensuring
  a consistent interface for all chart generation functions.

  ## Parameters
    - config: A map or ChartConfig struct with chart configuration

  ## Returns
    - {:ok, config} with a normalized ChartConfig struct
    - {:error, reason} if the configuration is invalid
  """
  def normalize_config(%ChartConfig{} = config) do
    # Already a ChartConfig struct, return as-is
    {:ok, config}
  end

  def normalize_config(config) when is_map(config) do
    # Extract values with proper defaults
    chart_type = config[:type] || config["type"]
    chart_data = config[:data] || config["data"]
    chart_title = config[:title] || config["title"]
    chart_options = config[:options] || config["options"] || %{}
    chart_width = config[:width] || config["width"] || @default_width
    chart_height = config[:height] || config["height"] || @default_height
    chart_bg_color = config[:background_color] || config["background_color"] || @default_background_color
    
    # Create a new ChartConfig struct
    ChartConfig.new(
      chart_type,
      chart_data,
      chart_title,
      chart_options,
      chart_width,
      chart_height,
      chart_bg_color
    )
  end

  def normalize_config(invalid_config) do
    Logger.error("Invalid chart configuration provided: #{inspect(invalid_config)}")
    {:error, "Invalid chart configuration format"}
  end

  @doc """
  Prepares a chart configuration for sending to the Node.js chart service.
  
  This function handles the conversion of a ChartConfig struct or map into
  the format expected by the Node.js service.

  ## Parameters
    - config: A map or ChartConfig struct with chart configuration

  ## Returns
    - {:ok, %{chart: json_map, width: width, height: height, background_color: bg_color}}
    - {:error, reason} if the configuration is invalid
  """
  def prepare_for_node_service(config) do
    case normalize_config(config) do
      {:ok, %ChartConfig{} = chart_config} ->
        # Convert to JSON-compatible map
        chart_map = ChartConfig.to_json_map(chart_config)
        
        # Return formatted for node service
        {:ok, %{
          chart: chart_map,
          width: chart_config.width,
          height: chart_config.height,
          background_color: chart_config.background_color
        }}
        
      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Generates a filename for chart images with PNG extension.
  
  This function creates a unique filename for chart images, ensuring
  it has the proper .png extension.

  ## Parameters
    - filename: Optional filename base (without extension)
    
  ## Returns
    - String with the filename (including .png extension)
  """
  def generate_filename(filename \\ nil) do
    # Generate a unique filename if none provided
    base_name = if is_nil(filename) || filename == "",
      do: "chart_#{:os.system_time(:millisecond)}",
      else: filename
      
    # Add .png extension if not present
    if String.ends_with?(base_name, ".png"),
      do: base_name,
      else: "#{base_name}.png"
  end
end