defmodule WandererNotifier.CorpTools.ChartGenerator do
  @moduledoc """
  Generates charts from EVE Corp Tools TPS data using quickcharts.io.
  """
  require Logger
  alias WandererNotifier.CorpTools.CorpToolsClient

  @quickcharts_url "https://quickchart.io/chart"
  @chart_width 800
  @chart_height 400
  # Discord dark theme background
  @chart_background_color "rgb(47, 49, 54)"
  # White text for Discord dark theme
  @chart_text_color "rgb(255, 255, 255)"

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
  Generates a pie chart URL for top ship types from TPS data.
  Returns {:ok, url} on success, {:error, reason} on failure.
  """
  def generate_ship_type_pie_chart do
    case CorpToolsClient.get_tps_data() do
      {:ok, data} ->
        # Extract kills by ship type from the last 12 months data
        kills_by_ship_type = get_in(data, ["Last12MonthsData", "KillsByShipType"])

        if is_map(kills_by_ship_type) and map_size(kills_by_ship_type) > 0 do
          # Sort by kill count (descending) and take top 8
          sorted_data =
            kills_by_ship_type
            |> Enum.sort_by(fn {_ship, count} -> count end, :desc)
            |> Enum.take(8)

          # Extract labels (ship types) and data (kill counts)
          {labels, values} = Enum.unzip(sorted_data)

          # Create chart configuration
          chart_config = %{
            type: "pie",
            data: %{
              labels: labels,
              datasets: [
                %{
                  data: values,
                  backgroundColor: [
                    "rgba(255, 99, 132, 0.8)",
                    "rgba(54, 162, 235, 0.8)",
                    "rgba(255, 206, 86, 0.8)",
                    "rgba(75, 192, 192, 0.8)",
                    "rgba(153, 102, 255, 0.8)",
                    "rgba(255, 159, 64, 0.8)",
                    "rgba(199, 199, 199, 0.8)",
                    "rgba(83, 102, 255, 0.8)"
                  ],
                  borderColor: [
                    "rgba(255, 99, 132, 1)",
                    "rgba(54, 162, 235, 1)",
                    "rgba(255, 206, 86, 1)",
                    "rgba(75, 192, 192, 1)",
                    "rgba(153, 102, 255, 1)",
                    "rgba(255, 159, 64, 1)",
                    "rgba(199, 199, 199, 1)",
                    "rgba(83, 102, 255, 1)"
                  ],
                  borderWidth: 1
                }
              ]
            },
            options: %{
              responsive: true,
              plugins: %{
                title: %{
                  display: true,
                  text: "Top Ship Types Distribution",
                  color: @chart_text_color,
                  font: %{
                    size: 18
                  }
                },
                legend: %{
                  position: "right",
                  labels: %{
                    color: @chart_text_color
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

  # Helper function to format month labels
  defp format_month_label(month_str) do
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

  @doc """
  Sends a chart to Discord as an embed.

  Args:
    - chart_type: The type of chart to generate (:ship_type, :monthly, or :pie)
    - title: The title for the Discord embed
    - description: The description for the Discord embed

  Returns :ok on success, {:error, reason} on failure.
  """
  def send_chart_to_discord(chart_type, title, description) do
    # Generate the chart URL based on the chart type
    chart_result =
      case chart_type do
        :ship_type -> generate_kills_by_ship_type_chart()
        :monthly -> generate_kills_by_month_chart()
        :pie -> generate_ship_type_pie_chart()
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
  Test function to generate and send all charts to Discord.
  Can be called from IEx console with:

  ```
  WandererNotifier.CorpTools.ChartGenerator.test_send_all_charts()
  ```
  """
  def test_send_all_charts do
    Logger.info("Testing chart generation and sending to Discord")

    # Send ship type bar chart
    ship_type_result =
      send_chart_to_discord(
        :ship_type,
        "Ship Type Analysis",
        "Top 10 ship types used in kills over the last 12 months"
      )

    # Send monthly kills line chart
    monthly_result =
      send_chart_to_discord(
        :monthly,
        "Monthly Kill Activity",
        "Kill activity trend over the last 12 months"
      )

    # Send ship type pie chart
    pie_result =
      send_chart_to_discord(
        :pie,
        "Ship Type Distribution",
        "Distribution of top 8 ship types used in kills"
      )

    # Return results
    %{
      ship_type: ship_type_result,
      monthly: monthly_result,
      pie: pie_result
    }
  end
end
