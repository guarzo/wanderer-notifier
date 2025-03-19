defmodule WandererNotifier.ChartService.JSChartAdapter do
  @moduledoc """
  Adapter for JavaScript-style chart generation using the new ChartService.

  This adapter provides compatibility with the old JSChartAdapter interface
  while using the new ChartService internally. It's used for transitioning
  from the old architecture to the new one.
  """

  require Logger
  alias WandererNotifier.ChartService
  alias WandererNotifier.ChartService.ChartConfig
  alias WandererNotifier.ChartService.ChartTypes
  alias WandererNotifier.CorpTools.CorpToolsClient

  @doc """
  Generates a chart for the specified chart type.
  Compatible with the interface of the old JSChartAdapter.

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

      _ ->
        {:error, "Unsupported chart type: #{inspect(chart_type)}"}
    end
  end

  @doc """
  Sends a chart to Discord.
  Compatible with the interface of the old JSChartAdapter.

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

  # Private helpers

  defp prepare_damage_final_blows_chart do
    Logger.info("Preparing damage and final blows chart")

    case CorpToolsClient.get_recent_tps_data() do
      {:ok, data} ->
        # Extract character performance data
        character_performance_data = extract_character_performance_data(data)

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
          Logger.warning("No character performance data available")

          create_fallback_chart(
            "Damage and Final Blows",
            "No character performance data available"
          )
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
        # Extract character losses data
        character_losses_data = extract_character_losses_data(data)

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
          Logger.warning("No character losses data available")
          create_fallback_chart("Combined Losses", "No character losses data available")
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
        # Extract kills by month data
        kills_by_month = get_in(data, ["Last12MonthsData", "KillsByMonth"])

        if is_map(kills_by_month) and map_size(kills_by_month) > 0 do
          # Sort by month chronologically
          sorted_data =
            kills_by_month
            |> Enum.sort_by(fn {month, _} -> month end)

          # Extract labels and data
          {labels, values} = Enum.unzip(sorted_data)

          # Format month labels
          formatted_labels = Enum.map(labels, &format_month_label/1)

          # Create chart data
          chart_data = %{
            "labels" => formatted_labels,
            "datasets" => [
              %{
                "label" => "Kill Activity",
                "data" => values,
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
                 chart_data,
                 "Kill Activity Over Time"
               ) do
            {:ok, config} -> ChartService.generate_chart_url(config)
            {:error, reason} -> {:error, reason}
          end
        else
          Logger.warning("No kill activity data available")
          create_fallback_chart("Kill Activity", "No kill activity data available")
        end

      {:loading, _} ->
        {:error, "TPS data is still loading"}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp create_fallback_chart(title, message) do
    Logger.info("Creating fallback chart for: #{title} - #{message}")

    ChartService.create_no_data_chart(title, message)
  end

  # Helper functions

  defp extract_character_performance_data(data) do
    # Try to extract from different possible locations in the data structure
    character_data =
      cond do
        # Try to get from Last12MonthsData.CharacterPerformance
        is_map(data) && is_map(data["Last12MonthsData"]) &&
            is_map(data["Last12MonthsData"]["CharacterPerformance"]) ->
          data["Last12MonthsData"]["CharacterPerformance"]
          |> Enum.map(fn {name, perf} ->
            %{"Name" => name, "DamageDone" => perf, "FinalBlows" => 0}
          end)

        # Try to get from CharacterPerformance directly
        is_map(data) && is_map(data["CharacterPerformance"]) ->
          data["CharacterPerformance"]
          |> Enum.map(fn {name, perf} ->
            %{"Name" => name, "DamageDone" => perf, "FinalBlows" => 0}
          end)

        # If character data is already a list, use it directly
        is_map(data) && is_list(data["CharacterData"]) ->
          data["CharacterData"]

        # Return empty list if no data found
        true ->
          []
      end

    Logger.debug("Extracted #{length(character_data)} character performance records")
    character_data
  end

  defp extract_character_losses_data(data) do
    # Try to extract from different possible locations in the data structure
    losses_data =
      cond do
        # Try to get from Last12MonthsData.CharacterLosses
        is_map(data) && is_map(data["Last12MonthsData"]) &&
            is_list(data["Last12MonthsData"]["CharacterLosses"]) ->
          data["Last12MonthsData"]["CharacterLosses"]

        # Try to get from CharacterLosses directly
        is_map(data) && is_list(data["CharacterLosses"]) ->
          data["CharacterLosses"]

        # Return empty list if no data found
        true ->
          []
      end

    Logger.debug("Extracted #{length(losses_data)} character losses records")
    losses_data
  end

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
