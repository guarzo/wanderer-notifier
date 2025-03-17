defmodule WandererNotifier.CorpTools.ChartAdapter do
  @moduledoc """
  Adapts existing chart configurations for use with quickcharts.io.
  """
  require Logger
  alias WandererNotifier.CorpTools.Client, as: CorpToolsClient
  alias WandererNotifier.CorpTools.ChartHelpers

  @chart_text_color "rgb(255, 255, 255)"     # White text for Discord dark theme

  @doc """
  Debug function to print the TPS data structure.
  """
  def debug_tps_data do
    case CorpToolsClient.get_tps_data() do
      {:ok, data} ->
        # Use the shared helper for debugging TPS data
        ChartHelpers.debug_tps_data_structure(data)
        {:ok, "Debug information logged"}

      {:loading, message} ->
        Logger.info("TPS data is still loading: #{message}")
        {:loading, message}

      {:error, reason} ->
        Logger.error("Failed to get TPS data: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Generates a chart URL for top ships killed from TPS data.
  Uses the existing top_ships_killed chart configuration.

  Returns {:ok, url} on success, {:error, reason} on failure.
  """
  def generate_top_ships_killed_chart do
    # First run the debug function to log the data structure
    debug_tps_data()

    case CorpToolsClient.get_tps_data() do
      {:ok, data} ->
        Logger.info("TPS data structure for top ships received")

        # Check for data in the correct location based on API documentation
        # First try the documented structure: Last12MonthsData -> KillsByShipType
        kills_by_ship_type = case Map.get(data, "Last12MonthsData") do
          last_12_months when is_map(last_12_months) ->
            Map.get(last_12_months, "KillsByShipType", %{})
          _ -> %{}
        end

        # If that's empty, check for Charts array as a fallback
        kills_by_ship_type = if map_size(kills_by_ship_type) == 0 do
          charts = Map.get(data, "Charts", [])
          top_ships_chart = Enum.find(charts, fn chart ->
            Map.get(chart, "ID") == "topShipsKilledChart_Last12M" ||
            Map.get(chart, "Name") == "Top Ships Killed"
          end)

          if top_ships_chart do
            Logger.info("Found top ships killed chart: #{inspect(top_ships_chart["Name"])}")
            chart_data_str = Map.get(top_ships_chart, "Data", "[]")

            case Jason.decode(chart_data_str) do
              {:ok, chart_data} when is_list(chart_data) and length(chart_data) > 0 ->
                # Convert the list to a map of Name -> KillCount for consistency
                Enum.reduce(chart_data, %{}, fn item, acc ->
                  name = Map.get(item, "Name", "Unknown")
                  count = Map.get(item, "KillCount", 0)
                  Map.put(acc, name, count)
                end)
              _ -> %{}
            end
          else
            %{}
          end
        else
          kills_by_ship_type
        end

        Logger.debug("Kills by ship type: #{inspect(kills_by_ship_type, limit: 10)}")

        if is_map(kills_by_ship_type) and map_size(kills_by_ship_type) > 0 do
          # Convert to the format expected by the chart configuration
          chart_data =
            kills_by_ship_type
            |> Enum.map(fn {ship_name, kill_count} ->
              %{
                "Name" => ship_name,
                "KillCount" => kill_count
              }
            end)
            |> Enum.sort_by(fn %{"KillCount" => count} -> count end, :desc)
            |> Enum.take(10)

          # Create a bar chart configuration (simpler than word cloud for quickcharts.io)
          {labels, values} = Enum.reduce(chart_data, {[], []}, fn %{"Name" => name, "KillCount" => count}, {names, counts} ->
            {names ++ [name], counts ++ [count]}
          end)

          # Use the shared helper to create chart configuration
          chart_data = %{
            labels: labels,
            datasets: [
              %{
                label: "Top Ships Killed",
                data: values,
                backgroundColor: "rgba(54, 162, 235, 0.8)",
                borderColor: "rgba(54, 162, 235, 1)",
                borderWidth: 1
              }
            ]
          }

          chart_config = ChartHelpers.generate_chart_config("Top Ships Killed", "bar", chart_data)

          # Generate chart URL using the shared helper
          ChartHelpers.generate_chart_url(chart_config)
        else
          ChartHelpers.create_no_data_chart("Top Ships Killed")
        end

      {:loading, _} ->
        {:error, "TPS data is still loading"}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Generates a chart URL for kill activity over time from TPS data.
  Uses the existing kill_activity_over_time chart configuration.

  Returns {:ok, url} on success, {:error, reason} on failure.
  """
  def generate_kill_activity_chart do
    case CorpToolsClient.get_tps_data() do
      {:ok, data} ->
        # Extract data from the correct location based on API documentation
        last_12_months_data = Map.get(data, "Last12MonthsData", %{})

        # Try to extract kills by month
        kills_by_month = Map.get(last_12_months_data, "KillsByMonth", %{})
        Logger.debug("Kills by month: #{inspect(kills_by_month, limit: 10)}")

        if is_map(kills_by_month) and map_size(kills_by_month) > 0 do
          # Sort by month (chronologically)
          sorted_data =
            kills_by_month
            |> Enum.sort_by(fn {month, _count} -> month end)

          # Convert to the format expected by the chart configuration
          chart_data = Enum.map(sorted_data, fn {month, kills} ->
            # Convert month string (e.g., "2023-01") to ISO date format
            date = "#{month}-15T00:00:00Z"  # Middle of the month
            %{
              "Time" => date,
              "Kills" => kills
            }
          end)

          # Format for quickcharts.io
          {labels, values} = Enum.reduce(chart_data, {[], []}, fn %{"Time" => time, "Kills" => kills}, {times, kill_counts} ->
            # Format the time label using the shared helper
            formatted_time = ChartHelpers.format_month_label(time)
            {times ++ [formatted_time], kill_counts ++ [kills]}
          end)

          # Create chart data
          chart_data = %{
            labels: labels,
            datasets: [
              %{
                label: "Kills Over Time",
                data: values,
                borderColor: "rgba(255, 77, 77, 1)",
                backgroundColor: "rgba(255, 77, 77, 0.5)",
                fill: true,
                tension: 0.4,
                pointBackgroundColor: "rgba(255, 77, 77, 1)",
                pointBorderColor: "#fff",
                pointHoverBackgroundColor: "#fff",
                pointHoverBorderColor: "rgba(255, 77, 77, 1)"
              }
            ]
          }

          # Use the shared helper to create chart configuration with custom options
          options = %{
            scales: %{
              x: %{
                title: %{
                  display: true,
                  text: "Time",
                  color: @chart_text_color
                }
              },
              y: %{
                title: %{
                  display: true,
                  text: "Kills",
                  color: @chart_text_color
                }
              }
            }
          }

          chart_config = ChartHelpers.generate_chart_config("Kill Activity Over Time", "line", chart_data, options)

          # Generate chart URL using the shared helper
          ChartHelpers.generate_chart_url(chart_config)
        else
          ChartHelpers.create_no_data_chart("Kill Activity Over Time")
        end

      {:loading, _} ->
        {:error, "TPS data is still loading"}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Generates a chart URL for character performance from TPS data.
  Uses a bar chart to show performance metrics by character.

  Returns {:ok, url} on success, {:error, reason} on failure.
  """
  def generate_character_performance_chart do
    case CorpToolsClient.get_tps_data() do
      {:ok, data} ->
        # Extract data from the correct location based on API documentation
        last_12_months_data = Map.get(data, "Last12MonthsData", %{})

        # Try to extract character performance data
        character_performance = Map.get(last_12_months_data, "CharacterPerformance", %{})
        Logger.debug("Character performance: #{inspect(character_performance, limit: 10)}")

        if is_map(character_performance) and map_size(character_performance) > 0 do
          # Convert to the format expected by the chart configuration
          chart_data =
            character_performance
            |> Enum.map(fn {character_name, performance} ->
              %{
                "Name" => character_name,
                "Performance" => performance
              }
            end)
            |> Enum.sort_by(fn %{"Performance" => perf} -> perf end, :desc)
            |> Enum.take(10)

          # Create a bar chart configuration (simpler than word cloud for quickcharts.io)
          {labels, values} = Enum.reduce(chart_data, {[], []}, fn %{"Name" => name, "Performance" => perf}, {names, perfs} ->
            {names ++ [name], perfs ++ [perf]}
          end)

          # Create chart data
          chart_data = %{
            labels: labels,
            datasets: [
              %{
                label: "Character Performance",
                data: values,
                backgroundColor: "rgba(54, 162, 235, 0.8)",
                borderColor: "rgba(54, 162, 235, 1)",
                borderWidth: 1
              }
            ]
          }

          # Use the shared helper to create chart configuration
          chart_config = ChartHelpers.generate_chart_config("Character Performance", "bar", chart_data)

          # Generate chart URL using the shared helper
          ChartHelpers.generate_chart_url(chart_config)
        else
          ChartHelpers.create_no_data_chart("Character Performance")
        end

      {:loading, _} ->
        {:error, "TPS data is still loading"}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Generates a summary chart showing total kills and value from TPS data.

  Returns {:ok, url} on success, {:error, reason} on failure.
  """
  def generate_summary_chart do
    case CorpToolsClient.get_tps_data() do
      {:ok, data} ->
        # Extract data from the correct location based on API documentation
        last_12_months_data = Map.get(data, "Last12MonthsData", %{})

        # Try to extract total kills and value
        total_kills = Map.get(last_12_months_data, "TotalKills", 0)
        total_value = Map.get(last_12_months_data, "TotalValue", 0)

        Logger.debug("Total kills: #{total_kills}, Total value: #{total_value}")

        # Create chart data
        chart_data = %{
          labels: ["Kills", "Value (Billions ISK)"],
          datasets: [
            %{
              data: [total_kills, round(total_value / 1_000_000_000)],
              backgroundColor: [
                "rgba(255, 99, 132, 0.8)",
                "rgba(54, 162, 235, 0.8)"
              ],
              borderColor: [
                "rgba(255, 99, 132, 1)",
                "rgba(54, 162, 235, 1)"
              ],
              borderWidth: 1
            }
          ]
        }

        # Use the shared helper to create chart configuration with custom options
        options = %{
          plugins: %{
            legend: %{
              position: "right"
            }
          }
        }

        chart_config = ChartHelpers.generate_chart_config("Kill Summary - Last 12 Months", "doughnut", chart_data, options)

        # Generate chart URL using the shared helper
        ChartHelpers.generate_chart_url(chart_config)

      {:loading, _} ->
        {:error, "TPS data is still loading"}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Generates a chart URL for top systems from TPS data.
  Uses the existing top_systems chart configuration.

  Returns {:ok, url} on success, {:error, reason} on failure.
  """
  def generate_top_systems_chart do
    case CorpToolsClient.get_tps_data() do
      {:ok, data} ->
        # Extract data from the correct location based on API documentation
        last_12_months_data = Map.get(data, "Last12MonthsData", %{})

        # Try to extract kills by system
        kills_by_system = Map.get(last_12_months_data, "KillsBySystem", %{})
        Logger.debug("Kills by system: #{inspect(kills_by_system, limit: 10)}")

        if is_map(kills_by_system) and map_size(kills_by_system) > 0 do
          # Convert to the format expected by the chart configuration
          chart_data =
            kills_by_system
            |> Enum.map(fn {system_name, kill_count} ->
              %{
                "Name" => system_name,
                "KillCount" => kill_count
              }
            end)
            |> Enum.sort_by(fn %{"KillCount" => count} -> count end, :desc)
            |> Enum.take(10)

          # Create a bar chart configuration (simpler than word cloud for quickcharts.io)
          {labels, values} = Enum.reduce(chart_data, {[], []}, fn %{"Name" => name, "KillCount" => count}, {names, counts} ->
            {names ++ [name], counts ++ [count]}
          end)

          # Create chart data
          chart_data = %{
            labels: labels,
            datasets: [
              %{
                label: "Top Systems",
                data: values,
                backgroundColor: "rgba(54, 162, 235, 0.8)",
                borderColor: "rgba(54, 162, 235, 1)",
                borderWidth: 1
              }
            ]
          }

          # Use the shared helper to create chart configuration
          chart_config = ChartHelpers.generate_chart_config("Top Systems", "bar", chart_data)

          # Generate chart URL using the shared helper
          ChartHelpers.generate_chart_url(chart_config)
        else
          ChartHelpers.create_no_data_chart("Top Systems")
        end

      {:loading, _} ->
        {:error, "TPS data is still loading"}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Sends a chart to Discord as an embed.

  Args:
    - chart_type: The type of chart to generate (:summary, :top_ships, :kill_activity, or :character_performance)
    - title: The title for the Discord embed
    - description: The description for the Discord embed

  Returns :ok on success, {:error, reason} on failure.
  """
  def send_chart_to_discord(chart_type, title, description) do
    # Generate the chart URL based on the chart type
    chart_result = case chart_type do
      :summary -> generate_summary_chart()
      :top_ships -> generate_top_ships_killed_chart()
      :kill_activity -> generate_kill_activity_chart()
      :character_performance -> generate_character_performance_chart()
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
  WandererNotifier.CorpTools.ChartAdapter.test_send_all_charts()
  ```
  """
  def test_send_all_charts do
    Logger.info("Testing chart generation and sending to Discord")

    # Send summary chart
    summary_result = send_chart_to_discord(
      :summary,
      "Kill Summary",
      "Overview of kills and value for the last 12 months"
    )

    # Send top ships killed chart
    top_ships_result = send_chart_to_discord(
      :top_ships,
      "Top Ships Killed",
      "Most frequently killed ship types"
    )

    # Send kill activity chart
    kill_activity_result = send_chart_to_discord(
      :kill_activity,
      "Kill Activity Over Time",
      "Monthly kill activity trend"
    )

    # Send character performance chart
    character_performance_result = send_chart_to_discord(
      :character_performance,
      "Character Performance",
      "Performance metrics by character"
    )

    # Return results
    %{
      summary: summary_result,
      top_ships: top_ships_result,
      kill_activity: kill_activity_result,
      character_performance: character_performance_result
    }
  end

  @doc """
  Test function to run all chart generation functions and log the results.
  Can be called from the command line with:

  ```
  mix run -e "WandererNotifier.CorpTools.ChartAdapter.test_all_charts()"
  ```
  """
  def test_all_charts do
    Logger.info("Starting chart tests...")

    # First, get the TPS data and log its structure
    case CorpToolsClient.get_tps_data() do
      {:ok, data} ->
        # Use the shared helper for debugging TPS data
        ChartHelpers.debug_tps_data_structure(data)

        # Now test each chart function
        Logger.info("Testing top ships killed chart...")
        case generate_top_ships_killed_chart() do
          {:ok, url} -> Logger.info("Top ships killed chart URL: #{url}")
          {:error, reason} -> Logger.error("Failed to generate top ships killed chart: #{inspect(reason)}")
        end

        Logger.info("Testing summary chart...")
        case generate_summary_chart() do
          {:ok, url} -> Logger.info("Summary chart URL: #{url}")
          {:error, reason} -> Logger.error("Failed to generate summary chart: #{inspect(reason)}")
        end

        Logger.info("Testing kill activity chart...")
        case generate_kill_activity_chart() do
          {:ok, url} -> Logger.info("Kill activity chart URL: #{url}")
          {:error, reason} -> Logger.error("Failed to generate kill activity chart: #{inspect(reason)}")
        end

        Logger.info("Testing top systems chart...")
        case generate_top_systems_chart() do
          {:ok, url} -> Logger.info("Top systems chart URL: #{url}")
          {:error, reason} -> Logger.error("Failed to generate top systems chart: #{inspect(reason)}")
        end

        Logger.info("Testing character performance chart...")
        case generate_character_performance_chart() do
          {:ok, url} -> Logger.info("Character performance chart URL: #{url}")
          {:error, reason} -> Logger.error("Failed to generate character performance chart: #{inspect(reason)}")
        end

        Logger.info("Chart tests completed.")

      {:loading, message} ->
        Logger.info("TPS data is still loading: #{message}")

      {:error, reason} ->
        Logger.error("Failed to get TPS data: #{inspect(reason)}")
    end
  end
end
