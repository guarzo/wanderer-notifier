defmodule WandererNotifier.CorpTools.TPSChartAdapter do
  @moduledoc """
  Adapts TPS data from the EVE Corp Tools API for use with quickchart.io.
  """
  require Logger
  alias WandererNotifier.CorpTools.Client, as: CorpToolsClient

  @quickcharts_url "https://quickchart.io/chart"
  @chart_width 800
  @chart_height 400
  @chart_background_color "rgb(47, 49, 54)"  # Discord dark theme background
  @chart_text_color "rgb(255, 255, 255)"     # White text for Discord dark theme

  @doc """
  Generates a chart URL for kills by ship type from TPS data.
  Returns {:ok, url} on success, {:error, reason} on failure.
  """
  def generate_kills_by_ship_type_chart do
    case CorpToolsClient.get_tps_data() do
      {:ok, data} ->
        # Extract kills by ship type from the last 12 months data
        kills_by_ship_type = get_in(data, ["Last12MonthsData", "KillsByShipType"])

        if is_map(kills_by_ship_type) and map_size(kills_by_ship_type) > 0 do
          # Sort by kill count (descending) and take top 10
          sorted_data =
            kills_by_ship_type
            |> Enum.sort_by(fn {_ship, count} -> count end, :desc)
            |> Enum.take(10)

          # Extract labels (ship types) and data (kill counts)
          {labels, values} = Enum.unzip(sorted_data)

          # Create chart configuration
          chart_config = %{
            type: "bar",
            data: %{
              labels: labels,
              datasets: [
                %{
                  label: "Kills by Ship Type (Last 12 Months)",
                  data: values,
                  backgroundColor: "rgba(54, 162, 235, 0.8)",
                  borderColor: "rgba(54, 162, 235, 1)",
                  borderWidth: 1
                }
              ]
            },
            options: %{
              responsive: true,
              plugins: %{
                title: %{
                  display: true,
                  text: "Top 10 Ship Types by Kills",
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
                  }
                }
              }
            },
            backgroundColor: @chart_background_color
          }

          # Generate chart URL
          generate_chart_url(chart_config)
        else
          {:error, "No ship type data available"}
        end

      {:loading, _} ->
        {:error, "TPS data is still loading"}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Generates a chart URL for kills by month from TPS data.
  Returns {:ok, url} on success, {:error, reason} on failure.
  """
  def generate_kills_by_month_chart do
    case CorpToolsClient.get_tps_data() do
      {:ok, data} ->
        # Extract kills by month from the last 12 months data
        kills_by_month = get_in(data, ["Last12MonthsData", "KillsByMonth"])

        if is_map(kills_by_month) and map_size(kills_by_month) > 0 do
          # Sort by month (chronologically)
          sorted_data =
            kills_by_month
            |> Enum.sort_by(fn {month, _count} ->
              # Convert month string (e.g., "2023-01") to sortable value
              month
            end)

          # Extract labels (months) and data (kill counts)
          {labels, values} = Enum.unzip(sorted_data)

          # Format month labels (e.g., "2023-01" to "Jan 2023")
          formatted_labels = Enum.map(labels, &format_month_label/1)

          # Create chart configuration
          chart_config = %{
            type: "line",
            data: %{
              labels: formatted_labels,
              datasets: [
                %{
                  label: "Kills by Month",
                  data: values,
                  fill: false,
                  backgroundColor: "rgba(75, 192, 192, 0.8)",
                  borderColor: "rgba(75, 192, 192, 1)",
                  tension: 0.1,
                  pointBackgroundColor: "rgba(75, 192, 192, 1)",
                  pointRadius: 5
                }
              ]
            },
            options: %{
              responsive: true,
              plugins: %{
                title: %{
                  display: true,
                  text: "Kills by Month (Last 12 Months)",
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
            },
            backgroundColor: @chart_background_color
          }

          # Generate chart URL
          generate_chart_url(chart_config)
        else
          {:error, "No monthly data available"}
        end

      {:loading, _} ->
        {:error, "TPS data is still loading"}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Generates a chart URL for total kills and value over time.
  Returns {:ok, url} on success, {:error, reason} on failure.
  """
  def generate_total_kills_value_chart do
    case CorpToolsClient.get_tps_data() do
      {:ok, data} ->
        # Extract kills by month and total value from the last 12 months data
        kills_by_month = get_in(data, ["Last12MonthsData", "KillsByMonth"])
        total_value = get_in(data, ["Last12MonthsData", "TotalValue"])

        if is_map(kills_by_month) and map_size(kills_by_month) > 0 do
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

          # Create chart configuration
          chart_config = %{
            type: "bar",
            data: %{
              labels: formatted_labels,
              datasets: [
                %{
                  label: "Kills",
                  type: "bar",
                  data: values,
                  backgroundColor: "rgba(54, 162, 235, 0.8)",
                  borderColor: "rgba(54, 162, 235, 1)",
                  borderWidth: 1,
                  yAxisID: "y"
                },
                %{
                  label: "Estimated Value (Billions ISK)",
                  type: "line",
                  data: Enum.map(value_by_month, fn value -> value / 1_000_000_000 end),
                  fill: false,
                  backgroundColor: "rgba(255, 99, 132, 0.8)",
                  borderColor: "rgba(255, 99, 132, 1)",
                  borderWidth: 2,
                  tension: 0.1,
                  pointRadius: 4,
                  yAxisID: "y1"
                }
              ]
            },
            options: %{
              responsive: true,
              plugins: %{
                title: %{
                  display: true,
                  text: "Kills and Value Over Time",
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
                  type: "linear",
                  display: true,
                  position: "left",
                  title: %{
                    display: true,
                    text: "Kills",
                    color: @chart_text_color
                  },
                  ticks: %{
                    color: @chart_text_color
                  },
                  grid: %{
                    color: "rgba(255, 255, 255, 0.1)"
                  }
                },
                y1: %{
                  type: "linear",
                  display: true,
                  position: "right",
                  title: %{
                    display: true,
                    text: "Value (Billions ISK)",
                    color: @chart_text_color
                  },
                  ticks: %{
                    color: @chart_text_color
                  },
                  grid: %{
                    color: "rgba(255, 255, 255, 0.1)",
                    drawOnChartArea: false
                  }
                }
              }
            },
            backgroundColor: @chart_background_color
          }

          # Generate chart URL
          generate_chart_url(chart_config)
        else
          {:error, "No monthly data available"}
        end

      {:loading, _} ->
        {:error, "TPS data is still loading"}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Generates a chart URL for all available TPS data charts.
  Returns a map of chart types to URLs.
  """
  def generate_all_charts do
    charts = %{}

    charts = case generate_kills_by_ship_type_chart() do
      {:ok, url} -> Map.put(charts, "kills_by_ship_type", url)
      {:error, _} -> charts
    end

    charts = case generate_kills_by_month_chart() do
      {:ok, url} -> Map.put(charts, "kills_by_month", url)
      {:error, _} -> charts
    end

    charts = case generate_total_kills_value_chart() do
      {:ok, url} -> Map.put(charts, "total_kills_value", url)
      {:error, _} -> charts
    end

    charts
  end

  @doc """
  Sends a TPS chart to Discord as an embed.

  Args:
    - chart_type: The type of chart to generate (:kills_by_ship_type, :kills_by_month, or :total_kills_value)
    - title: The title for the Discord embed
    - description: The description for the Discord embed

  Returns :ok on success, {:error, reason} on failure.
  """
  def send_chart_to_discord(chart_type, title, description) do
    # Generate the chart URL based on the chart type
    chart_result = case chart_type do
      :kills_by_ship_type -> generate_kills_by_ship_type_chart()
      :kills_by_month -> generate_kills_by_month_chart()
      :total_kills_value -> generate_total_kills_value_chart()
      _ -> {:error, "Invalid chart type"}
    end

    case chart_result do
      {:ok, url} ->
        # Get the notifier
        notifier = WandererNotifier.NotifierFactory.get_notifier()

        # Send the chart as an embed
        notifier.send_embed(title, description, url)

      {:error, reason} ->
        Logger.error("Failed to generate chart: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Sends all TPS charts to Discord.
  Returns a map with the result of each chart send operation.
  """
  def send_all_charts_to_discord do
    Logger.info("Sending all TPS charts to Discord")

    # Send kills by ship type chart
    ship_type_result = send_chart_to_discord(
      :kills_by_ship_type,
      "Top Ship Types by Kills",
      "Shows the top 10 ship types used in kills over the last 12 months"
    )

    # Send kills by month chart
    monthly_result = send_chart_to_discord(
      :kills_by_month,
      "Kills by Month",
      "Shows the number of kills per month over the last 12 months"
    )

    # Send total kills and value chart
    value_result = send_chart_to_discord(
      :total_kills_value,
      "Kills and Value Over Time",
      "Shows the number of kills and estimated value over time"
    )

    # Return results
    %{
      kills_by_ship_type: ship_type_result,
      kills_by_month: monthly_result,
      total_kills_value: value_result
    }
  end

  # Helper function to format month labels
  defp format_month_label(month_str) do
    case String.split(month_str, "-") do
      [year, month] ->
        month_name = case month do
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
      _ -> month_str
    end
  end

  # Helper function to generate chart URL
  defp generate_chart_url(chart_config) do
    # Convert chart configuration to JSON
    case Jason.encode(chart_config) do
      {:ok, json} ->
        # URL encode the JSON
        encoded_config = URI.encode_www_form(json)

        # Construct the URL
        url = "#{@quickcharts_url}?c=#{encoded_config}&w=#{@chart_width}&h=#{@chart_height}"

        {:ok, url}

      {:error, reason} ->
        Logger.error("Failed to encode chart configuration: #{inspect(reason)}")
        {:error, "Failed to encode chart configuration"}
    end
  end
end
