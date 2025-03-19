defmodule WandererNotifier.ChartService.TPSChartAdapter do
  @moduledoc """
  Adapts TPS data from the EVE Corp Tools API for use with the ChartService.

  This adapter is focused solely on data preparation, extracting and transforming
  TPS data into chart-ready formats. It delegates rendering and delivery to the
  ChartService module.
  """
  require Logger

  alias WandererNotifier.CorpTools.CorpToolsClient
  alias WandererNotifier.ChartService
  alias WandererNotifier.ChartService.ChartConfig
  alias WandererNotifier.ChartService.ChartTypes

  # Define constants for chart types to avoid function calls in guards
  @chart_type_kills_by_ship_type :kills_by_ship_type
  @chart_type_kills_by_month :kills_by_month
  @chart_type_total_kills_value :total_kills_value

  @doc """
  Generates a chart URL for kills by ship type from TPS data.
  Returns {:ok, url} on success, {:error, reason} on failure.
  """
  def generate_kills_by_ship_type_chart do
    case prepare_kills_by_ship_type_data() do
      {:ok, chart_data, title} ->
        # Create chart configuration using the ChartConfig struct
        case ChartConfig.new(
               ChartTypes.bar(),
               chart_data,
               title
             ) do
          {:ok, config} -> ChartService.generate_chart_url(config)
          {:error, reason} -> {:error, reason}
        end

      {:error, reason} ->
        # Handle specific empty response error
        error_message =
          if is_binary(reason) && String.contains?(reason, "empty response") do
            "API returned an empty response. Please check the TPS data API endpoint."
          else
            "Error fetching data: #{inspect(reason)}"
          end

        Logger.error("Failed to get TPS data: #{inspect(reason)}")
        ChartService.create_no_data_chart("Kills by Ship Type", error_message)
    end
  end

  @doc """
  Prepares chart data for kills by ship type.
  Returns {:ok, chart_data, title} or {:error, reason}.
  """
  def prepare_kills_by_ship_type_data do
    case CorpToolsClient.get_recent_tps_data() do
      {:ok, data} ->
        # Log the data structure for debugging
        Logger.debug("TPS data structure: #{inspect(data, pretty: true, limit: 10000)}")
        Logger.debug("TPS data keys: #{inspect(Map.keys(data))}")

        # Check if we have TimeFrames data
        time_frames = Map.get(data, "TimeFrames")

        if time_frames && length(time_frames) > 0 do
          Logger.debug("Found TimeFrames data with #{length(time_frames)} frames")

          # Process the first time frame's charts
          case extract_ship_type_data_from_time_frames(time_frames) do
            {:ok, ship_data} ->
              # Sort by kill count (descending) and take top 10
              sorted_data =
                ship_data
                |> Enum.sort_by(fn {_ship, count} -> count end, :desc)
                |> Enum.take(10)

              # Extract labels (ship types) and data (kill counts)
              {labels, values} = Enum.unzip(sorted_data)

              Logger.debug("Ship type labels: #{inspect(labels)}")
              Logger.debug("Kill values: #{inspect(values)}")

              # Create chart data
              chart_data = %{
                "labels" => labels,
                "datasets" => [
                  %{
                    "label" => "Kills by Ship Type (Last 12 Months)",
                    "data" => values,
                    "backgroundColor" => "rgba(54, 162, 235, 0.8)",
                    "borderColor" => "rgba(54, 162, 235, 1)",
                    "borderWidth" => 1
                  }
                ]
              }

              {:ok, chart_data, "Top Ship Types by Kills"}

            {:error, reason} ->
              {:error, reason}
          end
        else
          # Check for old API structure with KillsByShipType directly at root
          kills_by_ship_type = Map.get(data, "KillsByShipType")

          if is_map(kills_by_ship_type) and map_size(kills_by_ship_type) > 0 do
            # Sort by kill count (descending) and take top 10
            sorted_data =
              kills_by_ship_type
              |> Enum.sort_by(fn {_ship, count} -> count end, :desc)
              |> Enum.take(10)

            # Extract labels (ship types) and data (kill counts)
            {labels, values} = Enum.unzip(sorted_data)

            Logger.debug("Ship type labels: #{inspect(labels)}")
            Logger.debug("Kill values: #{inspect(values)}")

            # Create chart data
            chart_data = %{
              "labels" => labels,
              "datasets" => [
                %{
                  "label" => "Kills by Ship Type (Last 12 Months)",
                  "data" => values,
                  "backgroundColor" => "rgba(54, 162, 235, 0.8)",
                  "borderColor" => "rgba(54, 162, 235, 1)",
                  "borderWidth" => 1
                }
              ]
            }

            {:ok, chart_data, "Top Ship Types by Kills"}
          else
            {:error, "No ship type data found in TPS response"}
          end
        end

      {:loading, message} ->
        {:error, "Data is still loading: #{message}"}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # Helper function to extract ship type data from TimeFrames structure
  defp extract_ship_type_data_from_time_frames(time_frames) do
    try do
      # Find the chart with ship type data in the first time frame
      ship_type_chart =
        time_frames
        |> Enum.at(0, %{})
        |> Map.get("Charts", [])
        |> Enum.find(fn chart ->
          title = Map.get(chart, "Title", "")
          String.contains?(title, "Ship Type") or String.contains?(title, "ShipType")
        end)

      if ship_type_chart do
        # Extract and parse the JSON data string
        case Jason.decode(ship_type_chart["Data"]) do
          {:ok, parsed_data} ->
            # Transform the data into the expected format
            ship_data =
              parsed_data
              |> Enum.map(fn item ->
                {Map.get(item, "ShipType", Map.get(item, "Name", "Unknown")),
                 Map.get(item, "Count", Map.get(item, "Kills", 0))}
              end)

            {:ok, ship_data}

          {:error, decode_error} ->
            Logger.error("Failed to decode ship type data: #{inspect(decode_error)}")
            {:error, "Failed to parse ship type data: #{inspect(decode_error)}"}
        end
      else
        # Try to find any chart with data we can use
        fallback_chart =
          time_frames
          |> Enum.at(0, %{})
          |> Map.get("Charts", [])
          |> Enum.find(fn chart -> Map.has_key?(chart, "Data") end)

        if fallback_chart do
          case Jason.decode(fallback_chart["Data"]) do
            {:ok, parsed_data} ->
              # Try to determine if this is ship data based on structure
              if Enum.all?(parsed_data, &(is_map(&1) && Map.has_key?(&1, "Name"))) do
                ship_data =
                  parsed_data
                  |> Enum.map(fn item ->
                    {Map.get(item, "Name", "Unknown"),
                     Map.get(
                       item,
                       "Kills",
                       Map.get(item, "Count", Map.get(item, "FinalBlows", 0))
                     )}
                  end)

                {:ok, ship_data}
              else
                {:error, "No suitable ship type data found in charts"}
              end

            {:error, decode_error} ->
              {:error, "Failed to parse fallback chart data: #{inspect(decode_error)}"}
          end
        else
          {:error, "No charts with data found in time frames"}
        end
      end
    rescue
      e ->
        Logger.error("Error extracting ship type data: #{inspect(e)}")
        {:error, "Error processing TimeFrames data: #{inspect(e)}"}
    end
  end

  @doc """
  Generates a chart URL for kills by month from TPS data.
  Returns {:ok, url} on success, {:error, reason} on failure.
  """
  def generate_kills_by_month_chart do
    case prepare_kills_by_month_data() do
      {:ok, chart_data, title, options} ->
        # Create chart configuration using the ChartConfig struct
        case ChartConfig.new(
               ChartTypes.line(),
               chart_data,
               title,
               options
             ) do
          {:ok, config} -> ChartService.generate_chart_url(config)
          {:error, reason} -> {:error, reason}
        end

      {:error, reason} ->
        # Handle specific empty response error
        error_message =
          if is_binary(reason) && String.contains?(reason, "empty response") do
            "API returned an empty response. Please check the TPS data API endpoint."
          else
            "Error fetching data: #{inspect(reason)}"
          end

        Logger.error("Failed to get TPS data for monthly chart: #{inspect(reason)}")
        ChartService.create_no_data_chart("Kills by Month", error_message)
    end
  end

  @doc """
  Prepares chart data for kills by month.
  Returns {:ok, chart_data, title, options} or {:error, reason}.
  """
  def prepare_kills_by_month_data do
    case CorpToolsClient.get_recent_tps_data() do
      {:ok, data} ->
        # Check if we have TimeFrames data
        time_frames = Map.get(data, "TimeFrames")

        if time_frames && length(time_frames) > 0 do
          Logger.debug("Found TimeFrames data with #{length(time_frames)} frames")

          # Process the first time frame's charts for monthly data
          case extract_monthly_data_from_time_frames(time_frames) do
            {:ok, monthly_data} ->
              # Sort chronologically by month
              sorted_data =
                monthly_data
                |> Enum.sort_by(fn {month, _count} -> month end)

              # Extract labels (months) and data (kill counts)
              {labels, values} = Enum.unzip(sorted_data)

              # Format month labels (e.g., "2023-01" to "Jan 2023")
              formatted_labels = Enum.map(labels, &format_month_label/1)

              Logger.debug("Month labels: #{inspect(formatted_labels)}")
              Logger.debug("Kill values by month: #{inspect(values)}")

              # Create chart data
              chart_data = %{
                "labels" => formatted_labels,
                "datasets" => [
                  %{
                    "label" => "Kills by Month",
                    "data" => values,
                    "fill" => false,
                    "backgroundColor" => "rgba(75, 192, 192, 0.8)",
                    "borderColor" => "rgba(75, 192, 192, 1)",
                    "tension" => 0.1,
                    "pointBackgroundColor" => "rgba(75, 192, 192, 1)",
                    "pointRadius" => 5
                  }
                ]
              }

              # Create chart options with custom settings
              options = %{
                "scales" => %{
                  "yAxes" => [
                    %{
                      "scaleLabel" => %{
                        "display" => true,
                        "labelString" => "Kills",
                        "fontColor" => "rgb(255, 255, 255)"
                      },
                      "ticks" => %{
                        "fontColor" => "rgb(255, 255, 255)"
                      }
                    }
                  ],
                  "xAxes" => [
                    %{
                      "scaleLabel" => %{
                        "display" => true,
                        "labelString" => "Month",
                        "fontColor" => "rgb(255, 255, 255)"
                      },
                      "ticks" => %{
                        "fontColor" => "rgb(255, 255, 255)"
                      }
                    }
                  ]
                }
              }

              {:ok, chart_data, "Kills by Month (Last 12 Months)", options}

            {:error, reason} ->
              {:error, reason}
          end
        else
          # Check for old API structure with KillsByMonth directly at root
          kills_by_month = Map.get(data, "KillsByMonth")

          if is_map(kills_by_month) and map_size(kills_by_month) > 0 do
            # Sort by month (chronologically)
            sorted_data =
              kills_by_month
              |> Enum.sort_by(fn {month, _count} -> month end)

            # Extract labels (months) and data (kill counts)
            {labels, values} = Enum.unzip(sorted_data)

            # Format month labels (e.g., "2023-01" to "Jan 2023")
            formatted_labels = Enum.map(labels, &format_month_label/1)

            Logger.debug("Month labels: #{inspect(formatted_labels)}")
            Logger.debug("Kill values by month: #{inspect(values)}")

            # Create chart data
            chart_data = %{
              "labels" => formatted_labels,
              "datasets" => [
                %{
                  "label" => "Kills by Month",
                  "data" => values,
                  "fill" => false,
                  "backgroundColor" => "rgba(75, 192, 192, 0.8)",
                  "borderColor" => "rgba(75, 192, 192, 1)",
                  "tension" => 0.1,
                  "pointBackgroundColor" => "rgba(75, 192, 192, 1)",
                  "pointRadius" => 5
                }
              ]
            }

            # Create chart options with custom settings
            options = %{
              "scales" => %{
                "yAxes" => [
                  %{
                    "scaleLabel" => %{
                      "display" => true,
                      "labelString" => "Kills",
                      "fontColor" => "rgb(255, 255, 255)"
                    },
                    "ticks" => %{
                      "fontColor" => "rgb(255, 255, 255)"
                    }
                  }
                ],
                "xAxes" => [
                  %{
                    "scaleLabel" => %{
                      "display" => true,
                      "labelString" => "Month",
                      "fontColor" => "rgb(255, 255, 255)"
                    },
                    "ticks" => %{
                      "fontColor" => "rgb(255, 255, 255)"
                    }
                  }
                ]
              }
            }

            {:ok, chart_data, "Kills by Month (Last 12 Months)", options}
          else
            {:error, "No monthly kill data available"}
          end
        end

      {:loading, message} ->
        {:error, "Data is still loading: #{message}"}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # Helper function to extract monthly data from TimeFrames structure
  defp extract_monthly_data_from_time_frames(time_frames) do
    try do
      # Find the chart with monthly data in the first time frame
      monthly_chart =
        time_frames
        |> Enum.at(0, %{})
        |> Map.get("Charts", [])
        |> Enum.find(fn chart ->
          title = Map.get(chart, "Title", "")
          String.contains?(title, "Month") or String.contains?(title, "monthly")
        end)

      if monthly_chart do
        # Extract and parse the JSON data string
        case Jason.decode(monthly_chart["Data"]) do
          {:ok, parsed_data} ->
            # Transform the data into month => count format
            # Depending on the structure, we might need to handle different formats
            cond do
              # If data is already in the format we need
              Enum.all?(parsed_data, fn item ->
                is_map(item) and Map.has_key?(item, "Month") and Map.has_key?(item, "Kills")
              end) ->
                monthly_data =
                  Enum.map(parsed_data, fn item ->
                    {Map.get(item, "Month"), Map.get(item, "Kills", 0)}
                  end)

                {:ok, monthly_data}

              # If data is in a different format, try to extract date and count
              Enum.all?(parsed_data, fn item -> is_map(item) end) ->
                # Try to find date/month field and count field
                sample = List.first(parsed_data)

                date_key =
                  Enum.find(Map.keys(sample), fn key ->
                    String.contains?(String.downcase(key), "date") or
                      String.contains?(String.downcase(key), "month") or
                      String.contains?(String.downcase(key), "time")
                  end)

                count_key =
                  Enum.find(Map.keys(sample), fn key ->
                    String.contains?(String.downcase(key), "kill") or
                      String.contains?(String.downcase(key), "count") or
                      String.contains?(String.downcase(key), "value")
                  end)

                if date_key && count_key do
                  monthly_data =
                    Enum.map(parsed_data, fn item ->
                      date_value = Map.get(item, date_key)
                      month_format = format_date_to_month(date_value)
                      {month_format, Map.get(item, count_key, 0)}
                    end)

                  {:ok, monthly_data}
                else
                  # Fallback to using arbitrary keys
                  keys = Map.keys(sample)

                  if length(keys) >= 2 do
                    # Assume first key is date/month and second is count
                    monthly_data =
                      Enum.map(parsed_data, fn item ->
                        date_value = Map.get(item, Enum.at(keys, 0))
                        count_value = Map.get(item, Enum.at(keys, 1))
                        {to_string(date_value), parse_count(count_value)}
                      end)

                    {:ok, monthly_data}
                  else
                    {:error, "Could not determine month and count fields"}
                  end
                end

              true ->
                {:error, "Data structure not recognized for monthly kills"}
            end

          {:error, decode_error} ->
            Logger.error("Failed to decode monthly data: #{inspect(decode_error)}")
            {:error, "Failed to parse monthly data: #{inspect(decode_error)}"}
        end
      else
        {:error, "No monthly chart found in time frames"}
      end
    rescue
      e ->
        Logger.error("Error extracting monthly data: #{inspect(e)}")
        {:error, "Error processing TimeFrames data for monthly kills: #{inspect(e)}"}
    end
  end

  # Helper to parse a count value that might be a string or number
  defp parse_count(value) when is_binary(value) do
    case Integer.parse(value) do
      {num, _} -> num
      :error -> 0
    end
  end

  defp parse_count(value) when is_integer(value), do: value
  defp parse_count(value) when is_float(value), do: trunc(value)
  defp parse_count(_), do: 0

  # Helper to format various date formats to YYYY-MM
  defp format_date_to_month(date) when is_binary(date) do
    cond do
      String.match?(date, ~r/^\d{4}-\d{2}$/) ->
        # Already in YYYY-MM format
        date

      String.match?(date, ~r/^\d{4}-\d{2}-\d{2}/) ->
        # YYYY-MM-DD format, extract YYYY-MM
        String.slice(date, 0, 7)

      true ->
        # Unknown format, return as is
        date
    end
  end

  defp format_date_to_month(date), do: to_string(date)

  @doc """
  Generates a chart URL for total kills and value over time.
  Returns {:ok, url} on success, {:error, reason} on failure.
  """
  def generate_total_kills_value_chart do
    case prepare_total_kills_value_data() do
      {:ok, chart_data, title, options} ->
        # Create chart configuration using the ChartConfig struct
        case ChartConfig.new(
               ChartTypes.bar(),
               chart_data,
               title,
               options
             ) do
          {:ok, config} -> ChartService.generate_chart_url(config)
          {:error, reason} -> {:error, reason}
        end

      # Direct URL return from create_no_data_chart
      {:ok, url} ->
        Logger.info("Using no-data chart URL for total kills value")
        {:ok, url}

      {:error, reason} ->
        # Handle specific empty response error
        error_message =
          if is_binary(reason) && String.contains?(reason, "empty response") do
            "API returned an empty response. Please check the TPS data API endpoint."
          else
            "Error fetching data: #{inspect(reason)}"
          end

        Logger.error("Error fetching TPS data for total value chart: #{inspect(reason)}")

        case ChartService.create_no_data_chart("Kills and Value", error_message) do
          {:ok, _url} ->
            {:ok, %{}, "Error Fetching Data", %{}}

          error ->
            error
        end
    end
  end

  @doc """
  Prepares chart data for total kills and value.
  Returns {:ok, chart_data, title, options} or {:error, reason}.
  """
  def prepare_total_kills_value_data do
    case CorpToolsClient.get_recent_tps_data() do
      {:ok, data} ->
        # Check if we have TimeFrames data
        time_frames = Map.get(data, "TimeFrames")

        if time_frames && length(time_frames) > 0 do
          Logger.debug("Found TimeFrames data with #{length(time_frames)} frames")

          # Extract monthly data and total value from TimeFrames
          with {:ok, monthly_data} <- extract_monthly_data_from_time_frames(time_frames),
               {:ok, total_value} <- extract_total_value_from_time_frames(time_frames) do
            # Sort chronologically by month
            sorted_data =
              monthly_data
              |> Enum.sort_by(fn {month, _count} -> month end)

            # Extract labels (months) and data (kill counts)
            {labels, values} = Enum.unzip(sorted_data)

            # Format month labels (e.g., "2023-01" to "Jan 2023")
            formatted_labels = Enum.map(labels, &format_month_label/1)

            # Calculate average value per kill
            total_kills = Enum.sum(values)
            avg_value_per_kill = if total_kills > 0, do: total_value / total_kills, else: 0

            # Calculate estimated value per month
            value_by_month = Enum.map(values, fn kills -> kills * avg_value_per_kill end)

            Logger.debug("Total value data - month labels: #{inspect(formatted_labels)}")
            Logger.debug("Total value data - kill values: #{inspect(values)}")
            Logger.debug("Total value data - value estimates: #{inspect(value_by_month)}")

            # Create chart data
            chart_data = %{
              "labels" => formatted_labels,
              "datasets" => [
                %{
                  "label" => "Kills",
                  "type" => "bar",
                  "data" => values,
                  "backgroundColor" => "rgba(54, 162, 235, 0.8)",
                  "borderColor" => "rgba(54, 162, 235, 1)",
                  "borderWidth" => 1,
                  "yAxisID" => "y-axis-0"
                },
                %{
                  "label" => "Estimated Value (Billions ISK)",
                  "type" => "line",
                  "data" => Enum.map(value_by_month, fn value -> value / 1_000_000_000 end),
                  "fill" => false,
                  "backgroundColor" => "rgba(255, 99, 132, 0.8)",
                  "borderColor" => "rgba(255, 99, 132, 1)",
                  "borderWidth" => 2,
                  "tension" => 0.1,
                  "pointRadius" => 4,
                  "yAxisID" => "y-axis-1"
                }
              ]
            }

            # Create chart options with multiple y-axes
            options = %{
              "scales" => %{
                "yAxes" => [
                  %{
                    "id" => "y-axis-0",
                    "type" => "linear",
                    "display" => true,
                    "position" => "left",
                    "scaleLabel" => %{
                      "display" => true,
                      "labelString" => "Kills",
                      "fontColor" => "rgb(255, 255, 255)"
                    },
                    "ticks" => %{
                      "fontColor" => "rgb(255, 255, 255)"
                    }
                  },
                  %{
                    "id" => "y-axis-1",
                    "type" => "linear",
                    "display" => true,
                    "position" => "right",
                    "scaleLabel" => %{
                      "display" => true,
                      "labelString" => "Value (Billions ISK)",
                      "fontColor" => "rgb(255, 255, 255)"
                    },
                    "ticks" => %{
                      "fontColor" => "rgb(255, 255, 255)"
                    },
                    "gridLines" => %{
                      "drawOnChartArea" => false
                    }
                  }
                ],
                "xAxes" => [
                  %{
                    "scaleLabel" => %{
                      "display" => true,
                      "labelString" => "Month",
                      "fontColor" => "rgb(255, 255, 255)"
                    },
                    "ticks" => %{
                      "fontColor" => "rgb(255, 255, 255)"
                    }
                  }
                ]
              },
              "tooltips" => %{
                "mode" => "index",
                "intersect" => false,
                "callbacks" => %{
                  "label" => "function(tooltipItem, data) {
                    var label = data.datasets[tooltipItem.datasetIndex].label || '';
                    var value = tooltipItem.yLabel;
                    if (label.indexOf('Value') >= 0) {
                      return label + ': ' + value.toFixed(2) + ' B ISK';
                    }
                    return label + ': ' + value;
                  }"
                }
              }
            }

            {:ok, chart_data, "Total Kills and Estimated Value", options}
          else
            {:error, reason} ->
              {:error, reason}
          end
        else
          # Check for old API structure with KillsByMonth and TotalValue directly at root
          kills_by_month = Map.get(data, "KillsByMonth")
          total_value = Map.get(data, "TotalValue")

          Logger.debug(
            "Total kills value data check - KillsByMonth present: #{not is_nil(kills_by_month)}"
          )

          Logger.debug(
            "Total kills value data check - TotalValue present: #{not is_nil(total_value)}"
          )

          if is_map(kills_by_month) and map_size(kills_by_month) > 0 and is_number(total_value) do
            # Sort by month (chronologically)
            sorted_data =
              kills_by_month
              |> Enum.sort_by(fn {month, _count} -> month end)

            # Extract labels (months) and data (kill counts)
            {labels, values} = Enum.unzip(sorted_data)

            # Format month labels (e.g., "2023-01" to "Jan 2023")
            formatted_labels = Enum.map(labels, &format_month_label/1)

            # Calculate average value per kill
            total_kills = Enum.sum(values)
            avg_value_per_kill = if total_kills > 0, do: total_value / total_kills, else: 0

            # Calculate estimated value per month
            value_by_month = Enum.map(values, fn kills -> kills * avg_value_per_kill end)

            Logger.debug("Total value data - month labels: #{inspect(formatted_labels)}")
            Logger.debug("Total value data - kill values: #{inspect(values)}")
            Logger.debug("Total value data - value estimates: #{inspect(value_by_month)}")

            # Create chart data
            chart_data = %{
              "labels" => formatted_labels,
              "datasets" => [
                %{
                  "label" => "Kills",
                  "type" => "bar",
                  "data" => values,
                  "backgroundColor" => "rgba(54, 162, 235, 0.8)",
                  "borderColor" => "rgba(54, 162, 235, 1)",
                  "borderWidth" => 1,
                  "yAxisID" => "y-axis-0"
                },
                %{
                  "label" => "Estimated Value (Billions ISK)",
                  "type" => "line",
                  "data" => Enum.map(value_by_month, fn value -> value / 1_000_000_000 end),
                  "fill" => false,
                  "backgroundColor" => "rgba(255, 99, 132, 0.8)",
                  "borderColor" => "rgba(255, 99, 132, 1)",
                  "borderWidth" => 2,
                  "tension" => 0.1,
                  "pointRadius" => 4,
                  "yAxisID" => "y-axis-1"
                }
              ]
            }

            # Create chart options with multiple y-axes
            options = %{
              "scales" => %{
                "yAxes" => [
                  %{
                    "id" => "y-axis-0",
                    "type" => "linear",
                    "display" => true,
                    "position" => "left",
                    "scaleLabel" => %{
                      "display" => true,
                      "labelString" => "Kills",
                      "fontColor" => "rgb(255, 255, 255)"
                    },
                    "ticks" => %{
                      "fontColor" => "rgb(255, 255, 255)"
                    }
                  },
                  %{
                    "id" => "y-axis-1",
                    "type" => "linear",
                    "display" => true,
                    "position" => "right",
                    "scaleLabel" => %{
                      "display" => true,
                      "labelString" => "Value (Billions ISK)",
                      "fontColor" => "rgb(255, 255, 255)"
                    },
                    "ticks" => %{
                      "fontColor" => "rgb(255, 255, 255)"
                    },
                    "gridLines" => %{
                      "drawOnChartArea" => false
                    }
                  }
                ],
                "xAxes" => [
                  %{
                    "scaleLabel" => %{
                      "display" => true,
                      "labelString" => "Month",
                      "fontColor" => "rgb(255, 255, 255)"
                    },
                    "ticks" => %{
                      "fontColor" => "rgb(255, 255, 255)"
                    }
                  }
                ]
              },
              "tooltips" => %{
                "mode" => "index",
                "intersect" => false,
                "callbacks" => %{
                  "label" => "function(tooltipItem, data) {
                    var label = data.datasets[tooltipItem.datasetIndex].label || '';
                    var value = tooltipItem.yLabel;
                    if (label.indexOf('Value') >= 0) {
                      return label + ': ' + value.toFixed(2) + ' B ISK';
                    }
                    return label + ': ' + value;
                  }"
                }
              }
            }

            {:ok, chart_data, "Total Kills and Estimated Value", options}
          else
            {:error, "Required data for total kills and value chart not available"}
          end
        end

      {:loading, message} ->
        {:error, "Data is still loading: #{message}"}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # Helper function to extract total value from TimeFrames structure
  defp extract_total_value_from_time_frames(time_frames) do
    try do
      # Find the chart with value data in the first time frame
      value_chart =
        time_frames
        |> Enum.at(0, %{})
        |> Map.get("Charts", [])
        |> Enum.find(fn chart ->
          title = Map.get(chart, "Title", "")

          String.contains?(title, "Value") or String.contains?(title, "ISK") or
            String.contains?(title, "Total")
        end)

      if value_chart do
        # Try to extract total value from the chart
        case Jason.decode(value_chart["Data"]) do
          {:ok, parsed_data} ->
            # Look for an explicit total value field
            total_value =
              case parsed_data do
                # If it's a map with a TotalValue key
                %{"TotalValue" => value} ->
                  value

                %{"Total" => value} ->
                  value

                %{"Value" => value} ->
                  value

                # If it's a list of objects, try to sum appropriate fields
                items when is_list(items) ->
                  Enum.reduce(items, 0, fn item, acc ->
                    value_field =
                      Map.get(
                        item,
                        "Value",
                        Map.get(
                          item,
                          "ISK",
                          Map.get(item, "TotalValue", Map.get(item, "Total", 0))
                        )
                      )

                    acc + parse_value(value_field)
                  end)

                # Fallback to a reasonable default
                # 10 billion as a fallback
                _ ->
                  10_000_000_000
              end

            {:ok, parse_value(total_value)}

          {:error, decode_error} ->
            Logger.error("Failed to decode value data: #{inspect(decode_error)}")
            # Use a fallback value to avoid breaking charts
            # 10 billion as a fallback
            {:ok, 10_000_000_000}
        end
      else
        # If no explicit value chart, try to estimate from any data we have
        # First try to find any chart with Kill data that might have value
        kill_chart =
          time_frames
          |> Enum.at(0, %{})
          |> Map.get("Charts", [])
          |> Enum.find(fn chart ->
            title = Map.get(chart, "Title", "")
            String.contains?(title, "Kill") or String.contains?(title, "Damage")
          end)

        if kill_chart do
          case Jason.decode(kill_chart["Data"]) do
            {:ok, parsed_data} when is_list(parsed_data) ->
              # Try to estimate value by assigning avg value per kill or damage
              total_count =
                Enum.reduce(parsed_data, 0, fn item, acc ->
                  kill_count =
                    Map.get(item, "Kills", Map.get(item, "FinalBlows", Map.get(item, "Count", 0)))

                  acc + parse_count(kill_count)
                end)

              # Estimate value: average 100M ISK per kill
              {:ok, total_count * 100_000_000}

            {:error, _} ->
              # Default fallback
              {:ok, 10_000_000_000}
          end
        else
          # Complete fallback
          {:ok, 10_000_000_000}
        end
      end
    rescue
      e ->
        Logger.error("Error extracting total value: #{inspect(e)}")
        # Use a fallback value to avoid breaking charts
        # 10 billion as a fallback
        {:ok, 10_000_000_000}
    end
  end

  # Helper to parse ISK value that might be in various formats
  defp parse_value(value) when is_binary(value) do
    # Try to handle numeric strings, with potential commas or B/M suffix
    value = String.trim(value)

    cond do
      String.ends_with?(value, "B") or String.ends_with?(value, "b") ->
        # Billions
        {num, _} = Float.parse(String.slice(value, 0..-2//-1))
        num * 1_000_000_000

      String.ends_with?(value, "M") or String.ends_with?(value, "m") ->
        # Millions
        {num, _} = Float.parse(String.slice(value, 0..-2//-1))
        num * 1_000_000

      String.ends_with?(value, "K") or String.ends_with?(value, "k") ->
        # Thousands
        {num, _} = Float.parse(String.slice(value, 0..-2//-1))
        num * 1_000

      true ->
        case Float.parse(String.replace(value, [",", "_"], "")) do
          {num, _} -> num
          :error -> 0
        end
    end
  end

  defp parse_value(value) when is_integer(value), do: value
  defp parse_value(value) when is_float(value), do: value
  defp parse_value(_), do: 0

  @doc """
  Generates a chart URL for all available TPS data charts.
  Returns a map of chart types to URLs.
  """
  def generate_all_charts do
    charts = %{}

    charts =
      case generate_kills_by_ship_type_chart() do
        {:ok, url} -> Map.put(charts, @chart_type_kills_by_ship_type, url)
        {:error, _} -> charts
      end

    charts =
      case generate_kills_by_month_chart() do
        {:ok, url} -> Map.put(charts, @chart_type_kills_by_month, url)
        {:error, _} -> charts
      end

    charts =
      case generate_total_kills_value_chart() do
        {:ok, url} -> Map.put(charts, @chart_type_total_kills_value, url)
        {:error, _} -> charts
      end

    charts
  end

  @doc """
  Sends a chart to Discord as an embed.

  ## Parameters
    - chart_type: The type of chart to generate and send
    - title: The title for the Discord embed (optional)
    - description: The description for the Discord embed (optional)
    - channel_id: The Discord channel ID (optional)

  ## Returns
    - {:ok, response} on success
    - {:error, reason} on failure
  """
  def send_chart_to_discord(chart_type, title \\ nil, description \\ nil, channel_id \\ nil) do
    # Generate the chart URL based on the chart type
    chart_result =
      case chart_type do
        @chart_type_kills_by_ship_type ->
          generate_kills_by_ship_type_chart()

        @chart_type_kills_by_month ->
          generate_kills_by_month_chart()

        @chart_type_total_kills_value ->
          generate_total_kills_value_chart()

        _ ->
          {:error, "Unsupported chart type: #{chart_type}"}
      end

    # Send the chart to Discord using the ChartService
    case chart_result do
      {:ok, url} ->
        # Use provided title or default based on chart type
        embed_title =
          if title do
            title
          else
            case chart_type do
              @chart_type_kills_by_ship_type -> "Kills by Ship Type"
              @chart_type_kills_by_month -> "Kills by Month"
              @chart_type_total_kills_value -> "Kills and Value Over Time"
              _ -> "EVE Online Chart"
            end
          end

        # Send the embed with the chart
        ChartService.send_chart_to_discord(url, embed_title, description, channel_id)

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Sends all available TPS charts to Discord.

  ## Returns
    - A map of chart types to results
  """
  def send_all_charts_to_discord(channel_id \\ nil) do
    # Chart types and their descriptions
    charts = [
      {@chart_type_kills_by_ship_type, "Kills by Ship Type",
       "Distribution of kills by ship type over the last 12 months"},
      {@chart_type_kills_by_month, "Kills by Month", "Kill count trend over the last 12 months"},
      {@chart_type_total_kills_value, "Kills and Value",
       "Kill count and estimated value over the last 12 months"}
    ]

    # Send each chart and collect results
    Enum.reduce(charts, %{}, fn {chart_type, title, description}, results ->
      result = send_chart_to_discord(chart_type, title, description, channel_id)
      Map.put(results, chart_type, result)
    end)
  end

  # Helper functions

  # Formats a month string (e.g., "2023-01") to a more readable format (e.g., "Jan 2023")
  defp format_month_label(month_str) when is_binary(month_str) do
    case String.split(month_str, "-") do
      [year, month] ->
        month_name =
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

        "#{month_name} #{year}"

      _ ->
        month_str
    end
  end

  defp format_month_label(other), do: inspect(other)
end
