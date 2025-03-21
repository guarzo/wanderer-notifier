defmodule WandererNotifier.ChartService.ActivityChartAdapter do
  @moduledoc """
  Adapter for generating character activity charts using the ChartService.

  This adapter is focused solely on data preparation, extracting and transforming
  character activity data into chart-ready formats. It delegates rendering and
  delivery to the ChartService module.
  """

  require Logger
  alias WandererNotifier.ChartService
  alias WandererNotifier.ChartService.ChartConfig
  alias WandererNotifier.ChartService.ChartTypes

  @doc """
  Generates a chart URL for character activity summary.
  Returns {:ok, url} on success, {:error, reason} on failure.
  """
  def generate_activity_summary_chart(activity_data) do
    case prepare_activity_summary_data(activity_data) do
      {:ok, chart_data, title, options} ->
        # Create chart configuration using the ChartConfig struct
        case ChartConfig.new(
               ChartTypes.horizontal_bar(),
               chart_data,
               title,
               options
             ) do
          {:ok, config} -> ChartService.generate_chart_url(config)
          {:error, reason} -> {:error, reason}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Prepares chart data for character activity summary.
  Returns {:ok, chart_data, title, options} or {:error, reason}.
  """
  def prepare_activity_summary_data(activity_data) do
    Logger.info("Preparing character activity summary data")

    if activity_data == nil do
      Logger.error("No activity data provided")
      {:error, "No activity data provided"}
    else
      try do
        # Extract character data based on format
        characters =
          cond do
            # If activity_data is already a list of character data
            is_list(activity_data) ->
              activity_data

            # If activity_data is a map with a "data" key that contains a list
            is_map(activity_data) && Map.has_key?(activity_data, "data") &&
                is_list(activity_data["data"]) ->
              activity_data["data"]

            # If activity_data is a map with a "characters" key
            is_map(activity_data) && Map.has_key?(activity_data, "characters") ->
              activity_data["characters"]

            # Return empty list for other formats
            true ->
              Logger.error("Invalid data format - couldn't extract character data")
              []
          end

        if characters && length(characters) > 0 do
          # Sort by total activity (sum of connections, passages, signatures) in descending order and take top 5
          top_characters =
            characters
            |> Enum.sort_by(
              fn char ->
                connections = Map.get(char, "connections", 0)
                passages = Map.get(char, "passages", 0)
                signatures = Map.get(char, "signatures", 0)
                connections + passages + signatures
              end,
              :desc
            )
            |> Enum.take(5)

          Logger.info("Selected top #{length(top_characters)} characters for activity chart")

          # Extract character names for labels
          character_labels =
            Enum.map(top_characters, fn char ->
              character = Map.get(char, "character", %{})
              Map.get(character, "name", "Unknown")
            end)

          # Extract activity data for each metric
          connections_data =
            Enum.map(top_characters, fn char -> Map.get(char, "connections", 0) end)

          passages_data = Enum.map(top_characters, fn char -> Map.get(char, "passages", 0) end)

          signatures_data =
            Enum.map(top_characters, fn char -> Map.get(char, "signatures", 0) end)

          # Define vibrant colors with good contrast
          # Blue
          connection_color = "rgba(54, 162, 235, 0.8)"
          # Red
          passage_color = "rgba(255, 99, 132, 0.8)"
          # Teal
          signature_color = "rgba(75, 192, 192, 0.8)"

          # Create the chart data
          chart_data = %{
            "type" => "horizontalBar",
            "labels" => character_labels,
            "datasets" => [
              %{
                "label" => "Connections",
                "backgroundColor" => connection_color,
                "borderColor" => connection_color,
                "borderWidth" => 1,
                "data" => connections_data
              },
              %{
                "label" => "Passages",
                "backgroundColor" => passage_color,
                "borderColor" => passage_color,
                "borderWidth" => 1,
                "data" => passages_data
              },
              %{
                "label" => "Signatures",
                "backgroundColor" => signature_color,
                "borderColor" => signature_color,
                "borderWidth" => 1,
                "data" => signatures_data
              }
            ]
          }

          # Define options for a horizontal stacked bar chart
          options = %{
            "responsive" => true,
            "maintainAspectRatio" => false,
            "scales" => %{
              "xAxes" => [
                %{
                  "stacked" => true,
                  "gridLines" => %{
                    "color" => "rgba(255, 255, 255, 0.1)"
                  },
                  "ticks" => %{
                    "beginAtZero" => true,
                    "fontColor" => "rgb(255, 255, 255)"
                  },
                  "scaleLabel" => %{
                    "display" => true,
                    "labelString" => "Count",
                    "fontColor" => "rgb(255, 255, 255)"
                  }
                }
              ],
              "yAxes" => [
                %{
                  "stacked" => true,
                  "gridLines" => %{
                    "color" => "rgba(255, 255, 255, 0.1)"
                  },
                  "ticks" => %{
                    "fontColor" => "rgb(255, 255, 255)"
                  },
                  "scaleLabel" => %{
                    "display" => true,
                    "labelString" => "Characters",
                    "fontColor" => "rgb(255, 255, 255)"
                  }
                }
              ]
            },
            "legend" => %{
              "display" => true,
              "position" => "top",
              "labels" => %{
                "fontColor" => "rgb(255, 255, 255)"
              }
            },
            "title" => %{
              "display" => true,
              "text" => "Character Activity Summary",
              "fontColor" => "rgb(255, 255, 255)",
              "fontSize" => 16
            },
            "tooltips" => %{
              "enabled" => true,
              "mode" => "index",
              "intersect" => false
            }
          }

          {:ok, chart_data, "Character Activity Summary", options}
        else
          {:error, "No character data available"}
        end
      rescue
        e ->
          Logger.error("Error preparing activity summary data: #{inspect(e)}")
          {:error, "Error preparing activity summary data: #{inspect(e)}"}
      end
    end
  end

  @doc """
  Generates a chart URL for activity timeline.
  Returns {:ok, url} on success, {:error, reason} on failure.
  """
  def generate_activity_timeline_chart(activity_data) do
    case prepare_activity_timeline_data(activity_data) do
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
        {:error, reason}
    end
  end

  @doc """
  Prepares chart data for activity timeline.
  Returns {:ok, chart_data, title, options} or {:error, reason}.
  """
  def prepare_activity_timeline_data(activity_data) do
    Logger.info("Preparing activity timeline data")

    if activity_data == nil do
      Logger.error("No activity data provided")
      {:error, "No activity data provided"}
    else
      try do
        # Extract timeline data
        timeline =
          cond do
            # If activity_data is a map with a "timeline" key
            is_map(activity_data) && Map.has_key?(activity_data, "timeline") ->
              activity_data["timeline"]

            # Return empty map for other formats
            true ->
              Logger.error("Invalid data format - couldn't extract timeline data")
              %{}
          end

        if is_map(timeline) && map_size(timeline) > 0 do
          # Sort dates chronologically
          sorted_dates =
            timeline
            |> Map.keys()
            |> Enum.sort()

          # Create date labels in a readable format
          date_labels = Enum.map(sorted_dates, &format_date/1)

          # Extract activity metrics for each date
          connections_data =
            Enum.map(sorted_dates, fn date ->
              get_in(timeline, [date, "connections"]) || 0
            end)

          passages_data =
            Enum.map(sorted_dates, fn date ->
              get_in(timeline, [date, "passages"]) || 0
            end)

          signatures_data =
            Enum.map(sorted_dates, fn date ->
              get_in(timeline, [date, "signatures"]) || 0
            end)

          # Define vibrant colors with good contrast
          # Blue
          connection_color = "rgba(54, 162, 235, 0.8)"
          # Red
          passage_color = "rgba(255, 99, 132, 0.8)"
          # Teal
          signature_color = "rgba(75, 192, 192, 0.8)"

          # Create the chart data
          chart_data = %{
            "labels" => date_labels,
            "datasets" => [
              %{
                "label" => "Connections",
                "backgroundColor" => "rgba(54, 162, 235, 0.2)",
                "borderColor" => connection_color,
                "borderWidth" => 2,
                "pointBackgroundColor" => connection_color,
                "pointRadius" => 3,
                "data" => connections_data,
                "fill" => true
              },
              %{
                "label" => "Passages",
                "backgroundColor" => "rgba(255, 99, 132, 0.2)",
                "borderColor" => passage_color,
                "borderWidth" => 2,
                "pointBackgroundColor" => passage_color,
                "pointRadius" => 3,
                "data" => passages_data,
                "fill" => true
              },
              %{
                "label" => "Signatures",
                "backgroundColor" => "rgba(75, 192, 192, 0.2)",
                "borderColor" => signature_color,
                "borderWidth" => 2,
                "pointBackgroundColor" => signature_color,
                "pointRadius" => 3,
                "data" => signatures_data,
                "fill" => true
              }
            ]
          }

          # Define options for a line chart
          options = %{
            "tooltips" => %{
              "mode" => "index",
              "intersect" => false
            },
            "scales" => %{
              "x" => %{
                "title" => %{
                  "display" => true,
                  "text" => "Date"
                }
              },
              "y" => %{
                "beginAtZero" => true,
                "title" => %{
                  "display" => true,
                  "text" => "Count"
                }
              }
            },
            "elements" => %{
              "line" => %{
                "tension" => 0.4
              }
            }
          }

          {:ok, chart_data, "Activity Over Time", options}
        else
          {:error, "No timeline data available"}
        end
      rescue
        e ->
          Logger.error("Error preparing activity timeline data: #{inspect(e)}")
          {:error, "Error preparing activity timeline data: #{inspect(e)}"}
      end
    end
  end

  @doc """
  Generates a chart URL for activity distribution.
  Returns {:ok, url} on success, {:error, reason} on failure.
  """
  def generate_activity_distribution_chart(activity_data) do
    case prepare_activity_distribution_data(activity_data) do
      {:ok, chart_data, title, options} ->
        # Create chart configuration using the ChartConfig struct
        case ChartConfig.new(
               ChartTypes.pie(),
               chart_data,
               title,
               options
             ) do
          {:ok, config} -> ChartService.generate_chart_url(config)
          {:error, reason} -> {:error, reason}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Prepares chart data for activity distribution.
  Returns {:ok, chart_data, title, options} or {:error, reason}.
  """
  def prepare_activity_distribution_data(activity_data) do
    Logger.info("Preparing activity distribution data")

    if activity_data == nil do
      Logger.error("No activity data provided")
      {:error, "No activity data provided"}
    else
      try do
        # Extract totals from the activity data
        totals =
          cond do
            # If activity_data is a map with a "totals" key
            is_map(activity_data) && is_map(activity_data["totals"]) ->
              activity_data["totals"]

            # If activity_data has connections, passages, signatures directly
            is_map(activity_data) &&
              Map.has_key?(activity_data, "connections") &&
              Map.has_key?(activity_data, "passages") &&
                Map.has_key?(activity_data, "signatures") ->
              %{
                "connections" => activity_data["connections"],
                "passages" => activity_data["passages"],
                "signatures" => activity_data["signatures"]
              }

            # Aggregate totals if we have character data
            is_map(activity_data) && is_list(activity_data["characters"]) ->
              characters = activity_data["characters"]

              Enum.reduce(
                characters,
                %{"connections" => 0, "passages" => 0, "signatures" => 0},
                fn char, acc ->
                  %{
                    "connections" => acc["connections"] + Map.get(char, "connections", 0),
                    "passages" => acc["passages"] + Map.get(char, "passages", 0),
                    "signatures" => acc["signatures"] + Map.get(char, "signatures", 0)
                  }
                end
              )

            # Return empty map for other formats
            true ->
              Logger.error("Invalid data format - couldn't extract activity totals")
              %{"connections" => 0, "passages" => 0, "signatures" => 0}
          end

        # Get the activity values
        connections = Map.get(totals, "connections", 0)
        passages = Map.get(totals, "passages", 0)
        signatures = Map.get(totals, "signatures", 0)

        total_activities = connections + passages + signatures

        if total_activities > 0 do
          # Create chart data
          chart_data = %{
            "labels" => ["Connections", "Passages", "Signatures"],
            "datasets" => [
              %{
                "data" => [connections, passages, signatures],
                "backgroundColor" => [
                  # Blue
                  "rgba(54, 162, 235, 0.8)",
                  # Red
                  "rgba(255, 99, 132, 0.8)",
                  # Teal
                  "rgba(75, 192, 192, 0.8)"
                ],
                "borderColor" => [
                  "rgba(54, 162, 235, 1)",
                  "rgba(255, 99, 132, 1)",
                  "rgba(75, 192, 192, 1)"
                ],
                "borderWidth" => 1
              }
            ]
          }

          # Define options for a pie chart
          options = %{
            "plugins" => %{
              "legend" => %{
                "position" => "right"
              },
              "tooltip" => %{
                "callbacks" => %{
                  "label" =>
                    "function(context) { return context.label + ': ' + context.formattedValue + ' (' + Math.round(context.raw / " <>
                      Integer.to_string(total_activities) <> " * 100) + '%)'; }"
                }
              }
            }
          }

          {:ok, chart_data, "Activity Distribution", options}
        else
          {:error, "No activity data available"}
        end
      rescue
        e ->
          Logger.error("Error preparing activity distribution data: #{inspect(e)}")
          {:error, "Error preparing activity distribution data: #{inspect(e)}"}
      end
    end
  end

  @doc """
  Sends a chart to Discord as an embed.

  ## Parameters
    - activity_data: The activity data to use for chart generation
    - title: The title for the Discord embed
    - chart_type: The type of chart to generate and send (optional, defaults to "activity_summary")
    - description: The description for the Discord embed (optional)
    - channel_id: The Discord channel ID (optional)

  ## Returns
    - {:ok, response} on success
    - {:error, reason} on failure
  """
  def send_chart_to_discord(
        activity_data,
        title,
        chart_type \\ "activity_summary",
        description \\ nil,
        channel_id \\ nil
      ) do
    # Support both the old format (activity_data, title) and new format (activity_data, chart_type, title)
    {actual_chart_type, actual_title, actual_description} =
      cond do
        # If activity_data is a string, it's likely the old chart_type, title format
        is_binary(activity_data) ->
          {activity_data, title, chart_type}

        # Otherwise, use the new format
        true ->
          {chart_type, title, description}
      end

    # Generate the chart URL based on the chart type
    chart_result =
      case actual_chart_type do
        "activity_summary" ->
          generate_activity_summary_chart(activity_data)

        "activity_timeline" ->
          generate_activity_timeline_chart(activity_data)

        "activity_distribution" ->
          generate_activity_distribution_chart(activity_data)

        _ ->
          {:error, "Unsupported chart type: #{actual_chart_type}"}
      end

    # Send the chart to Discord using the ChartService
    case chart_result do
      {:ok, url} ->
        # Use provided title or default based on chart type
        embed_title =
          cond do
            actual_title != nil -> actual_title
            actual_chart_type == "activity_summary" -> "Character Activity Summary"
            actual_chart_type == "activity_timeline" -> "Activity Over Time"
            actual_chart_type == "activity_distribution" -> "Activity Distribution"
            true -> "EVE Online Character Activity"
          end

        # Create a more informative description
        enhanced_description =
          if actual_description do
            actual_description
          else
            case actual_chart_type do
              "activity_summary" ->
                "Top characters by connections, passages, and signatures in the last 24 hours"

              "activity_timeline" ->
                "Character activity trends over time"

              "activity_distribution" ->
                "Distribution of character activity by type"

              _ ->
                "Character activity in EVE Online"
            end
          end

        # Send the embed with the chart and convert response format
        case ChartService.send_chart_to_discord(
               url,
               embed_title,
               enhanced_description,
               channel_id
             ) do
          :ok ->
            # Return standardized format with URL and title for caller
            {:ok, url, embed_title}

          {:ok, _response} ->
            # Forward response format
            {:ok, url, embed_title}

          {:error, reason} ->
            # Forward error
            {:error, reason}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Sends all available activity charts to Discord.

  ## Parameters
    - activity_data: The activity data to use for chart generation
    - channel_id: The Discord channel ID (optional)

  ## Returns
    - A map of chart types to results
  """
  def send_all_charts_to_discord(activity_data, channel_id \\ nil) do
    # Use provided channel ID or determine the appropriate channel with fallbacks
    actual_channel_id =
      if is_nil(channel_id) do
        WandererNotifier.Core.Config.discord_channel_id_for_activity_charts()
      else
        channel_id
      end

    Logger.info("Sending activity charts to Discord channel: #{actual_channel_id}")

    # Chart types and their descriptions
    charts = [
      {"activity_summary", "Character Activity Summary",
       "Top characters by connections, passages, and signatures in the last 24 hours.\nData is refreshed daily."}
      # Timeline and distribution charts removed
    ]

    # Send each chart and collect results
    Enum.reduce(charts, %{}, fn {chart_type, title, description}, results ->
      result =
        send_chart_to_discord(activity_data, title, chart_type, description, actual_channel_id)

      Map.put(results, chart_type, result)
    end)
  end

  # Helper functions

  # Formats a date string (e.g., "2023-01-15") to a more readable format (e.g., "Jan 15, 2023")
  defp format_date(date_str) when is_binary(date_str) do
    case String.split(date_str, "-") do
      [year, month, day] ->
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

        # Remove leading zero from day
        day_num = String.to_integer(day)
        "#{month_name} #{day_num}, #{year}"

      _ ->
        date_str
    end
  end

  defp format_date(other), do: inspect(other)
end
