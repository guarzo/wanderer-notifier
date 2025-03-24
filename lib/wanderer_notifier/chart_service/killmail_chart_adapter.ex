defmodule WandererNotifier.ChartService.KillmailChartAdapter do
  @moduledoc """
  Adapter for generating killmail charts using the ChartService.

  This adapter is focused on preparing killmail data for charting,
  such as top character kills, kill statistics, and other killmail-related visualizations.
  """

  require Logger
  require Ash.Query
  alias WandererNotifier.Logger, as: AppLogger
  alias WandererNotifier.ChartService
  alias WandererNotifier.Resources.KillmailStatistic
  alias WandererNotifier.Resources.TrackedCharacter
  alias Ash.Query

  @doc """
  Generates a chart showing the top characters by kills for the past week.

  ## Parameters
    - options: Map of options including:
      - limit: Maximum number of characters to include (default: 20)
      or directly an integer representing the limit

  ## Returns
    - {:ok, chart_url} if successful
    - {:error, reason} if chart generation fails
  """
  def generate_weekly_kills_chart(options \\ %{}) do
    # Extract limit from options
    limit = extract_limit_from_options(options)
    AppLogger.kill_info("Generating weekly kills chart", limit: limit)

    # Prepare chart data
    case prepare_weekly_kills_data(limit) do
      {:ok, chart_data, title, chart_options} ->
        generate_chart_from_data(chart_data, title, chart_options)
    end
  end

  # Helper to extract limit from options
  defp extract_limit_from_options(options) do
    case options do
      limit when is_integer(limit) -> limit
      %{} = opts -> Map.get(opts, :limit, 20)
      _ -> 20
    end
  end

  # Helper to generate chart from prepared data
  defp generate_chart_from_data(chart_data, title, chart_options) do
    # Check if we have meaningful data
    if has_meaningful_data?(chart_data) do
      generate_real_chart(chart_data, title, chart_options)
    else
      # Use a fixed error URL for empty data
      generate_empty_chart()
    end
  end

  # Check if chart data has meaningful content
  defp has_meaningful_data?(chart_data) do
    labels = Map.get(chart_data, "labels", [])
    length(labels) > 1 || (length(labels) == 1 && hd(labels) != "No Data")
  end

  # Generate a chart with real data
  defp generate_real_chart(chart_data, title, chart_options) do
    # Create chart configuration
    chart_config = %{
      type: chart_data["type"] || "horizontalBar",
      data: chart_data,
      title: title,
      options: chart_options
    }

    # Generate URL from the config
    ChartService.generate_chart_url(chart_config)
  end

  # Generate an empty chart with error message
  defp generate_empty_chart do
    {:ok,
     "https://quickchart.io/chart?c={type:%27bar%27,data:{labels:[%27No%20Data%27],datasets:[{label:%27No%20weekly%20kill%20statistics%20available%27,data:[0]}]}}&bkg=rgb(47,49,54)&width=800&height=400"}
  end

  @doc """
  Prepares chart data for the weekly kills chart.
  Returns {:ok, chart_data, title, options} or {:error, reason}.
  """
  def prepare_weekly_kills_data(limit) do
    AppLogger.kill_info("Preparing weekly kills chart data")

    try do
      # Get tracked characters
      tracked_characters = get_tracked_characters()

      # Get weekly statistics for these characters
      weekly_stats = get_weekly_stats(tracked_characters)

      if length(weekly_stats) > 0 do
        # Get top characters by kills
        top_characters = get_top_characters_by_kills(weekly_stats, limit)

        AppLogger.kill_info("Selected top characters for weekly kills chart",
          count: length(top_characters)
        )

        # Extract chart elements
        {character_labels, kills_data, isk_destroyed_data} = extract_kill_metrics(top_characters)

        # Create chart data structure
        chart_data =
          create_weekly_kills_chart_data(character_labels, kills_data, isk_destroyed_data)

        options = create_weekly_kills_chart_options()

        {:ok, chart_data, "Weekly Character Kills", options}
      else
        AppLogger.kill_warn("No weekly statistics available for tracked characters")

        # Create an empty chart with a message instead of returning an error
        empty_chart_data = create_empty_chart_data("No kill statistics available yet")
        options = create_empty_chart_options()

        {:ok, empty_chart_data, "Weekly Character Kills", options}
      end
    rescue
      e ->
        AppLogger.kill_error("Error preparing weekly kills data",
          error: Exception.message(e),
          stacktrace: Exception.format_stacktrace(__STACKTRACE__)
        )

        # Even for errors, create an empty chart with an error message
        empty_chart_data = create_empty_chart_data("Error loading chart data")
        options = create_empty_chart_options()

        {:ok, empty_chart_data, "Weekly Character Kills", options}
    end
  end

  @doc """
  Sends a weekly killmail chart to Discord.

  ## Parameters
    - title: The title for the chart embed (optional)
    - description: Optional description for the Discord embed
    - channel_id: Optional Discord channel ID to send the chart to
    - limit: Maximum number of characters to display (default 20)

  ## Returns
    - {:ok, message_id} if successful
    - {:error, reason} if something fails
  """
  def send_weekly_kills_chart_to_discord(
        title \\ "Weekly Character Kills",
        description \\ nil,
        channel_id \\ nil,
        limit \\ 20
      ) do
    # Determine actual description if not provided
    actual_description = description || "Top #{limit} characters by kills in the past week"

    # Generate the chart URL
    case generate_weekly_kills_chart(limit) do
      {:ok, url} ->
        # Send chart to Discord
        ChartService.send_chart_to_discord(
          url,
          title,
          actual_description,
          channel_id
        )

      {:error, reason} ->
        AppLogger.kill_error("Failed to generate weekly kills chart", error: inspect(reason))
        {:error, reason}
    end
  end

  # Helper functions

  # Get all tracked characters
  defp get_tracked_characters do
    case TrackedCharacter
         |> Query.load([:character_id, :character_name])
         |> WandererNotifier.Resources.Api.read() do
      {:ok, characters} ->
        characters

      {:error, error} ->
        AppLogger.kill_error("Error fetching tracked characters", error: inspect(error))
        []

      _ ->
        []
    end
  end

  # Get weekly statistics for tracked characters
  defp get_weekly_stats(tracked_characters) do
    # Get character IDs
    character_ids = Enum.map(tracked_characters, & &1.character_id)

    # Get the current date and calculate the most recent week start
    today = Date.utc_today()
    days_since_monday = Date.day_of_week(today) - 1
    week_start = Date.add(today, -days_since_monday)

    # Query for weekly stats for these characters - using proper Ash.Query filter syntax
    case KillmailStatistic
         |> Query.filter(character_id: [in: character_ids])
         |> Query.filter(period_type: :weekly)
         |> Query.filter(period_start: week_start)
         |> Query.load([
           :character_id,
           :character_name,
           :kills_count,
           :deaths_count,
           :isk_destroyed,
           :isk_lost,
           :period_start,
           :period_end
         ])
         |> WandererNotifier.Resources.Api.read() do
      {:ok, stats} ->
        stats

      {:error, error} ->
        AppLogger.kill_error("Error fetching weekly stats", error: inspect(error))
        []

      _ ->
        []
    end
  end

  # Gets top N characters sorted by kill count
  defp get_top_characters_by_kills(stats, limit) do
    stats
    |> Enum.sort_by(fn stat -> stat.kills_count end, :desc)
    |> Enum.take(limit)
  end

  # Extracts chart metrics from statistics
  defp extract_kill_metrics(stats) do
    character_labels = Enum.map(stats, fn stat -> stat.character_name end)
    kills_data = Enum.map(stats, fn stat -> stat.kills_count end)

    # Convert Decimal to float for charting
    isk_destroyed_data =
      Enum.map(stats, fn stat ->
        case stat.isk_destroyed do
          nil ->
            0.0

          decimal ->
            # Safely convert to float, handling potential errors
            try do
              Decimal.to_float(decimal) / 1_000_000.0
            rescue
              _ -> 0.0
            end
        end
      end)

    {character_labels, kills_data, isk_destroyed_data}
  end

  # Creates chart data structure for the weekly kills chart
  defp create_weekly_kills_chart_data(labels, kills_data, isk_destroyed_data) do
    # Define colors
    # Red for kills
    kill_color = "rgba(255, 99, 132, 0.8)"
    # Blue for ISK
    isk_color = "rgba(54, 162, 235, 0.8)"

    # Create the chart data
    %{
      "type" => "horizontalBar",
      "labels" => labels,
      "datasets" => [
        %{
          "label" => "Kills",
          "backgroundColor" => kill_color,
          "borderColor" => kill_color,
          "borderWidth" => 1,
          "data" => kills_data,
          "yAxisID" => "kills"
        },
        %{
          "label" => "ISK Destroyed (Millions)",
          "backgroundColor" => isk_color,
          "borderColor" => isk_color,
          "borderWidth" => 1,
          "data" => isk_destroyed_data,
          "yAxisID" => "isk"
        }
      ]
    }
  end

  # Creates options for the weekly kills chart
  defp create_weekly_kills_chart_options do
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
              "beginAtZero" => true,
              "fontColor" => "rgb(255, 255, 255)"
            }
          }
        ],
        "yAxes" => [
          %{
            "id" => "kills",
            "position" => "left",
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
          },
          %{
            "id" => "isk",
            "position" => "right",
            "gridLines" => %{
              "display" => false
            },
            "ticks" => %{
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
        "text" => "Weekly Character Kills",
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

  defp create_empty_chart_data(message) do
    %{
      "type" => "horizontalBar",
      "labels" => ["No Data"],
      "datasets" => [
        %{
          "label" => "Kills",
          "backgroundColor" => "rgba(255, 99, 132, 0.2)",
          "borderColor" => "rgba(255, 99, 132, 0.2)",
          "borderWidth" => 1,
          "data" => [0],
          "yAxisID" => "kills"
        },
        %{
          "label" => "ISK Destroyed (Millions)",
          "backgroundColor" => "rgba(54, 162, 235, 0.2)",
          "borderColor" => "rgba(54, 162, 235, 0.2)",
          "borderWidth" => 1,
          "data" => [0],
          "yAxisID" => "isk"
        }
      ],
      "options" => %{
        "plugins" => %{
          "annotation" => %{
            "annotations" => [
              %{
                "type" => "label",
                "content" => message,
                "font" => %{
                  "size" => 24,
                  "weight" => "bold",
                  "color" => "rgba(255, 255, 255, 0.8)"
                },
                "position" => %{
                  "x" => "50%",
                  "y" => "50%"
                }
              }
            ]
          }
        }
      }
    }
  end

  # Creates options for the weekly kills chart when there's no data available
  defp create_empty_chart_options do
    base_options = create_weekly_kills_chart_options()

    Map.put(base_options, "plugins", %{
      "datalabels" => %{
        "display" => false
      },
      "title" => %{
        "display" => true,
        "text" => "No Killmail Data Available",
        "fontColor" => "rgb(255, 255, 255)",
        "fontSize" => 16
      }
    })
  end
end
