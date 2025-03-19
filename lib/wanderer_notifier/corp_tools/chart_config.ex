defmodule WandererNotifier.CorpTools.ChartConfig do
  @moduledoc """
  Standardized configuration for chart generation.

  This module defines a struct and validation functions for chart configurations.
  It provides a uniform interface for all chart types, ensuring consistency and
  proper validation before chart generation.

  ## Usage Example

  ```elixir
  config = ChartConfig.new(%{
    type: "bar",
    title: "Damage and Final Blows",
    data: [%{"Name" => "Player 1", "DamageDone" => 150}]
  })

  case config do
    {:ok, valid_config} -> ChartService.generate_chart(valid_config)
    {:error, reason} -> handle_error(reason)
  end
  ```
  """

  @typedoc """
  Chart configuration struct.

  Fields:
  - type: The chart type identifier (e.g., "bar", "line", "pie")
  - title: The chart title
  - data: The data to be charted
  - options: Optional chart-specific settings
  - id: Unique identifier for the chart (auto-generated if not provided)
  """
  @type t :: %__MODULE__{
          type: String.t(),
          title: String.t(),
          data: list(map()) | map(),
          options: map(),
          id: String.t()
        }

  defstruct [
    :type,
    :title,
    :data,
    options: %{},
    id: nil
  ]

  @doc """
  Creates a new ChartConfig struct with validation.

  ## Parameters

  - params: Map of chart configuration parameters

  ## Returns

  - `{:ok, config}` if validation passes
  - `{:error, reason}` if validation fails
  """
  @spec new(map()) :: {:ok, t()} | {:error, String.t()}
  def new(params) when is_map(params) do
    config = %__MODULE__{
      type: Map.get(params, :type) || Map.get(params, "type"),
      title: Map.get(params, :title) || Map.get(params, "title"),
      data: Map.get(params, :data) || Map.get(params, "data"),
      options: Map.get(params, :options) || Map.get(params, "options") || %{},
      id: Map.get(params, :id) || Map.get(params, "id") || generate_id()
    }

    validate(config)
  end

  @doc """
  Validates a ChartConfig struct.

  ## Parameters

  - config: The ChartConfig struct to validate

  ## Returns

  - `{:ok, config}` if validation passes
  - `{:error, reason}` if validation fails
  """
  @spec validate(t()) :: {:ok, t()} | {:error, String.t()}
  def validate(%__MODULE__{} = config) do
    cond do
      !is_binary(config.type) || String.trim(config.type) == "" ->
        {:error, "Chart type must be a non-empty string"}

      !is_binary(config.title) || String.trim(config.title) == "" ->
        {:error, "Chart title must be a non-empty string"}

      !valid_data?(config.data) ->
        {:error, "Chart data must be a valid list or map"}

      !is_map(config.options) ->
        {:error, "Chart options must be a map"}

      true ->
        {:ok, config}
    end
  end

  @doc """
  Checks if the provided data is valid for chart generation.

  ## Parameters

  - data: The data to validate

  ## Returns

  - `true` if data is valid
  - `false` if data is invalid
  """
  @spec valid_data?(any()) :: boolean()
  def valid_data?(data) when is_list(data), do: length(data) > 0
  def valid_data?(data) when is_map(data), do: map_size(data) > 0
  def valid_data?(_), do: false

  @doc """
  Generates a unique ID for a chart.

  ## Returns

  - A unique ID string
  """
  @spec generate_id() :: String.t()
  def generate_id do
    timestamp = System.system_time(:second)
    random = :rand.uniform(1000)
    "chart_#{timestamp}_#{random}"
  end

  @doc """
  Converts a ChartConfig to a map suitable for JSON encoding.

  ## Parameters

  - config: The ChartConfig struct to convert

  ## Returns

  - A map suitable for JSON encoding
  """
  @spec to_json(t()) :: map()
  def to_json(%__MODULE__{} = config) do
    %{
      "chart_type" => config.type,
      "title" => config.title,
      "data" => config.data,
      "options" => config.options,
      "id" => config.id
    }
  end
end
