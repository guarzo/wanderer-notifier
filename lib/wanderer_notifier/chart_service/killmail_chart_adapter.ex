defmodule WandererNotifier.ChartService.KillmailChartAdapter do
  @moduledoc """
  Adapter for generating killmail charts using the ChartService.

  This adapter is focused on preparing killmail data for charting,
  such as top character kills, kill statistics, and other killmail-related visualizations.
  """

  require Logger
  require Ash.Query
  alias WandererNotifier.ChartService
  alias WandererNotifier.ChartService.ChartConfig
  alias WandererNotifier.ChartService.ChartTypes
  alias WandererNotifier.Resources.KillmailStatistic
  alias WandererNotifier.Resources.TrackedCharacter
  alias Ash.Query

  @doc """
  Generates a chart showing top characters by kills for the past week.
  Returns {:ok, url} on success, {:error, reason} on failure.
  """
  def generate_weekly_kills_chart(limit \\ 20) do
    case prepare_weekly_kills_data(limit) do
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
  Prepares chart data for the weekly kills chart.
  Returns {:ok, chart_data, title, options} or {:error, reason}.
  """
  def prepare_weekly_kills_data(limit) do
    Logger.info("Preparing weekly kills chart data")

    try do
      # Get tracked characters
      tracked_characters = get_tracked_characters()

      # Get weekly statistics for these characters
      weekly_stats = get_weekly_stats(tracked_characters)

      if length(weekly_stats) > 0 do
        # Get top characters by kills
        top_characters = get_top_characters_by_kills(weekly_stats, limit)
        Logger.info("Selected top #{length(top_characters)} characters for weekly kills chart")

        # Extract chart elements
        {character_labels, kills_data, isk_destroyed_data} = extract_kill_metrics(top_characters)

        # Create chart data structure
        chart_data =
          create_weekly_kills_chart_data(character_labels, kills_data, isk_destroyed_data)

        options = create_weekly_kills_chart_options()

        {:ok, chart_data, "Weekly Character Kills", options}
      else
        Logger.warning("No weekly statistics available for tracked characters", [])
        {:error, "No weekly statistics available"}
      end
    rescue
      e ->
        Logger.error("Error preparing weekly kills data: #{Exception.message(e)}")
        Logger.error(Exception.format_stacktrace())
        {:error, "Error preparing weekly kills data: #{Exception.message(e)}"}
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
        Logger.error("Failed to generate weekly kills chart: #{inspect(reason)}")
        {:error, reason}
    end
  end

  # Helper functions

  # Get all tracked characters
  defp get_tracked_characters do
    TrackedCharacter
    |> Query.load([:character_id, :character_name])
    |> WandererNotifier.Resources.Api.read()
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
    KillmailStatistic
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
    |> WandererNotifier.Resources.Api.read()
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
        Decimal.to_float(stat.isk_destroyed) / 1_000_000.0
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
end
