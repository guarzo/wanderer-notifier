defmodule WandererNotifier.ChartService.KillmailChartAdapter do
  @moduledoc """
  Adapter for generating killmail charts using the ChartService.

  This adapter is focused on preparing killmail data for charting,
  such as top character kills, kill statistics, and other killmail-related visualizations.
  """

  @behaviour WandererNotifier.ChartService.KillmailChartAdapterBehaviour

  require Ash.Query
  alias Ash.Query

  alias WandererNotifier.ChartService
  alias WandererNotifier.Data.Repo
  alias WandererNotifier.Logger.Logger, as: AppLogger
  alias WandererNotifier.Notifiers.Discord.NeoClient, as: DiscordClient
  alias WandererNotifier.Resources.Api
  alias WandererNotifier.Resources.KillmailStatistic
  alias WandererNotifier.Resources.TrackedCharacter

  @doc """
  Generates a chart showing the top characters by kills for the past week.
  Returns {:ok, chart_url} if successful, {:error, reason} if chart generation fails.
  """
  @impl true
  def generate_weekly_kills_chart do
    # Use default limit of 20 for the weekly kills chart
    case prepare_weekly_kills_data(20) do
      {:ok, chart_data, title, chart_options} ->
        generate_chart_from_data(chart_data, title, chart_options)

      {:error, reason} ->
        AppLogger.kill_error("Failed to prepare weekly kills data", error: inspect(reason))
        {:error, reason}
    end
  rescue
    e ->
      AppLogger.kill_error("Error generating weekly kills chart",
        error: Exception.message(e),
        stacktrace: Exception.format_stacktrace(__STACKTRACE__)
      )

      {:error, "Error generating weekly kills chart: #{Exception.message(e)}"}
  end

  @doc """
  Generates a chart showing only ISK destroyed for tracked characters.
  """
  @impl true
  def generate_weekly_isk_chart(options \\ %{}) do
    limit = extract_limit_from_options(options)
    AppLogger.kill_info("Generating weekly ISK destroyed chart", limit: limit)

    case prepare_weekly_isk_data(limit) do
      {:ok, chart_data, title, chart_options} ->
        generate_chart_from_data(chart_data, title, chart_options)

      {:error, reason} ->
        AppLogger.kill_error("Failed to prepare weekly ISK data", error: inspect(reason))
        generate_empty_chart()
    end
  end

  @doc """
  Generates a killmail validation chart showing zkill API kill counts vs database kill counts
  for each tracked character.

  This chart helps identify discrepancies between kills retrieved from the ZKillboard API
  and what's been successfully stored in the database.

  ## Returns
    - {:ok, image_data} if successful
    - {:error, reason} if chart generation fails
  """
  @impl true
  def generate_kill_validation_chart do
    AppLogger.kill_info("Generating kill validation chart")

    case prepare_kill_validation_data() do
      {:ok, chart_data, title, chart_options} ->
        generate_chart_from_data(chart_data, title, chart_options)

      {:error, reason} ->
        AppLogger.kill_error("Failed to prepare kill validation data", error: inspect(reason))
        generate_empty_chart()
    end
  rescue
    e ->
      AppLogger.kill_error("Error generating kill validation chart",
        error: Exception.message(e),
        stacktrace: Exception.format_stacktrace(__STACKTRACE__)
      )

      {:error, "Error generating kill validation chart: #{Exception.message(e)}"}
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

    # Generate chart using the Node.js service
    ChartService.generate_chart_image(chart_config)
  end

  # Generate an empty chart with error message
  defp generate_empty_chart do
    ChartService.create_no_data_chart(
      "No Killmail Data Available",
      "No weekly kill statistics available"
    )
  end

  @doc """
  Prepares chart data for the weekly kills chart.
  Returns {:ok, chart_data, title, options} or {:error, reason}.
  """
  def prepare_weekly_kills_data(limit) do
    AppLogger.kill_info("Preparing weekly kills chart data")

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
      {character_labels, kills_data, _, solo_kills_data, final_blows_data} =
        extract_kill_metrics(top_characters)

      # Create chart data structure for kills only
      chart_data =
        create_weekly_kills_only_chart_data(
          character_labels,
          kills_data,
          solo_kills_data,
          final_blows_data
        )

      options = create_weekly_kills_chart_options()

      {:ok, chart_data, "Weekly Character Kills", options}
    else
      AppLogger.kill_warn("No weekly statistics available for tracked characters")

      # Create an empty chart with a message instead of returning an error
      empty_chart_data = create_empty_kills_chart_data("No kill statistics available yet")
      options = create_empty_chart_options()

      {:ok, empty_chart_data, "Weekly Character Kills", options}
    end
  rescue
    e ->
      AppLogger.kill_error("Error preparing weekly kills data",
        error: Exception.message(e),
        stacktrace: Exception.format_stacktrace(__STACKTRACE__)
      )

      {:error, "Error preparing weekly kills data: #{Exception.message(e)}"}
  end

  @doc """
  Prepares chart data for the weekly ISK destroyed chart.
  Returns {:ok, chart_data, title, options} or {:error, reason}.
  """
  def prepare_weekly_isk_data(limit) do
    AppLogger.kill_info("Preparing weekly ISK destroyed chart data")

    # Get tracked characters
    tracked_characters = get_tracked_characters()

    # Get weekly statistics for these characters
    weekly_stats = get_weekly_stats(tracked_characters)

    if length(weekly_stats) > 0 do
      # Get top characters by ISK destroyed
      top_characters = get_top_characters_by_isk_destroyed(weekly_stats, limit)

      AppLogger.kill_info("Selected top characters for weekly ISK destroyed chart",
        count: length(top_characters)
      )

      # Extract chart elements
      {character_labels, _, isk_destroyed_data, _, _} = extract_kill_metrics(top_characters)

      # Create chart data structure for ISK only
      chart_data = create_weekly_isk_only_chart_data(character_labels, isk_destroyed_data)
      options = create_weekly_isk_chart_options()

      {:ok, chart_data, "Weekly ISK Destroyed", options}
    else
      AppLogger.kill_warn("No weekly statistics available for tracked characters")

      # Create an empty chart with a message instead of returning an error
      empty_chart_data = create_empty_isk_chart_data("No ISK statistics available yet")
      options = create_empty_chart_options()

      {:ok, empty_chart_data, "Weekly ISK Destroyed", options}
    end
  rescue
    e ->
      AppLogger.kill_error("Error preparing weekly ISK data",
        error: Exception.message(e),
        stacktrace: Exception.format_stacktrace(__STACKTRACE__)
      )

      {:error, "Error preparing weekly ISK data: #{Exception.message(e)}"}
  end

  @doc """
  Prepares data for the kill validation chart.
  """
  def prepare_kill_validation_data do
    AppLogger.kill_info("Preparing kill validation data")

    # Get tracked characters - limit to 8 to prevent timeouts and improve performance
    tracked_characters = get_tracked_characters() |> Enum.take(8)

    if length(tracked_characters) > 0 do
      process_validation_data(tracked_characters)
    else
      handle_no_validation_data("No tracked characters available")
    end
  rescue
    e ->
      AppLogger.kill_error("Error preparing kill validation data",
        error: Exception.message(e),
        stacktrace: Exception.format_stacktrace(__STACKTRACE__)
      )

      {:error, "Error preparing kill validation data: #{Exception.message(e)}"}
  end

  # Process validation data for a list of characters
  defp process_validation_data(tracked_characters) do
    # Get comparison data for each character in parallel
    validation_data = fetch_parallel_validation_data(tracked_characters)

    if length(validation_data) > 0 do
      # Extract chart elements
      {character_labels, zkill_counts, db_counts} = extract_validation_metrics(validation_data)

      # Create chart data structure
      chart_data = create_kill_validation_chart_data(character_labels, zkill_counts, db_counts)
      options = create_kill_validation_chart_options()

      {:ok, chart_data, "Killmail Validation", options}
    else
      handle_no_validation_data("No validation data available for tracked characters")
    end
  end

  # Fetch validation data in parallel
  defp fetch_parallel_validation_data(tracked_characters) do
    tracked_characters
    |> Task.async_stream(
      &get_character_kill_comparison/1,
      max_concurrency: 3,
      timeout: 10_000,
      ordered: false
    )
    |> Enum.map(fn
      {:ok, result} ->
        result

      {:exit, reason} ->
        # Include error details per character when tasks fail
        character_id = get_in(reason, [:character, :character_id]) || "unknown"

        AppLogger.kill_warn("Failed to get comparison data for character", %{
          character_id: character_id,
          reason: inspect(reason)
        })

        nil

      _ ->
        nil
    end)
    |> Enum.filter(&(&1 != nil))
  end

  # Handle cases where no validation data is available
  defp handle_no_validation_data(log_message) do
    AppLogger.kill_warn(log_message)
    empty_chart_data = create_empty_kills_chart_data("No validation data available")
    options = create_empty_chart_options()

    {:ok, empty_chart_data, "Killmail Validation", options}
  end

  @impl true
  def send_weekly_kills_chart_to_discord(channel_id, date_from, date_to) do
    # Generate both kills and ISK charts
    with {:ok, kills_chart_data} <- generate_weekly_kills_chart(),
         {:ok, isk_chart_data} <- generate_weekly_isk_chart(%{limit: 20}) do
      # Send both charts to Discord
      send_generated_charts(
        channel_id,
        date_from,
        date_to,
        kills_chart_data,
        isk_chart_data
      )
    else
      {:error, reason} ->
        AppLogger.kill_error("Failed to generate weekly charts", error: inspect(reason))
        {:error, reason}
    end
  rescue
    e ->
      AppLogger.kill_error("Error sending weekly charts to Discord",
        error: Exception.message(e),
        stacktrace: Exception.format_stacktrace(__STACKTRACE__)
      )

      {:error, "Error sending weekly charts: #{Exception.message(e)}"}
  end

  # Helper to send generated charts to Discord
  defp send_generated_charts(channel_id, date_from, date_to, kills_chart_data, isk_chart_data) do
    kill_title =
      "Weekly Character Kills (#{Date.to_string(date_from)} to #{Date.to_string(date_to)})"
    isk_title =
      "Weekly ISK Destroyed (#{Date.to_string(date_from)} to #{Date.to_string(date_to)})"

    kill_embed = create_chart_embed(kill_title)
    isk_embed = create_chart_embed(isk_title)

    send_chart_file("weekly_kills.png", kills_chart_data, kill_title, channel_id, kill_embed)
    |> then(fn
      :ok ->
        send_chart_file("weekly_isk.png", isk_chart_data, isk_title, channel_id, isk_embed)
        |> handle_second_send_result()

      {:error, reason} ->
        AppLogger.kill_error("Failed to send kills chart to Discord", error: inspect(reason))
        {:error, reason}
    end)
  end

  # Creates a basic Discord embed for a chart
  defp create_chart_embed(title) do
    %{
      "title" => title,
      "color" => 3_447_003
    }
  end

  # Sends a single chart file to Discord
  defp send_chart_file(filename, chart_data, title, channel_id, embed) do
    DiscordClient.send_file(
      filename,
      chart_data,
      title,
      nil,
      channel_id,
      embed
    )
  end

  # Handles the result of sending the second chart
  defp handle_second_send_result(:ok) do
    {:ok, %{status: :ok, message: "Successfully sent both charts to Discord"}}
  end

  defp handle_second_send_result({:error, reason}) do
    AppLogger.kill_error("Failed to send ISK chart to Discord", error: inspect(reason))
    {:error, reason}
  end

  @doc """
  Sends a weekly ISK destroyed chart to Discord.

  ## Parameters
    - title: The title for the chart embed (optional)
    - description: Optional description for the Discord embed
    - channel_id: Optional Discord channel ID to send the chart to
    - limit: Maximum number of characters to display (default 20)

  ## Returns
    - {:ok, message_id} if successful
    - {:error, reason} if something fails
  """
  def send_weekly_isk_chart_to_discord(
        title \\ "Weekly ISK Destroyed",
        description \\ nil,
        channel_id \\ nil,
        limit \\ 20
      ) do
    # Determine actual description if not provided
    actual_description =
      description || "Top #{limit} characters by ISK destroyed in the past week"

    # Generate the chart URL
    case generate_weekly_isk_chart(limit) do
      {:ok, url} ->
        # Send chart to Discord
        ChartService.send_chart_to_discord(
          url,
          title,
          actual_description,
          channel_id
        )

      {:error, reason} ->
        AppLogger.kill_error("Failed to generate weekly ISK destroyed chart",
          error: inspect(reason)
        )

        {:error, reason}
    end
  end

  @doc """
  Sends both weekly kill and ISK destroyed charts to Discord.

  ## Parameters
    - kill_title: Optional title for the kills chart
    - isk_title: Optional title for the ISK destroyed chart
    - description: Optional description for the Discord embeds
    - channel_id: Optional Discord channel ID to send the charts to
    - limit: Maximum number of characters to display (default 20)

  ## Returns
    - {:ok, [kill_message_id, isk_message_id]} if successful
    - {:error, reason} if something fails
  """
  def send_weekly_charts_to_discord(
        _kill_title \\ "Weekly Character Kills",
        isk_title \\ "Weekly ISK Destroyed",
        description \\ nil,
        channel_id \\ nil,
        limit \\ 20
      ) do
    # Get date range for the current week
    today = Date.utc_today()
    days_since_monday = Date.day_of_week(today) - 1
    date_from = Date.add(today, -days_since_monday)
    date_to = Date.add(date_from, 6)

    # Use the behavior-compliant function for kills chart
    kill_result = send_weekly_kills_chart_to_discord(channel_id, date_from, date_to)

    # Send ISK chart
    isk_result = send_weekly_isk_chart_to_discord(isk_title, description, channel_id, limit)

    case {kill_result, isk_result} do
      {{:ok, %{kills_message: kill_msg, isk_message: isk_msg}}, _} ->
        # Since the new function already sends both charts, we can ignore the isk_result
        {:ok, [kill_msg, isk_msg]}

      {{:error, kill_reason}, _} ->
        {:error, "Failed to send charts: #{inspect(kill_reason)}"}

      {_, {:error, isk_reason}} ->
        {:error, "Failed to send ISK chart: #{inspect(isk_reason)}"}
    end
  end

  # Helper functions

  # Get all tracked characters
  defp get_tracked_characters do
    case TrackedCharacter
         |> Query.load([:character_id, :character_name])
         |> Api.read() do
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
           :solo_kills_count,
           :final_blows_count,
           :period_start,
           :period_end
         ])
         |> Api.read() do
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
    |> Enum.filter(fn stat -> stat.kills_count > 0 end)
    |> Enum.sort_by(fn stat -> stat.kills_count end, :desc)
    |> Enum.take(limit)
  end

  # Gets top N characters sorted by ISK destroyed
  defp get_top_characters_by_isk_destroyed(stats, limit) do
    stats
    |> Enum.filter(fn stat ->
      case stat.isk_destroyed do
        nil -> false
        decimal -> Decimal.compare(decimal, Decimal.new(0)) != :eq
      end
    end)
    |> Enum.sort_by(
      fn stat ->
        case stat.isk_destroyed do
          nil -> Decimal.new(0)
          decimal -> decimal
        end
      end,
      :desc
    )
    |> Enum.take(limit)
  end

  # Extracts chart metrics from statistics
  defp extract_kill_metrics(stats) do
    character_labels = Enum.map(stats, fn stat -> stat.character_name end)
    kills_data = Enum.map(stats, fn stat -> stat.kills_count end)
    solo_kills_data = Enum.map(stats, fn stat -> stat.solo_kills_count end)
    final_blows_data = Enum.map(stats, fn stat -> stat.final_blows_count end)

    # Convert Decimal to float for charting
    isk_destroyed_data =
      Enum.map(stats, fn stat ->
        case stat.isk_destroyed do
          nil ->
            0.0

          decimal ->
            # Safely convert to float, handling potential errors
            try do
              decimal
              |> Decimal.round(2)
              |> Decimal.to_float()
              |> Kernel./(1_000_000.0)
            rescue
              _ -> 0.0
            end
        end
      end)

    {character_labels, kills_data, isk_destroyed_data, solo_kills_data, final_blows_data}
  end

  # Creates chart data structure for the weekly kills chart
  defp create_weekly_kills_only_chart_data(labels, kills_data, solo_kills_data, final_blows_data) do
    # Calculate non-solo, non-final blow kills for proper stacking
    # Since kills_data is total kills, we need to calculate the "other" kills
    # that are not solo kills or final blows
    other_kills_data =
      Enum.zip([kills_data, solo_kills_data, final_blows_data])
      |> Enum.map(fn {total, solo, final} ->
        # Ensure we don't go negative due to data inconsistencies
        max(0, total - solo - final)
      end)

    %{
      "type" => "bar",
      "labels" => labels,
      "datasets" => [
        %{
          "label" => "Kills",
          # EVE Online red
          "backgroundColor" => "rgba(220, 53, 69, 0.8)",
          "borderColor" => "rgba(220, 53, 69, 1.0)",
          "borderWidth" => 1,
          "borderRadius" => 4,
          "data" => other_kills_data,
          "stack" => "kills",
          "barPercentage" => 0.8,
          "categoryPercentage" => 0.9
        },
        %{
          "label" => "Solo Kills",
          # EVE Online blue
          "backgroundColor" => "rgba(0, 123, 255, 0.8)",
          "borderColor" => "rgba(0, 123, 255, 1.0)",
          "borderWidth" => 1,
          "borderRadius" => 0,
          "data" => solo_kills_data,
          "stack" => "kills",
          "barPercentage" => 0.8,
          "categoryPercentage" => 0.9
        },
        %{
          "label" => "Final Blows",
          # EVE Online teal
          "backgroundColor" => "rgba(32, 201, 151, 0.8)",
          "borderColor" => "rgba(32, 201, 151, 1.0)",
          "borderWidth" => 1,
          "borderRadius" => 2,
          "data" => final_blows_data,
          "stack" => "kills",
          "barPercentage" => 0.8,
          "categoryPercentage" => 0.9
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
              "color" => "rgba(255, 255, 255, 0.1)",
              "zeroLineColor" => "rgba(255, 255, 255, 0.25)"
            },
            "ticks" => %{
              "fontColor" => "rgb(235, 235, 235)",
              "fontSize" => 12,
              "maxRotation" => 45,
              "autoSkip" => false,
              "padding" => 8
            },
            "scaleLabel" => %{
              "display" => true,
              "labelString" => "Character",
              "fontColor" => "rgb(235, 235, 235)",
              "fontSize" => 14,
              "padding" => 10
            },
            "stacked" => true
          }
        ],
        "yAxes" => [
          %{
            "id" => "kills",
            "position" => "left",
            "gridLines" => %{
              "color" => "rgba(255, 255, 255, 0.1)",
              "zeroLineColor" => "rgba(255, 255, 255, 0.25)",
              "drawBorder" => true
            },
            "ticks" => %{
              "fontColor" => "rgb(235, 235, 235)",
              "fontSize" => 12,
              "padding" => 10,
              "beginAtZero" => true,
              "stepSize" => 1,
              "precision" => 0
            },
            "scaleLabel" => %{
              "display" => true,
              "labelString" => "Number of Kills",
              "fontColor" => "rgb(235, 235, 235)",
              "fontSize" => 14,
              "padding" => 10
            },
            "stacked" => true
          }
        ]
      },
      "legend" => %{
        "display" => true,
        "position" => "top",
        "labels" => %{
          "fontColor" => "rgb(235, 235, 235)",
          "fontSize" => 14,
          "padding" => 20,
          "usePointStyle" => true,
          "boxWidth" => 8
        }
      },
      "title" => %{
        "display" => true,
        "text" => "Weekly Character Kills (Stacked)",
        "fontColor" => "rgb(235, 235, 235)",
        "fontSize" => 18,
        "padding" => 20
      },
      "tooltips" => %{
        "enabled" => true,
        "mode" => "index",
        "intersect" => false,
        "backgroundColor" => "rgba(15, 17, 26, 0.9)",
        "titleFontSize" => 14,
        "bodyFontSize" => 13,
        "cornerRadius" => 4,
        "xPadding" => 10,
        "yPadding" => 10,
        "callbacks" => %{
          "title" => %{
            "__fn" => "function(tooltipItems, data) {
              const characterName = data.labels[tooltipItems[0].index];

              // Calculate total kills for this character
              const totalKills = tooltipItems.reduce((sum, item) => {
                return sum + item.yLabel;
              }, 0);

              return `${characterName} - Total: ${totalKills} kills`;
            }"
          },
          "label" => %{
            "__fn" => "function(tooltipItem, data) {
              const datasetLabel = data.datasets[tooltipItem.datasetIndex].label;
              const value = tooltipItem.yLabel;

              // Calculate the total for this character (all datasets at this index)
              const total = data.datasets.reduce((sum, dataset) => {
                return sum + dataset.data[tooltipItem.index];
              }, 0);

              // Calculate and format percentage
              const percentage = Math.round((value / total) * 100);

              return `${datasetLabel}: ${value} (${percentage}% of total)`;
            }"
          }
        }
      },
      "layout" => %{
        "padding" => %{
          "left" => 20,
          "right" => 20,
          "top" => 20,
          "bottom" => 30
        }
      },
      "plugins" => %{
        "datalabels" => %{
          "display" => false
        }
      }
    }
  end

  defp create_empty_kills_chart_data(message) do
    %{
      "type" => "bar",
      "labels" => ["No Data"],
      "datasets" => [
        %{
          "label" => "Other Kills",
          # EVE Online red (transparent)
          "backgroundColor" => "rgba(220, 53, 69, 0.2)",
          "borderColor" => "rgba(220, 53, 69, 0.2)",
          "borderWidth" => 1,
          "data" => [0],
          "stack" => "kills"
        },
        %{
          "label" => "Solo Kills",
          # EVE Online blue (transparent)
          "backgroundColor" => "rgba(0, 123, 255, 0.2)",
          "borderColor" => "rgba(0, 123, 255, 0.2)",
          "borderWidth" => 1,
          "data" => [0],
          "stack" => "kills"
        },
        %{
          "label" => "Final Blows",
          # EVE Online teal (transparent)
          "backgroundColor" => "rgba(32, 201, 151, 0.2)",
          "borderColor" => "rgba(32, 201, 151, 0.2)",
          "borderWidth" => 1,
          "data" => [0],
          "stack" => "kills"
        }
      ],
      "options" => %{
        "scales" => %{
          "xAxes" => [
            %{
              "stacked" => true
            }
          ],
          "yAxes" => [
            %{
              "stacked" => true
            }
          ]
        },
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

  # Creates chart data structure for the weekly ISK destroyed chart
  defp create_weekly_isk_only_chart_data(labels, isk_destroyed_data) do
    %{
      "type" => "bar",
      "labels" => labels,
      "datasets" => [
        %{
          "label" => "ISK Destroyed (Millions)",
          # EVE Online blue
          "backgroundColor" => "rgba(0, 123, 255, 0.8)",
          "borderColor" => "rgba(0, 123, 255, 1.0)",
          "borderWidth" => 1,
          "borderRadius" => 4,
          "data" => isk_destroyed_data,
          "yAxisID" => "isk"
        }
      ]
    }
  end

  # Creates options for the weekly ISK destroyed chart
  defp create_weekly_isk_chart_options do
    %{
      "responsive" => true,
      "maintainAspectRatio" => false,
      "scales" => %{
        "xAxes" => [
          %{
            "gridLines" => %{
              "color" => "rgba(255, 255, 255, 0.1)",
              "zeroLineColor" => "rgba(255, 255, 255, 0.25)"
            },
            "ticks" => %{
              "fontColor" => "rgb(235, 235, 235)",
              "fontSize" => 12,
              "maxRotation" => 45,
              "autoSkip" => false,
              "padding" => 8
            },
            "scaleLabel" => %{
              "display" => true,
              "labelString" => "Character",
              "fontColor" => "rgb(235, 235, 235)",
              "fontSize" => 14,
              "padding" => 10
            }
          }
        ],
        "yAxes" => [
          %{
            "id" => "isk",
            "position" => "left",
            "gridLines" => %{
              "color" => "rgba(255, 255, 255, 0.1)",
              "zeroLineColor" => "rgba(255, 255, 255, 0.25)",
              "display" => true
            },
            "ticks" => %{
              "fontColor" => "rgb(235, 235, 235)",
              "fontSize" => 12,
              "padding" => 10,
              "beginAtZero" => true,
              "callback" => %{
                "__fn" => "function(value) { return value.toLocaleString() + ' M'; }"
              }
            },
            "scaleLabel" => %{
              "display" => true,
              "labelString" => "ISK (Millions)",
              "fontColor" => "rgb(235, 235, 235)",
              "fontSize" => 14,
              "padding" => 10
            }
          }
        ]
      },
      "legend" => %{
        "display" => true,
        "position" => "top",
        "labels" => %{
          "fontColor" => "rgb(235, 235, 235)",
          "fontSize" => 14,
          "padding" => 20,
          "usePointStyle" => true,
          "boxWidth" => 8
        }
      },
      "title" => %{
        "display" => true,
        "text" => "Weekly ISK Destroyed",
        "fontColor" => "rgb(235, 235, 235)",
        "fontSize" => 18,
        "padding" => 20
      },
      "tooltips" => %{
        "enabled" => true,
        "mode" => "index",
        "intersect" => false,
        "backgroundColor" => "rgba(15, 17, 26, 0.9)",
        "titleFontSize" => 14,
        "bodyFontSize" => 13,
        "cornerRadius" => 4,
        "xPadding" => 10,
        "yPadding" => 10,
        "callbacks" => %{
          "__fn" => "function(tooltipItem, data) {
            return tooltipItem.yLabel.toLocaleString() + ' Million ISK';
          }"
        }
      },
      "layout" => %{
        "padding" => %{
          "left" => 20,
          "right" => 20,
          "top" => 20,
          "bottom" => 30
        }
      },
      "plugins" => %{
        "datalabels" => %{
          "display" => false
        }
      }
    }
  end

  defp create_empty_isk_chart_data(message) do
    %{
      "type" => "bar",
      "labels" => ["No Data"],
      "datasets" => [
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

  # Get comparison data for a character
  defp get_character_kill_comparison(character) do
    # Get database kill count
    db_count = get_character_db_kill_count(character.character_id)

    # Get zkill API kill count
    zkill_count = get_character_zkill_count(character.character_id)

    case {db_count, zkill_count} do
      {{:ok, db_count}, {:ok, zkill_count}} ->
        %{
          character_id: character.character_id,
          character_name: character.character_name || "Character #{character.character_id}",
          db_count: db_count,
          zkill_count: zkill_count
        }

      _ ->
        nil
    end
  end

  # Get kill count from database
  defp get_character_db_kill_count(character_id) do
    query = """
    SELECT COUNT(*) FROM killmails
    WHERE related_character_id = $1
    """

    case Repo.query(query, [character_id]) do
      {:ok, %{rows: [[count]]}} -> {:ok, count}
      _ -> {:error, :query_failed}
    end
  rescue
    _ -> {:error, :database_error}
  end

  # Get kill count from ZKill API
  defp get_character_zkill_count(character_id) do
    alias WandererNotifier.Api.ZKill.Client, as: ZKillClient

    # Use a 100 kill limit to match the load kill data call, without date restrictions
    date_range = %{start: nil, end: nil}
    max_kills = 100

    # Add a task timeout to prevent long-running API calls
    task_fn = fn ->
      ZKillClient.get_character_kills(character_id, date_range, max_kills)
    end

    task_timeout = 5000

    # Execute task with timeout and handle results
    execute_zkill_task(task_fn, task_timeout, character_id)
  end

  # Executes a ZKill API task with timeout and handles results
  defp execute_zkill_task(task_fn, timeout, character_id) do
    task = Task.async(task_fn)

    try do
      case Task.yield(task, timeout) || Task.shutdown(task) do
        {:ok, {:ok, kills}} when is_list(kills) ->
          handle_zkill_success(kills, character_id)

        {:ok, {:error, reason}} ->
          handle_zkill_api_error(reason, character_id)

        nil ->
          handle_zkill_timeout(character_id)

        _ ->
          handle_zkill_unknown_response(character_id)
      end
    rescue
      e ->
        handle_zkill_exception(e, character_id)
    end
  end

  # Handlers for ZKill task results
  defp handle_zkill_success(kills, character_id) do
    AppLogger.kill_debug(
      "Got #{length(kills)} kills from ZKill API for character #{character_id}"
    )

    {:ok, length(kills)}
  end

  defp handle_zkill_api_error(reason, character_id) do
    AppLogger.kill_warn("ZKill API error for character #{character_id}: #{inspect(reason)}")
    {:ok, 0}
  end

  defp handle_zkill_timeout(character_id) do
    AppLogger.kill_warn("ZKill API timeout for character #{character_id}")
    {:ok, 0}
  end

  defp handle_zkill_unknown_response(character_id) do
    AppLogger.kill_warn("Unknown ZKill API response for character #{character_id}")
    {:ok, 0}
  end

  defp handle_zkill_exception(e, character_id) do
    AppLogger.kill_error("Exception in ZKill API call for character #{character_id}",
      error: Exception.message(e)
    )

    {:ok, 0}
  end

  # Extract validation metrics from data
  defp extract_validation_metrics(validation_data) do
    character_labels = Enum.map(validation_data, & &1.character_name)
    zkill_counts = Enum.map(validation_data, & &1.zkill_count)
    db_counts = Enum.map(validation_data, & &1.db_count)

    {character_labels, zkill_counts, db_counts}
  end

  # Create chart data for kill validation
  defp create_kill_validation_chart_data(character_labels, zkill_counts, db_counts) do
    %{
      "type" => "bar",
      "labels" => character_labels,
      "datasets" => [
        %{
          "label" => "ZKill API",
          "data" => zkill_counts,
          "backgroundColor" => "rgba(54, 162, 235, 0.7)",
          "borderColor" => "rgba(54, 162, 235, 1)",
          "borderWidth" => 1
        },
        %{
          "label" => "Database",
          "data" => db_counts,
          "backgroundColor" => "rgba(75, 192, 192, 0.7)",
          "borderColor" => "rgba(75, 192, 192, 1)",
          "borderWidth" => 1
        }
      ]
    }
  end

  # Create options for kill validation chart
  defp create_kill_validation_chart_options do
    %{
      "responsive" => true,
      "maintainAspectRatio" => false,
      "legend" => %{
        "position" => "top"
      },
      "title" => %{
        "display" => true,
        "text" => "Killmail Validation - ZKill API vs Database"
      },
      "scales" => %{
        "yAxes" => [
          %{
            "ticks" => %{
              "beginAtZero" => true
            },
            "scaleLabel" => %{
              "display" => true,
              "labelString" => "Kill Count"
            }
          }
        ],
        "xAxes" => [
          %{
            "ticks" => %{
              "autoSkip" => false,
              "maxRotation" => 90,
              "minRotation" => 45
            }
          }
        ]
      }
    }
  end

  @doc """
  Schedules a kill validation chart to be generated.
  Can be called from a scheduler or manually.

  ## Returns
    - :ok if scheduled
    - {:error, reason} on failure
  """
  def schedule_kill_validation_chart do
    AppLogger.kill_info("Scheduling kill validation chart")

    try do
      # Simply generate the chart now
      case generate_kill_validation_chart() do
        {:ok, _} ->
          AppLogger.kill_info("Kill validation chart generated successfully")
          :ok

        {:error, reason} ->
          AppLogger.kill_error("Failed to generate kill validation chart", error: inspect(reason))
          {:error, reason}
      end
    rescue
      e ->
        AppLogger.kill_error("Error scheduling kill validation chart",
          error: Exception.message(e),
          stacktrace: Exception.format_stacktrace(__STACKTRACE__)
        )

        {:error, "Error scheduling kill validation chart: #{Exception.message(e)}"}
    end
  end
end
