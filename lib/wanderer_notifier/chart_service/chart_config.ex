defmodule WandererNotifier.ChartService.ChartConfig do
  @moduledoc """
  Defines a standardized chart configuration struct with validation.

  ChartConfig provides a consistent interface for generating chart configurations
  across all charts in the application. It enforces required fields and validates
  chart data to prevent common errors.
  """

  alias WandererNotifier.ChartService.ChartTypes
  require Logger

  @enforce_keys [:type, :data]
  defstruct [
    # The chart type (bar, line, etc.)
    :type,
    # The chart data (labels and datasets)
    :data,
    # The chart title
    :title,
    # Additional chart options
    :options,
    # Chart width
    :width,
    # Chart height
    :height,
    # Chart background color
    :background_color
  ]

  @doc """
  Creates a new chart configuration with validation.

  ## Parameters
    - type: The chart type (bar, line, etc.)
    - data: The chart data with labels and datasets
    - title: The chart title (optional)
    - options: Additional chart options (optional)
    - width: Chart width (optional, defaults to 800)
    - height: Chart height (optional, defaults to 400)
    - background_color: Chart background color (optional, defaults to Discord dark theme)

  ## Returns
    - {:ok, config} if valid
    - {:error, reason} if invalid
  """
  def new(
        type,
        data,
        title \\ nil,
        options \\ %{},
        width \\ 800,
        height \\ 400,
        background_color \\ "rgb(47, 49, 54)"
      ) do
    # Create the struct
    config = %__MODULE__{
      type: type,
      data: data,
      title: title,
      options: options,
      width: width,
      height: height,
      background_color: background_color
    }

    # Validate the config
    case validate(config) do
      :ok -> {:ok, config}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Validates a chart configuration for correctness.

  ## Returns
    - :ok if valid
    - {:error, reason} if invalid
  """
  def validate(%__MODULE__{} = config) do
    cond do
      not valid_type?(config.type) ->
        {:error, "Invalid chart type: #{inspect(config.type)}"}

      not valid_data?(config.data) ->
        {:error, "Invalid chart data structure"}

      true ->
        :ok
    end
  end

  @doc """
  Converts the ChartConfig struct to a map suitable for encoding to JSON.
  Adds default styling if needed.

  ## Returns
    - Map that can be encoded to JSON
  """
  def to_json_map(%__MODULE__{} = config) do
    require Logger

    # Base configuration
    json_map = %{
      "type" => config.type,
      "data" => config.data
    }

    Logger.debug("Creating chart JSON map",
      type: config.type,
      data: inspect(config.data, pretty: true, limit: 2000)
    )

    # Add options with defaults if not provided
    json_map =
      case config.options do
        opts when is_map(opts) and map_size(opts) > 0 ->
          Logger.debug("Using provided options with defaults",
            options: inspect(opts, pretty: true, limit: 2000)
          )

          Map.put(json_map, "options", merge_with_default_options(opts, config.title))

        _ ->
          Logger.debug("Using default options")
          Map.put(json_map, "options", default_options(config.title))
      end

    Logger.debug("Final chart configuration",
      config: inspect(json_map, pretty: true, limit: 5000)
    )

    json_map
  end

  # Private helpers

  defp valid_type?(type) do
    require Logger

    valid_types = [
      ChartTypes.bar(),
      ChartTypes.line(),
      ChartTypes.horizontal_bar(),
      ChartTypes.doughnut(),
      ChartTypes.pie(),
      # Also allow string versions
      "bar",
      "line",
      "horizontalBar",
      "doughnut",
      "pie"
    ]

    is_valid = type in valid_types
    Logger.debug("Validating chart type", type: type, valid: is_valid)
    is_valid
  end

  defp valid_data?(data) when is_map(data) do
    # Check for required data structures
    has_labels = data[:labels] != nil || data["labels"] != nil
    has_datasets = data[:datasets] != nil || data["datasets"] != nil
    datasets = data[:datasets] || data["datasets"] || []

    has_labels and has_datasets and is_list(datasets) and length(datasets) > 0
  end

  defp valid_data?(_), do: false

  defp default_options(title) do
    # Default styling for charts with white text on dark background
    options = %{
      "responsive" => true,
      "plugins" => %{
        "legend" => %{
          "labels" => %{
            "color" => "white"
          }
        }
      },
      "scales" => %{
        "x" => %{
          "ticks" => %{
            "color" => "white"
          },
          "grid" => %{
            "color" => "rgba(255, 255, 255, 0.1)"
          }
        },
        "y" => %{
          "ticks" => %{
            "color" => "white"
          },
          "grid" => %{
            "color" => "rgba(255, 255, 255, 0.1)"
          },
          "beginAtZero" => true
        }
      }
    }

    # Add title if provided
    if title do
      put_in(options, ["plugins", "title"], %{
        "display" => true,
        "text" => title,
        "color" => "white",
        "font" => %{
          "size" => 18
        }
      })
    else
      options
    end
  end

  defp merge_with_default_options(options, title) do
    # Start with default options
    defaults = default_options(title)

    # Deep merge user options with defaults
    deep_merge(defaults, options)
  end

  # Recursively merges two maps
  defp deep_merge(left, right) do
    Map.merge(left, right, fn
      # If both values are maps, recursively merge them
      _key, left_val, right_val when is_map(left_val) and is_map(right_val) ->
        deep_merge(left_val, right_val)

      # Otherwise, take the value from the right map
      _key, _left_val, right_val ->
        right_val
    end)
  end
end
