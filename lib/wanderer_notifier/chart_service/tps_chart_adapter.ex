defmodule WandererNotifier.ChartService.TPSChartAdapter do
  @moduledoc """
  Adapter for TPS (Time, Pilots, Ships) chart generation using the ChartService.

  This adapter processes data from the EVE Corp Tools API to generate various
  charts related to TPS data, such as character damage and final blows,
  combined losses, and kill activity over time.
  """

  require Logger
  alias WandererNotifier.ChartService
  alias WandererNotifier.ChartService.ChartConfig
  alias WandererNotifier.ChartService.ChartTypes
  alias WandererNotifier.CorpTools.CorpToolsClient

  @doc """
  Generates a chart for the specified chart type.

  ## Parameters
    - chart_type: The type of chart to generate

  ## Returns
    - {:ok, url} on success
    - {:error, reason} on failure
  """
  def generate_chart(chart_type) do
    Logger.info("Generating chart for type: #{inspect(chart_type)}")

    case chart_type do
      :damage_final_blows ->
        prepare_damage_final_blows_chart()

      :combined_losses ->
        prepare_combined_losses_chart()

      :kill_activity ->
        prepare_kill_activity_chart()

      # Add EVE-specific chart types
      :kills_by_ship_type ->
        prepare_kills_by_ship_type_chart()

      :kills_by_month ->
        prepare_kills_by_month_chart()

      :total_kills_value ->
        prepare_total_kills_value_chart()

      _ ->
        {:error, "Unsupported chart type: #{inspect(chart_type)}"}
    end
  end

  @doc """
  Sends a chart to Discord.

  ## Parameters
    - chart_type: The type of chart to generate and send
    - title: The title for the Discord embed
    - description: The description for the Discord embed (optional)
    - channel_id: The Discord channel ID (optional)

  ## Returns
    - {:ok, response} on success
    - {:error, reason} on failure
  """
  def send_chart_to_discord(chart_type, title, description \\ nil, channel_id \\ nil) do
    Logger.info("Sending chart to Discord: #{inspect(chart_type)}, #{title}")

    case generate_chart(chart_type) do
      {:ok, url} ->
        ChartService.send_chart_to_discord(url, title, description, channel_id)

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Generates a chart URL for kills by ship type from TPS data.
  Returns {:ok, url} on success, {:error, reason} on failure.
  """
  def generate_kills_by_ship_type_chart do
    prepare_kills_by_ship_type_chart()
  end

  @doc """
  Generates a chart URL for kills by month from TPS data.
  Returns {:ok, url} on success, {:error, reason} on failure.
  """
  def generate_kills_by_month_chart do
    prepare_kills_by_month_chart()
  end

  @doc """
  Generates a chart URL for total kills and value over time.
  Returns {:ok, url} on success, {:error, reason} on failure.
  """
  def generate_total_kills_value_chart do
    prepare_total_kills_value_chart()
  end

  @doc """
  Generates a chart URL for all available TPS data charts.
  Returns a map of chart types to URLs.
  """
  def generate_all_charts do
    charts = %{}

    charts =
      case generate_kills_by_ship_type_chart() do
        {:ok, url} -> Map.put(charts, :kills_by_ship_type, url)
        {:error, _} -> charts
      end

    charts =
      case generate_kills_by_month_chart() do
        {:ok, url} -> Map.put(charts, :kills_by_month, url)
        {:error, _} -> charts
      end

    charts =
      case generate_total_kills_value_chart() do
        {:ok, url} -> Map.put(charts, :total_kills_value, url)
        {:error, _} -> charts
      end

    # Add any new chart types here

    charts
  end

  @doc """
  Sends all available TPS charts to Discord.

  ## Returns
    - A map of chart types to results
  """
  def send_all_charts_to_discord(channel_id \\ nil) do
    # Chart types and their descriptions
    charts = [
      {:kills_by_ship_type, "Kills by Ship Type",
       "Distribution of kills by ship type over the last 12 months"},
      {:kills_by_month, "Kills by Month", "Kill count trend over the last 12 months"},
      {:total_kills_value, "Kills and Value",
       "Kill count and estimated value over the last 12 months"},
      {:damage_final_blows, "Damage and Final Blows", 
       "Character damage dealt and final blows in recent combat"},
      {:combined_losses, "Combined Losses", 
       "Character losses in terms of both count and value"},
      {:kill_activity, "Kill Activity", 
       "Combat activity patterns over the last 7 days"}
    ]

    # Send each chart and collect results
    Enum.reduce(charts, %{}, fn {chart_type, title, description}, results ->
      result = send_chart_to_discord(chart_type, title, description, channel_id)
      Map.put(results, chart_type, result)
    end)
  end

  # Private helpers

  defp prepare_damage_final_blows_chart do
    Logger.info("Preparing damage and final blows chart")

    case CorpToolsClient.get_recent_tps_data() do
      {:ok, data} ->
        # Log essential structure info to diagnose the issue
        Logger.info("RECEIVED TPS DATA: #{inspect(data)}")
        
        # Extract character performance data
        character_performance_data = extract_character_performance_data(data)
        
        # Log the extracted data
        Logger.debug("Extracted character data: #{inspect(character_performance_data, pretty: true)}")

        if is_list(character_performance_data) and length(character_performance_data) > 0 do
          # Sort by damage done (descending) and take top 20
          sorted_data =
            character_performance_data
            |> Enum.sort_by(fn char -> Map.get(char, "DamageDone", 0) end, :desc)
            |> Enum.take(20)

          # Extract labels and data
          labels = Enum.map(sorted_data, fn char -> Map.get(char, "Name", "Unknown") end)
          damage_done = Enum.map(sorted_data, fn char -> Map.get(char, "DamageDone", 0) end)
          final_blows = Enum.map(sorted_data, fn char -> Map.get(char, "FinalBlows", 0) end)

          # Create chart data
          chart_data = %{
            "labels" => labels,
            "datasets" => [
              %{
                "label" => "Damage Done",
                "data" => damage_done,
                "backgroundColor" => "rgba(255, 77, 77, 0.7)",
                "borderColor" => "rgba(255, 77, 77, 1)",
                "borderWidth" => 1,
                "yAxisID" => "y"
              },
              %{
                "label" => "Final Blows",
                "data" => final_blows,
                "backgroundColor" => "rgba(54, 162, 235, 0.7)",
                "borderColor" => "rgba(54, 162, 235, 1)",
                "borderWidth" => 1,
                "yAxisID" => "y1"
              }
            ]
          }

          # Additional options for multiple y-axes
          options = %{
            "scales" => %{
              "y" => %{
                "title" => %{
                  "display" => true,
                  "text" => "Damage Done"
                }
              },
              "y1" => %{
                "title" => %{
                  "display" => true,
                  "text" => "Final Blows"
                },
                "position" => "right",
                "grid" => %{
                  "drawOnChartArea" => false
                }
              }
            }
          }

          # Create chart with the ChartService
          case ChartConfig.new(
                 ChartTypes.bar(),
                 chart_data,
                 "Damage Done & Final Blows",
                 options
               ) do
            {:ok, config} -> ChartService.generate_chart_url(config)
            {:error, reason} -> {:error, reason}
          end
        else
          Logger.error("Character damage/final blows data not found in the expected format")
          {:error, "Character damage/final blows data not found in the expected format"}
        end

      {:loading, _} ->
        {:error, "TPS data is still loading"}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp prepare_combined_losses_chart do
    Logger.info("Preparing combined losses chart")

    case CorpToolsClient.get_recent_tps_data() do
      {:ok, data} ->
        # Log the data structure for debugging
        Logger.debug("TPS losses data structure: #{inspect(data, pretty: true, limit: 5000)}")
        
        # Extract character losses data
        character_losses_data = extract_character_losses_data(data)
        
        # Log the extracted data
        Logger.debug("Extracted losses data: #{inspect(character_losses_data, pretty: true)}")

        if is_list(character_losses_data) and length(character_losses_data) > 0 do
          # Sort by losses value (descending) and take top 10
          sorted_data =
            character_losses_data
            |> Enum.sort_by(fn char -> Map.get(char, "LossesValue", 0) end, :desc)
            |> Enum.take(10)

          # Extract labels and data
          labels = Enum.map(sorted_data, fn char -> Map.get(char, "CharacterName", "Unknown") end)
          losses_value = Enum.map(sorted_data, fn char -> Map.get(char, "LossesValue", 0) end)
          losses_count = Enum.map(sorted_data, fn char -> Map.get(char, "LossesCount", 0) end)

          # Create chart data
          chart_data = %{
            "labels" => labels,
            "datasets" => [
              %{
                "label" => "Losses Value",
                "data" => losses_value,
                "backgroundColor" => "rgba(255, 99, 132, 0.7)",
                "borderColor" => "rgba(255, 99, 132, 1)",
                "borderWidth" => 1,
                "yAxisID" => "y"
              },
              %{
                "label" => "Losses Count",
                "data" => losses_count,
                "backgroundColor" => "rgba(54, 162, 235, 0.7)",
                "borderColor" => "rgba(54, 162, 235, 1)",
                "borderWidth" => 1,
                "yAxisID" => "y1"
              }
            ]
          }

          # Options for multiple y-axes
          options = %{
            "scales" => %{
              "y" => %{
                "type" => "linear",
                "position" => "left",
                "title" => %{
                  "display" => true,
                  "text" => "Losses Value"
                }
              },
              "y1" => %{
                "type" => "linear",
                "position" => "right",
                "title" => %{
                  "display" => true,
                  "text" => "Losses Count"
                },
                "grid" => %{
                  "drawOnChartArea" => false
                }
              }
            }
          }

          # Create chart with the ChartService
          case ChartConfig.new(
                 ChartTypes.bar(),
                 chart_data,
                 "Combined Losses",
                 options
               ) do
            {:ok, config} -> ChartService.generate_chart_url(config)
            {:error, reason} -> {:error, reason}
          end
        else
          Logger.error("Combined losses data not found in the expected format")
          {:error, "Combined losses data not found in the expected format"}
        end

      {:loading, _} ->
        {:error, "TPS data is still loading"}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp prepare_kill_activity_chart do
    Logger.info("Preparing kill activity chart")

    case CorpToolsClient.get_recent_tps_data() do
      {:ok, data} ->
        # Log the data structure for debugging
        Logger.debug("TPS kill activity data structure: #{inspect(data, pretty: true, limit: 5000)}")
        
        # Find Kill Activity chart in TimeFrames structure
        if is_map(data) && is_list(data["TimeFrames"]) && length(data["TimeFrames"]) > 0 do
          time_frame = Enum.at(data["TimeFrames"], 0, %{})
          charts = Map.get(time_frame, "Charts", [])
          
          # Find Kill Activity chart by ID
          activity_chart = Enum.find(charts, fn chart -> 
            id = Map.get(chart, "ID", "")
            String.contains?(id, "killActivityOverTimeChart")
          end)
          
          if activity_chart do
            Logger.info("Found Kill Activity chart: #{Map.get(activity_chart, "Name", "unknown")}")
            # Parse JSON data string
            chart_data = Map.get(activity_chart, "Data", "[]")
            
            case Jason.decode(chart_data) do
              {:ok, activity_data} when is_list(activity_data) ->
                Logger.info("Successfully parsed Kill Activity chart data")
                
                # Extract time and kills data
                times = Enum.map(activity_data, fn point -> Map.get(point, "Time", "") end)
                kills = Enum.map(activity_data, fn point -> Map.get(point, "Kills", 0) end)
                
                # Format time labels (extract dates from full timestamp)
                formatted_labels = Enum.map(times, fn time ->
                  case String.split(time, "T") do
                    [date | _] -> date
                    _ -> time
                  end
                end)
                
                # Create chart data
                line_chart_data = %{
                  "labels" => formatted_labels,
                  "datasets" => [
                    %{
                      "label" => "Kill Activity",
                      "data" => kills,
                      "fill" => false,
                      "backgroundColor" => "rgba(75, 192, 192, 0.7)",
                      "borderColor" => "rgba(75, 192, 192, 1)",
                      "tension" => 0.2,
                      "pointBackgroundColor" => "rgba(75, 192, 192, 1)",
                      "pointRadius" => 4
                    }
                  ]
                }
                
                # Create chart with the ChartService
                case ChartConfig.new(
                       ChartTypes.line(),
                       line_chart_data,
                       "Kill Activity Over Time"
                     ) do
                  {:ok, config} -> ChartService.generate_chart_url(config)
                  {:error, reason} -> {:error, reason}
                end
                
              {:error, error} ->
                Logger.error("Failed to parse Kill Activity chart data: #{inspect(error)}")
                {:error, "Failed to parse Kill Activity chart data"}
              
              _ ->
                Logger.error("Unexpected format in Kill Activity chart data")
                {:error, "Unexpected format in Kill Activity chart data"}
            end
          else
            Logger.error("Kill Activity chart not found in expected TimeFrames structure")
            {:error, "Kill Activity chart not found in expected TimeFrames structure"}
          end
        else
          Logger.error("Expected TimeFrames data structure not found")
          {:error, "Expected TimeFrames data structure not found"}
        end

      {:loading, _} ->
        {:error, "TPS data is still loading"}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # Implements methods from the old TPSChartAdapter

  defp prepare_kills_by_ship_type_chart do
    Logger.info("Preparing kills by ship type chart")

    case CorpToolsClient.get_recent_tps_data() do
      {:ok, data} ->
        # Extract ship type chart data
        if is_map(data) && is_list(data["TimeFrames"]) && length(data["TimeFrames"]) > 0 do
          time_frame = Enum.at(data["TimeFrames"], 0, %{})
          charts = Map.get(time_frame, "Charts", [])
          
          # Find Top Ships Killed chart by ID
          ship_type_chart = Enum.find(charts, fn chart -> 
            id = Map.get(chart, "ID", "")
            String.contains?(id, "topShipsKilledChart")
          end)
          
          if ship_type_chart do
            Logger.info("Found Ship Type chart: #{Map.get(ship_type_chart, "Name", "unknown")}")
            # Parse JSON data string
            chart_data = Map.get(ship_type_chart, "Data", "[]")
            
            case Jason.decode(chart_data) do
              {:ok, ships_data} when is_list(ships_data) ->
                Logger.info("Successfully parsed Ship Type chart data")
                
                # Sort by kill count (descending) and take top 10
                sorted_data =
                  ships_data
                  |> Enum.sort_by(fn ship -> Map.get(ship, "KillCount", 0) end, :desc)
                  |> Enum.take(10)

                # Extract labels and data
                labels = Enum.map(sorted_data, fn ship -> Map.get(ship, "Name", "Unknown") end)
                values = Enum.map(sorted_data, fn ship -> Map.get(ship, "KillCount", 0) end)

                # Create chart data
                ship_chart_data = %{
                  "labels" => labels,
                  "datasets" => [
                    %{
                      "label" => "Kills by Ship Type",
                      "data" => values,
                      "backgroundColor" => "rgba(54, 162, 235, 0.8)",
                      "borderColor" => "rgba(54, 162, 235, 1)",
                      "borderWidth" => 1
                    }
                  ]
                }
                
                # Create chart with the ChartService
                case ChartConfig.new(
                      ChartTypes.bar(),
                      ship_chart_data,
                      "Top Ship Types by Kills"
                    ) do
                  {:ok, config} -> ChartService.generate_chart_url(config)
                  {:error, reason} -> {:error, reason}
                end
                
              {:error, error} ->
                Logger.error("Failed to parse Ship Type chart data: #{inspect(error)}")
                {:error, "Failed to parse Ship Type chart data"}
              
              _ ->
                Logger.error("Unexpected format in Ship Type chart data")
                {:error, "Unexpected format in Ship Type chart data"}
            end
          else
            Logger.error("Ship Type chart not found in expected TimeFrames structure")
            {:error, "Ship Type chart not found in expected TimeFrames structure"}
          end
        else
          Logger.error("Expected TimeFrames data structure not found")
          {:error, "Expected TimeFrames data structure not found"}
        end

      {:loading, _} ->
        {:error, "TPS data is still loading"}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp prepare_kills_by_month_chart do
    Logger.info("Preparing kills by month chart")

    case CorpToolsClient.get_recent_tps_data() do
      {:ok, data} ->
        # Find Kill Activity chart which contains our monthly data
        if is_map(data) && is_list(data["TimeFrames"]) && length(data["TimeFrames"]) > 0 do
          time_frame = Enum.at(data["TimeFrames"], 0, %{})
          charts = Map.get(time_frame, "Charts", [])
          
          # Find Kill Activity chart by ID - we'll repurpose this data for monthly stats
          activity_chart = Enum.find(charts, fn chart -> 
            id = Map.get(chart, "ID", "")
            String.contains?(id, "killActivityOverTimeChart")
          end)
          
          if activity_chart do
            Logger.info("Found activity chart for monthly data: #{Map.get(activity_chart, "Name", "unknown")}")
            # Parse JSON data string
            chart_data = Map.get(activity_chart, "Data", "[]")
            
            case Jason.decode(chart_data) do
              {:ok, activity_data} when is_list(activity_data) ->
                Logger.info("Successfully parsed activity data for monthly chart")
                
                # Extract time and kills data and group by month
                monthly_data = Enum.reduce(activity_data, %{}, fn point, acc ->
                  time = Map.get(point, "Time", "")
                  kills = Map.get(point, "Kills", 0)
                  
                  # Extract month from timestamp (YYYY-MM)
                  month = case String.split(time, "T") do
                    [date | _] -> 
                      case String.split(date, "-") do
                        [year, month, _] -> "#{year}-#{month}"
                        _ -> date
                      end
                    _ -> time
                  end
                  
                  # Add kills to month total
                  Map.update(acc, month, kills, &(&1 + kills))
                end)
                
                # Convert map to sorted list
                sorted_data = 
                  monthly_data
                  |> Enum.sort_by(fn {month, _} -> month end)
                  |> Enum.take(12) # Last 12 months
                
                # Extract labels and values
                {months, kills} = Enum.unzip(sorted_data)
                
                # Format month labels
                formatted_months = Enum.map(months, fn month ->
                  case String.split(month, "-") do
                    [year, month_num] ->
                      month_name = case month_num do
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
                        _ -> month_num
                      end
                      "#{month_name} #{year}"
                    _ -> month
                  end
                end)
                
                # Create chart data
                month_chart_data = %{
                  "labels" => formatted_months,
                  "datasets" => [
                    %{
                      "label" => "Kills by Month",
                      "data" => kills,
                      "fill" => false,
                      "backgroundColor" => "rgba(75, 192, 192, 0.8)",
                      "borderColor" => "rgba(75, 192, 192, 1)",
                      "tension" => 0.1,
                      "pointBackgroundColor" => "rgba(75, 192, 192, 1)",
                      "pointRadius" => 5
                    }
                  ]
                }
                
                # Chart options
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
                
                # Create chart with the ChartService
                case ChartConfig.new(
                      ChartTypes.line(),
                      month_chart_data,
                      "Kills by Month (Last 12 Months)",
                      options
                    ) do
                  {:ok, config} -> ChartService.generate_chart_url(config)
                  {:error, reason} -> {:error, reason}
                end
                
              {:error, error} ->
                Logger.error("Failed to parse monthly data: #{inspect(error)}")
                {:error, "Failed to parse monthly data"}
              
              _ ->
                Logger.error("Unexpected format in monthly data")
                {:error, "Unexpected format in monthly data"}
            end
          else
            Logger.error("Monthly chart data not found in expected TimeFrames structure")
            {:error, "Monthly chart data not found in expected TimeFrames structure"}
          end
        else
          Logger.error("Expected TimeFrames data structure not found")
          {:error, "Expected TimeFrames data structure not found"}
        end

      {:loading, _} ->
        {:error, "TPS data is still loading"}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp prepare_total_kills_value_chart do
    Logger.info("Preparing total kills value chart")

    case CorpToolsClient.get_recent_tps_data() do
      {:ok, data} ->
        # Similar to monthly data but with added value component
        if is_map(data) && is_list(data["TimeFrames"]) && length(data["TimeFrames"]) > 0 do
          time_frame = Enum.at(data["TimeFrames"], 0, %{})
          charts = Map.get(time_frame, "Charts", [])
          
          # Find Kill-to-Loss Ratio chart for value data
          value_chart = Enum.find(charts, fn chart -> 
            id = Map.get(chart, "ID", "")
            String.contains?(id, "killToLossRatioChart")
          end)
          
          # Also find kill activity chart for the activity data
          activity_chart = Enum.find(charts, fn chart -> 
            id = Map.get(chart, "ID", "")
            String.contains?(id, "killActivityOverTimeChart")
          end)
          
          if value_chart && activity_chart do
            Logger.info("Found both value and activity charts for total value chart")
            
            # Get value data
            value_data = Map.get(value_chart, "Data", "[]")
            value_result = Jason.decode(value_data)
            
            # Get activity data
            activity_data = Map.get(activity_chart, "Data", "[]")
            activity_result = Jason.decode(activity_data)
            
            case {value_result, activity_result} do
              {{:ok, value_list}, {:ok, activity_list}} when is_list(value_list) and is_list(activity_list) ->
                Logger.info("Successfully parsed both value and activity data")
                
                # Extract total value
                total_value = Enum.reduce(value_list, 0, fn item, acc ->
                  isk_destroyed = Map.get(item, "ISKDestroyed", 0)
                  acc + isk_destroyed
                end)
                
                # Group activity data by month
                monthly_data = Enum.reduce(activity_list, %{}, fn point, acc ->
                  time = Map.get(point, "Time", "")
                  kills = Map.get(point, "Kills", 0)
                  
                  # Extract month from timestamp (YYYY-MM)
                  month = case String.split(time, "T") do
                    [date | _] -> 
                      case String.split(date, "-") do
                        [year, month, _] -> "#{year}-#{month}"
                        _ -> date
                      end
                    _ -> time
                  end
                  
                  # Add kills to month total
                  Map.update(acc, month, kills, &(&1 + kills))
                end)
                
                # Convert map to sorted list
                sorted_data = 
                  monthly_data
                  |> Enum.sort_by(fn {month, _} -> month end)
                  |> Enum.take(12) # Last 12 months
                
                # Extract labels and values
                {months, kills} = Enum.unzip(sorted_data)
                
                # Format month labels
                formatted_months = Enum.map(months, fn month ->
                  case String.split(month, "-") do
                    [year, month_num] ->
                      month_name = case month_num do
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
                        _ -> month_num
                      end
                      "#{month_name} #{year}"
                    _ -> month
                  end
                end)
                
                # Calculate average value per kill
                total_kills = Enum.sum(kills)
                avg_value_per_kill = if total_kills > 0, do: total_value / total_kills, else: 0
                
                # Calculate estimated value per month
                value_by_month = Enum.map(kills, fn kills -> kills * avg_value_per_kill end)
                
                # Create chart data with combined dataset
                combined_chart_data = %{
                  "labels" => formatted_months,
                  "datasets" => [
                    %{
                      "label" => "Kills",
                      "type" => "bar",
                      "data" => kills,
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
                
                # Create chart with the ChartService
                case ChartConfig.new(
                      ChartTypes.bar(),
                      combined_chart_data,
                      "Total Kills and Estimated Value",
                      options
                    ) do
                  {:ok, config} -> ChartService.generate_chart_url(config)
                  {:error, reason} -> {:error, reason}
                end
                
              _ ->
                Logger.error("Failed to parse value or activity data for total value chart")
                {:error, "Failed to parse value or activity data"}
            end
          else
            Logger.error("Required charts not found for total value chart")
            {:error, "Required charts not found for total value chart"}
          end
        else
          Logger.error("Expected TimeFrames data structure not found")
          {:error, "Expected TimeFrames data structure not found"}
        end

      {:loading, _} ->
        {:error, "TPS data is still loading"}

      {:error, reason} ->
        {:error, reason}
    end
  end
  
  # Helper functions

  defp extract_character_performance_data(data) do
    # Log the structure for debugging
    Logger.info("DATA STRUCTURE: #{inspect(data, limit: 1000)}")
    
    # Only handle the exact format from the TimeFrames structure as in log.txt
    if is_map(data) && is_list(data["TimeFrames"]) && length(data["TimeFrames"]) > 0 do
      time_frame = Enum.at(data["TimeFrames"], 0, %{})
      charts = Map.get(time_frame, "Charts", [])
      
      # Find Character Damage chart by ID
      damage_chart = Enum.find(charts, fn chart -> 
        id = Map.get(chart, "ID", "")
        String.contains?(id, "characterDamageAndFinalBlowsChart")
      end)
      
      if damage_chart do
        Logger.info("Found Character Damage chart: #{Map.get(damage_chart, "Name", "unknown")}")
        # Parse JSON data string
        chart_data = Map.get(damage_chart, "Data", "[]")
        
        case Jason.decode(chart_data) do
          {:ok, chars} when is_list(chars) ->
            Logger.info("Successfully parsed Character Damage chart data")
            chars
          {:error, error} ->
            Logger.error("Failed to parse Character Damage chart data: #{inspect(error)}")
            []
          _ ->
            Logger.error("Unexpected format in Character Damage chart data")
            []
        end
      else
        Logger.error("Character Damage chart not found in expected TimeFrames structure")
        []
      end
    else
      Logger.error("Expected TimeFrames data structure not found")
      []
    end
  end

  defp extract_character_losses_data(data) do
    # Only handle the exact format from the TimeFrames structure as in log.txt
    if is_map(data) && is_list(data["TimeFrames"]) && length(data["TimeFrames"]) > 0 do
      time_frame = Enum.at(data["TimeFrames"], 0, %{})
      charts = Map.get(time_frame, "Charts", [])
      
      # Find Combined Losses chart by ID
      losses_chart = Enum.find(charts, fn chart -> 
        id = Map.get(chart, "ID", "")
        String.contains?(id, "combinedLossesChart") || 
        String.contains?(Map.get(chart, "Name", ""), "Combined Losses")
      end)
      
      if losses_chart do
        Logger.info("Found Combined Losses chart: #{Map.get(losses_chart, "Name", "unknown")}")
        # Parse JSON data string
        chart_data = Map.get(losses_chart, "Data", "[]")
        
        # Handle "null" string which appears in the log example
        if chart_data == "null" do
          Logger.info("Combined Losses chart data is null")
          []
        else
          case Jason.decode(chart_data) do
            {:ok, losses} when is_list(losses) ->
              Logger.info("Successfully parsed Combined Losses chart data")
              losses
            {:error, error} ->
              Logger.error("Failed to parse Combined Losses chart data: #{inspect(error)}")
              []
            _ ->
              Logger.error("Unexpected format in Combined Losses chart data")
              []
          end
        end
      else
        Logger.error("Combined Losses chart not found in expected TimeFrames structure")
        []
      end
    else
      Logger.error("Expected TimeFrames data structure not found")
      []
    end
  end
end