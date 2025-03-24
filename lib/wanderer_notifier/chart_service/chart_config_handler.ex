defmodule WandererNotifier.ChartService.ChartConfigHandler do
  @moduledoc """
  Handles chart configuration conversion and normalization.

  This module provides utility functions for converting various chart configuration
  formats into standardized ChartConfig structs. It centralizes the logic for
  working with chart configurations across the application.
  """

  alias WandererNotifier.ChartService.ChartConfig
  require Logger
  alias WandererNotifier.Logger, as: AppLogger

  # Default chart settings
  @default_width 800
  @default_height 400
  # Discord dark theme
  @default_background_color "rgb(47, 49, 54)"

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
    # Extract all field values with proper defaults
    config_fields = extract_config_fields(config)

    # Create a new ChartConfig struct with the extracted fields
    ChartConfig.new(
      config_fields.type,
      config_fields.data,
      config_fields.title,
      config_fields.options,
      config_fields.width,
      config_fields.height,
      config_fields.background_color
    )
  end

  def normalize_config(invalid_config) do
    AppLogger.processor_error("Invalid chart configuration provided", config: inspect(invalid_config))
    {:error, "Invalid chart configuration format"}
  end

  # Extract configuration fields from a map with proper fallbacks
  defp extract_config_fields(config) do
    %{
      type: extract_field(config, :type, "type"),
      data: extract_field(config, :data, "data"),
      title: extract_field(config, :title, "title"),
      options: extract_field(config, :options, "options", %{}),
      width: extract_field(config, :width, "width", @default_width),
      height: extract_field(config, :height, "height", @default_height),
      background_color:
        extract_field(config, :background_color, "background_color", @default_background_color)
    }
  end

  # Extract a field value from a config map with fallbacks
  defp extract_field(config, atom_key, string_key, default \\ nil) do
    config[atom_key] || config[string_key] || default
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
        {:ok,
         %{
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
    base_name =
      if is_nil(filename) || filename == "",
        do: "chart_#{:os.system_time(:millisecond)}",
        else: filename

    # Add .png extension if not present
    if String.ends_with?(base_name, ".png"),
      do: base_name,
      else: "#{base_name}.png"
  end
end
