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
        characters = extract_character_data(activity_data)

        if characters && length(characters) > 0 do
          # Get top characters by activity
          top_characters = get_top_characters(characters, 5)
          Logger.info("Selected top #{length(top_characters)} characters for activity chart")

          # Extract chart elements
          character_labels = extract_character_labels(top_characters)

          {connections_data, passages_data, signatures_data} =
            extract_activity_metrics(top_characters)

          # Create chart data structure
          chart_data =
            create_summary_chart_data(
              character_labels,
              connections_data,
              passages_data,
              signatures_data
            )

          options = create_summary_chart_options()

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

  # Extracts character data from various formats
  defp extract_character_data(activity_data) do
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
  end

  # Gets top N characters sorted by total activity
  defp get_top_characters(characters, limit) do
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
    |> Enum.take(limit)
  end

  # Extracts character names for labels
  defp extract_character_labels(characters) do
    Enum.map(characters, fn char ->
      character = Map.get(char, "character", %{})
      Map.get(character, "name", "Unknown")
    end)
  end

  # Extracts activity metrics for each character
  defp extract_activity_metrics(characters) do
    connections_data = Enum.map(characters, fn char -> Map.get(char, "connections", 0) end)
    passages_data = Enum.map(characters, fn char -> Map.get(char, "passages", 0) end)
    signatures_data = Enum.map(characters, fn char -> Map.get(char, "signatures", 0) end)

    {connections_data, passages_data, signatures_data}
  end

  # Creates chart data structure for summary chart
  defp create_summary_chart_data(labels, connections_data, passages_data, signatures_data) do
    # Define vibrant colors with good contrast
    {connection_color, passage_color, signature_color} = get_chart_colors()

    # Create the chart data
    %{
      "type" => "horizontalBar",
      "labels" => labels,
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
  end

  # Creates options for summary chart
  defp create_summary_chart_options do
    %{
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
        timeline = extract_timeline_data(activity_data)

        if is_map(timeline) && map_size(timeline) > 0 do
          create_timeline_chart_data(timeline)
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

  # Extracts timeline data from the activity data
  defp extract_timeline_data(activity_data) do
    if is_map(activity_data) && Map.has_key?(activity_data, "timeline") do
      activity_data["timeline"]
    else
      Logger.error("Invalid data format - couldn't extract timeline data")
      %{}
    end
  end

  # Creates chart data for activity timeline
  defp create_timeline_chart_data(timeline) do
    # Sort dates chronologically
    sorted_dates =
      timeline
      |> Map.keys()
      |> Enum.sort()

    # Create date labels in a readable format
    date_labels = Enum.map(sorted_dates, &format_date/1)

    # Extract activity metrics for each date
    {connections_data, passages_data, signatures_data} =
      extract_timeline_metrics(timeline, sorted_dates)

    # Define chart colors
    {connection_color, passage_color, signature_color} = get_chart_colors()

    # Create the chart data structure
    chart_data = %{
      "labels" => date_labels,
      "datasets" => [
        create_dataset("Connections", connection_color, connections_data),
        create_dataset("Passages", passage_color, passages_data),
        create_dataset("Signatures", signature_color, signatures_data)
      ]
    }

    # Create chart options
    options = create_timeline_chart_options()

    {:ok, chart_data, "Activity Timeline", options}
  end

  # Extracts metrics from timeline for each date
  defp extract_timeline_metrics(timeline, sorted_dates) do
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

    {connections_data, passages_data, signatures_data}
  end

  # Returns standard colors for chart elements
  defp get_chart_colors do
    # Blue
    connection_color = "rgba(54, 162, 235, 0.8)"
    # Red
    passage_color = "rgba(255, 99, 132, 0.8)"
    # Teal
    signature_color = "rgba(75, 192, 192, 0.8)"

    {connection_color, passage_color, signature_color}
  end

  # Creates a dataset for the timeline chart
  defp create_dataset(label, color, data) do
    %{
      "label" => label,
      "backgroundColor" => "#{color}2",
      "borderColor" => color,
      "borderWidth" => 2,
      "pointBackgroundColor" => color,
      "pointRadius" => 3,
      "data" => data,
      "fill" => true
    }
  end

  # Creates options for the timeline chart
  defp create_timeline_chart_options do
    %{
      "responsive" => true,
      "maintainAspectRatio" => false,
      "scales" => %{
        "xAxes" => [
          %{
            "gridLines" => %{
              "color" => "rgba(255, 255, 255, 0.1)"
            },
            "ticks" => %{
              "fontColor" => "rgb(255, 255, 255)"
            },
            "scaleLabel" => %{
              "display" => true,
              "labelString" => "Date",
              "fontColor" => "rgb(255, 255, 255)"
            }
          }
        ],
        "yAxes" => [
          %{
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
        "text" => "Activity Timeline",
        "fontColor" => "rgb(255, 255, 255)",
        "fontSize" => 16
      },
      "tooltips" => %{
        "mode" => "index",
        "intersect" => false
      }
    }
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
        totals = extract_activity_totals(activity_data)

        # Get the activity values
        connections = Map.get(totals, "connections", 0)
        passages = Map.get(totals, "passages", 0)
        signatures = Map.get(totals, "signatures", 0)

        total_activities = connections + passages + signatures

        if total_activities > 0 do
          create_distribution_chart_data(connections, passages, signatures)
        else
          {:error, "No activity data to display"}
        end
      rescue
        e ->
          Logger.error("Error preparing activity distribution data: #{inspect(e)}")
          {:error, "Error preparing activity distribution data: #{inspect(e)}"}
      end
    end
  end

  # Extracts totals from various activity data formats
  defp extract_activity_totals(activity_data) do
    # First check if we have totals directly
    if is_map(activity_data) && Map.has_key?(activity_data, "totals") do
      activity_data["totals"]
    else
      extract_activity_totals_from_alternative_formats(activity_data)
    end
  end

  # Handles alternative activity data formats
  defp extract_activity_totals_from_alternative_formats(activity_data) do
    # Check for direct metrics
    has_direct_metrics =
      is_map(activity_data) &&
        Map.has_key?(activity_data, "connections") &&
        Map.has_key?(activity_data, "passages") &&
        Map.has_key?(activity_data, "signatures")

    cond do
      has_direct_metrics ->
        # Extract direct metrics
        %{
          "connections" => activity_data["connections"],
          "passages" => activity_data["passages"],
          "signatures" => activity_data["signatures"]
        }

      # Check for character data to aggregate
      is_map(activity_data) && is_list(activity_data["characters"]) ->
        aggregate_character_activities(activity_data["characters"])

      # Fallback to empty data
      true ->
        Logger.error("Invalid data format - couldn't extract activity totals")
        %{"connections" => 0, "passages" => 0, "signatures" => 0}
    end
  end

  # Aggregates activities across multiple characters
  defp aggregate_character_activities(characters) do
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
  end

  # Creates chart data for activity distribution
  defp create_distribution_chart_data(connections, passages, signatures) do
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

    # Create options with responsive design and proper colors
    options = %{
      "responsive" => true,
      "maintainAspectRatio" => false,
      "plugins" => %{
        "legend" => %{
          "position" => "right",
          "labels" => %{
            "fontColor" => "rgb(255, 255, 255)"
          }
        },
        "title" => %{
          "display" => true,
          "text" => "Activity Distribution",
          "fontColor" => "rgb(255, 255, 255)"
        },
        "tooltip" => %{
          "enabled" => true
        }
      }
    }

    {:ok, chart_data, "Activity Distribution", options}
  end

  @doc """
  Sends a chart to Discord based on the provided activity data.

  ## Parameters
    - activity_data: The activity data for the chart
    - title: The title for the chart or embed
    - chart_type: The type of chart to generate ("activity_summary", "activity_timeline", or "activity_distribution")
    - description: Optional description for the Discord embed
    - channel_id: Optional Discord channel ID to send the chart to

  ## Returns
    - {:ok, message_id} if successful
    - {:error, reason} if something fails
  """
  def send_chart_to_discord(
        activity_data,
        title,
        chart_type \\ "activity_summary",
        description \\ nil,
        channel_id \\ nil
      ) do
    # Determine actual parameters based on input format
    {actual_chart_type, actual_title, actual_description} =
      resolve_chart_parameters(activity_data, title, chart_type, description)

    # Generate the chart URL based on the chart type
    chart_result = generate_chart_by_type(actual_chart_type, activity_data)

    # Send the chart to Discord using the ChartService
    case chart_result do
      {:ok, url} ->
        # Build embed parameters
        embed_title = resolve_embed_title(actual_title, actual_chart_type)
        enhanced_description = resolve_embed_description(actual_description, actual_chart_type)

        # Send the embed with the chart and convert response format
        ChartService.send_chart_to_discord(
          url,
          embed_title,
          enhanced_description,
          channel_id
        )

      {:error, reason} ->
        Logger.error("Failed to generate chart: #{inspect(reason)}")
        {:error, reason}
    end
  end

  # Resolves input parameters to determine actual chart type, title, and description
  defp resolve_chart_parameters(activity_data, title, chart_type, description) do
    if is_binary(activity_data) do
      # If activity_data is a string, it's likely the old chart_type, title format
      {activity_data, title, chart_type}
    else
      # Otherwise, use the new format
      {chart_type, title, description}
    end
  end

  # Generates chart based on the specified type
  defp generate_chart_by_type(chart_type, activity_data) do
    case chart_type do
      "activity_summary" ->
        generate_activity_summary_chart(activity_data)

      "activity_timeline" ->
        generate_activity_timeline_chart(activity_data)

      "activity_distribution" ->
        generate_activity_distribution_chart(activity_data)

      _ ->
        {:error, "Unsupported chart type: #{chart_type}"}
    end
  end

  # Resolves the embed title based on provided title and chart type
  defp resolve_embed_title(nil, chart_type) do
    case chart_type do
      "activity_summary" -> "Character Activity Summary"
      "activity_timeline" -> "Activity Over Time"
      "activity_distribution" -> "Activity Distribution"
      _ -> "EVE Online Character Activity"
    end
  end

  defp resolve_embed_title(title, _), do: title

  # Resolves the embed description based on provided description and chart type
  defp resolve_embed_description(nil, chart_type) do
    case chart_type do
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

  defp resolve_embed_description(description, _), do: description

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

  # Formats a date string into a more human-readable format
  defp format_date(date_str) when is_binary(date_str) do
    case String.split(date_str, "-") do
      [year, month, day] ->
        month_name = get_month_name(month)

        # Remove leading zero from day
        day_num = String.to_integer(day)
        "#{month_name} #{day_num}, #{year}"

      _ ->
        date_str
    end
  end

  defp format_date(other), do: inspect(other)

  # Returns month name from month number
  defp get_month_name(month) do
    month_names = %{
      "01" => "Jan",
      "02" => "Feb",
      "03" => "Mar",
      "04" => "Apr",
      "05" => "May",
      "06" => "Jun",
      "07" => "Jul",
      "08" => "Aug",
      "09" => "Sep",
      "10" => "Oct",
      "11" => "Nov",
      "12" => "Dec"
    }

    Map.get(month_names, month, month)
  end
end
