defmodule WandererNotifier.CorpTools.ChartHelpers do
  @moduledoc """
  Shared helper functions for chart generation across different adapters.
  """
  require Logger

  @quickcharts_url "https://quickchart.io/chart"
  @chart_width 800
  @chart_height 400
  @chart_background_color "rgb(47, 49, 54)"  # Discord dark theme background
  @chart_text_color "rgb(255, 255, 255)"     # White text for Discord dark theme

  @doc """
  Generates a chart URL from a chart configuration.

  Args:
    - chart_config: The chart configuration map to encode

  Returns {:ok, url} on success, {:error, reason} on failure.
  """
  def generate_chart_url(chart_config) do
    # Log the chart config structure for debugging
    Logger.debug("Generating chart URL with config: #{inspect(chart_config, limit: 5000)}")
    
    # Convert chart configuration to JSON
    case Jason.encode(chart_config) do
      {:ok, json} ->
        # URL encode the JSON - the percent encoding is causing issues
        # Instead of regular form encoding, we need a more compatible encoding
        encoded_config = 
          json
          |> URI.encode()
          |> String.replace("%20", "+") # Spaces are better as + for QuickChart

        # Construct the URL
        url = "#{@quickcharts_url}?c=#{encoded_config}&w=#{@chart_width}&h=#{@chart_height}"

        # Log the URL (truncated for brevity in logs)
        url_length = String.length(url)
        truncated_url = if url_length > 100, 
          do: "#{String.slice(url, 0, 50)}...#{String.slice(url, -50, 50)} (length: #{url_length})",
          else: url
          
        Logger.info("Generated chart URL: #{truncated_url}")
        
        # Validate the URL is properly formed
        case URI.parse(url) do
          %URI{scheme: nil} ->
            Logger.error("Generated invalid chart URL without scheme")
            {:error, "Invalid chart URL generated"}
          %URI{host: nil} ->
            Logger.error("Generated invalid chart URL without host")
            {:error, "Invalid chart URL generated"}
          _ ->
            {:ok, url}
        end

      {:error, reason} ->
        Logger.error("Failed to encode chart configuration: #{inspect(reason)}")
        {:error, "Failed to encode chart configuration: #{inspect(reason)}"}
    end
  end

  @doc """
  Generates a standard chart configuration with common settings.

  Args:
    - title: The chart title
    - chart_type: The type of chart (e.g., "bar", "line", "doughnut")
    - chart_data: The data for the chart
    - options: Additional options to merge with defaults (optional)

  Returns a chart configuration map.
  """
  def generate_chart_config(title, chart_type, chart_data, options \\ %{}) do
    default_options = %{
      responsive: true,
      plugins: %{
        title: %{
          display: true,
          text: title,
          color: @chart_text_color,
          font: %{
            size: 18
          }
        },
        legend: %{
          labels: %{
            color: @chart_text_color
          }
        }
      },
      scales: %{
        x: %{
          ticks: %{
            color: @chart_text_color
          },
          grid: %{
            color: "rgba(255, 255, 255, 0.1)"
          }
        },
        y: %{
          ticks: %{
            color: @chart_text_color
          },
          grid: %{
            color: "rgba(255, 255, 255, 0.1)"
          },
          beginAtZero: true
        }
      }
    }

    # Merge the default options with any provided options
    merged_options = deep_merge(default_options, options)

    %{
      type: chart_type,
      data: chart_data,
      options: merged_options,
      backgroundColor: @chart_background_color
    }
  end

  @doc """
  Creates a "No Data Available" chart.

  Args:
    - title: The chart title

  Returns {:ok, url} with the chart URL.
  """
  def create_no_data_chart(title) do
    # Use a simplified title that's less likely to cause encoding issues
    simple_title = "No Data"
    Logger.info("Creating 'No Data Available' chart for: #{title}")
    
    # Create a very minimal chart configuration
    chart_config = %{
      type: "bar",
      data: %{
        labels: ["No Data"],
        datasets: [
          %{
            label: "Value",
            data: [0],
            backgroundColor: "rgba(54, 162, 235, 0.8)"
          }
        ]
      },
      options: %{
        plugins: %{
          title: %{
            display: true,
            text: simple_title,
            color: "rgb(255, 255, 255)"
          },
          legend: %{
            display: false
          }
        }
      },
      backgroundColor: "rgb(47, 49, 54)"
    }
    
    # Direct URL encoding approach as a fallback
    case Jason.encode(chart_config) do
      {:ok, json} ->
        encoded_json = URI.encode(json)
        url = "#{@quickcharts_url}?c=#{encoded_json}&w=#{@chart_width}&h=#{@chart_height}"
        Logger.info("Created simple 'No Data' chart with direct encoding")
        {:ok, url}
      
      {:error, reason} ->
        Logger.error("Failed to encode 'No Data' chart: #{inspect(reason)}")
        # Super simple fallback using a predefined chart
        fallback_url = "#{@quickcharts_url}?c=%7B%22type%22%3A%22bar%22%2C%22data%22%3A%7B%22labels%22%3A%5B%22No%20Data%22%5D%2C%22datasets%22%3A%5B%7B%22label%22%3A%22Value%22%2C%22data%22%3A%5B0%5D%2C%22backgroundColor%22%3A%22blue%22%7D%5D%7D%7D"
        {:ok, fallback_url}
    end
  end

  @doc """
  Helper function to format month labels from various formats.

  Args:
    - date_str: A date string in ISO format or "YYYY-MM" format

  Returns a formatted month label (e.g., "Jan 2023").
  """
  def format_month_label(date_str) do
    cond do
      String.contains?(date_str, "T") ->
        # Handle ISO date format
        case DateTime.from_iso8601(date_str) do
          {:ok, datetime, _} ->
            month_name = get_month_name(datetime.month)
            "#{month_name} #{datetime.year}"
          _ ->
            date_str
        end

      # Handle YYYY-MM format
      String.match?(date_str, ~r/^\d{4}-\d{2}$/) ->
        case String.split(date_str, "-") do
          [year, month] ->
            month_name = get_month_name(String.to_integer(month))
            "#{month_name} #{year}"
          _ ->
            date_str
        end

      true ->
        date_str
    end
  end

  @doc """
  Dispatches chart generation based on chart type.

  Args:
    - chart_type: The type of chart to generate (atom)
    - generators: A map of chart types to generator functions

  Returns the result of the generator function for the specified chart type.
  """
  def dispatch_chart_generation(chart_type, generators) do
    case Map.get(generators, chart_type) do
      nil ->
        {:error, "Invalid chart type: #{inspect(chart_type)}"}

      generator_fn when is_function(generator_fn, 0) ->
        generator_fn.()

      _ ->
        {:error, "Invalid generator function for chart type: #{inspect(chart_type)}"}
    end
  end

  @doc """
  Debug function to log the TPS data structure.

  Args:
    - data: The TPS data structure to debug
  """
  def debug_tps_data_structure(data) do
    Logger.info("TPS data keys: #{inspect(Map.keys(data))}")

    # Check for the documented structure
    if Map.has_key?(data, "Last12MonthsData") do
      last_12_months_data = Map.get(data, "Last12MonthsData", %{})
      Logger.info("Last12MonthsData keys: #{inspect(Map.keys(last_12_months_data))}")

      # Check for KillsByShipType
      if Map.has_key?(last_12_months_data, "KillsByShipType") do
        kills_by_ship_type = Map.get(last_12_months_data, "KillsByShipType", %{})
        Logger.info("KillsByShipType is a map with #{map_size(kills_by_ship_type)} entries")
        Logger.info("Sample entries: #{inspect(Enum.take(kills_by_ship_type, 3))}")
      else
        Logger.info("KillsByShipType not found in Last12MonthsData")
      end

      # Check for KillsByMonth
      if Map.has_key?(last_12_months_data, "KillsByMonth") do
        kills_by_month = Map.get(last_12_months_data, "KillsByMonth", %{})
        Logger.info("KillsByMonth is a map with #{map_size(kills_by_month)} entries")
        Logger.info("Sample entries: #{inspect(Enum.take(kills_by_month, 3))}")
      else
        Logger.info("KillsByMonth not found in Last12MonthsData")
      end
    else
      Logger.info("Last12MonthsData not found in TPS data")
    end

    # Check for Charts array
    if Map.has_key?(data, "Charts") do
      charts = Map.get(data, "Charts", [])
      Logger.info("Charts is an array with #{length(charts)} entries")

      # Log chart IDs and names
      Enum.each(Enum.take(charts, 3), fn chart ->
        Logger.info("Chart ID: #{Map.get(chart, "ID", "unknown")}, Name: #{Map.get(chart, "Name", "unknown")}")
      end)
    else
      Logger.info("Charts array not found in TPS data")
    end
  end

  # Helper function to get month name from month number
  defp get_month_name(month) when is_integer(month) do
    case month do
      1 -> "Jan"
      2 -> "Feb"
      3 -> "Mar"
      4 -> "Apr"
      5 -> "May"
      6 -> "Jun"
      7 -> "Jul"
      8 -> "Aug"
      9 -> "Sep"
      10 -> "Oct"
      11 -> "Nov"
      12 -> "Dec"
      _ -> "Unknown"
    end
  end

  defp get_month_name(month) when is_binary(month) do
    case month do
      "01" -> "Jan"
      "02" -> "Feb"
      "03" -> "Mar"
      "04" -> "Apr"
      "05" -> "May"
      "06" -> "Jun"
      "07" -> "Jul"
      "08" -> "Aug"
      "09" -> "Sep"
      "10" -> "Oct"
      "11" -> "Nov"
      "12" -> "Dec"
      _ -> month
    end
  end

  # Helper function to deep merge maps
  defp deep_merge(left, right) do
    Map.merge(left, right, fn
      _, %{} = left_val, %{} = right_val -> deep_merge(left_val, right_val)
      _, _left_val, right_val -> right_val
    end)
  end
end
