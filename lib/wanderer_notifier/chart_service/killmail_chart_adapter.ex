defmodule WandererNotifier.ChartService.KillmailChartAdapter do
  @moduledoc """
  Adapter for generating killmail charts using the ChartService.

  This adapter is focused on preparing killmail data for charting,
  such as top character kills, kill statistics, and other killmail-related visualizations.
  """

  @behaviour WandererNotifier.ChartService.KillmailChartAdapterBehaviour

  require Logger
  require Ash.Query
  alias WandererNotifier.Logger, as: AppLogger
  alias WandererNotifier.ChartService
  alias WandererNotifier.Resources.KillmailStatistic
  alias WandererNotifier.Resources.TrackedCharacter
  alias WandererNotifier.Discord.Client, as: DiscordClient
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

      {:error, reason} ->
        AppLogger.kill_error("Failed to prepare weekly kills data", error: inspect(reason))
        generate_empty_chart()
    end
  end

  @doc """
  Generates a chart showing only ISK destroyed for tracked characters.
  """
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
  end

  @doc """
  Prepares chart data for the weekly ISK destroyed chart.
  Returns {:ok, chart_data, title, options} or {:error, reason}.
  """
  def prepare_weekly_isk_data(limit) do
    AppLogger.kill_info("Preparing weekly ISK destroyed chart data")

    try do
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
  end

  @impl true
  def send_weekly_kills_chart_to_discord(channel_id, date_from, date_to) do
    try do
      # Generate both kills and ISK charts
      with {:ok, kills_chart_url} <- generate_weekly_kills_chart(%{limit: 20}),
           {:ok, isk_chart_url} <- generate_weekly_isk_chart(%{limit: 20}) do
        # Send both charts to Discord
        kill_title =
          "Weekly Character Kills (#{Date.to_string(date_from)} to #{Date.to_string(date_to)})"

        isk_title =
          "Weekly ISK Destroyed (#{Date.to_string(date_from)} to #{Date.to_string(date_to)})"

        # Create embeds with chart URLs
        kill_embed = %{
          "title" => kill_title,
          "image" => %{
            "url" => kills_chart_url
          },
          # Discord blue
          "color" => 3_447_003
        }

        isk_embed = %{
          "title" => isk_title,
          "image" => %{
            "url" => isk_chart_url
          },
          # Discord blue
          "color" => 3_447_003
        }

        # Send kills chart and handle potential errors
        with {:ok, kills_message} <- DiscordClient.send_embed(kill_embed, channel_id),
             {:ok, isk_message} <- DiscordClient.send_embed(isk_embed, channel_id) do
          {:ok, %{kills_message: kills_message, isk_message: isk_message}}
        else
          {:error, reason} ->
            AppLogger.kill_error("Failed to send charts to Discord", error: inspect(reason))
            {:error, reason}
        end
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
           :solo_kills_count,
           :final_blows_count,
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
              Decimal.to_float(decimal) / 1_000_000.0
            rescue
              _ -> 0.0
            end
        end
      end)

    {character_labels, kills_data, isk_destroyed_data, solo_kills_data, final_blows_data}
  end

  # Creates chart data structure for the weekly kills chart
  defp create_weekly_kills_only_chart_data(labels, kills_data, solo_kills_data, final_blows_data) do
    %{
      "type" => "bar",
      "labels" => labels,
      "datasets" => [
        %{
          "label" => "Kills",
          "backgroundColor" => "rgba(255, 99, 132, 0.8)",
          "borderColor" => "rgba(255, 99, 132, 0.8)",
          "borderWidth" => 1,
          "data" => kills_data,
          "yAxisID" => "kills"
        },
        %{
          "label" => "Solo Kills",
          "backgroundColor" => "rgba(54, 162, 235, 0.8)",
          "borderColor" => "rgba(54, 162, 235, 0.8)",
          "borderWidth" => 1,
          "data" => solo_kills_data,
          "yAxisID" => "kills"
        },
        %{
          "label" => "Final Blows",
          "backgroundColor" => "rgba(75, 192, 192, 0.8)",
          "borderColor" => "rgba(75, 192, 192, 0.8)",
          "borderWidth" => 1,
          "data" => final_blows_data,
          "yAxisID" => "kills"
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
              "fontColor" => "rgb(255, 255, 255)",
              "maxRotation" => 45,
              "autoSkip" => false
            },
            "scaleLabel" => %{
              "display" => false
            },
            "stacked" => true
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
              "fontColor" => "rgb(255, 255, 255)",
              "padding" => 10,
              "beginAtZero" => true,
              "stepSize" => 1,
              "precision" => 0
            },
            "scaleLabel" => %{
              "display" => false
            },
            "stacked" => true
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
      },
      "layout" => %{
        "padding" => %{
          "left" => 15,
          "right" => 15,
          "top" => 10,
          "bottom" => 20
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
          "label" => "Kills",
          "backgroundColor" => "rgba(255, 99, 132, 0.2)",
          "borderColor" => "rgba(255, 99, 132, 0.2)",
          "borderWidth" => 1,
          "data" => [0],
          "yAxisID" => "kills"
        },
        %{
          "label" => "Solo Kills",
          "backgroundColor" => "rgba(54, 162, 235, 0.2)",
          "borderColor" => "rgba(54, 162, 235, 0.2)",
          "borderWidth" => 1,
          "data" => [0],
          "yAxisID" => "kills"
        },
        %{
          "label" => "Final Blows",
          "backgroundColor" => "rgba(75, 192, 192, 0.2)",
          "borderColor" => "rgba(75, 192, 192, 0.2)",
          "borderWidth" => 1,
          "data" => [0],
          "yAxisID" => "kills"
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
          "backgroundColor" => "rgba(54, 162, 235, 0.8)",
          "borderColor" => "rgba(54, 162, 235, 0.8)",
          "borderWidth" => 1,
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
              "color" => "rgba(255, 255, 255, 0.1)"
            },
            "ticks" => %{
              "fontColor" => "rgb(255, 255, 255)",
              "maxRotation" => 45,
              "autoSkip" => false
            },
            "scaleLabel" => %{
              "display" => false
            }
          }
        ],
        "yAxes" => [
          %{
            "id" => "isk",
            "position" => "left",
            "gridLines" => %{
              "color" => "rgba(255, 255, 255, 0.1)",
              "display" => true
            },
            "ticks" => %{
              "fontColor" => "rgb(255, 255, 255)",
              "padding" => 10,
              "beginAtZero" => true
            },
            "scaleLabel" => %{
              "display" => false
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
        "text" => "Weekly ISK Destroyed",
        "fontColor" => "rgb(255, 255, 255)",
        "fontSize" => 16
      },
      "tooltips" => %{
        "enabled" => true,
        "mode" => "index",
        "intersect" => false
      },
      "layout" => %{
        "padding" => %{
          "left" => 15,
          "right" => 15,
          "top" => 10,
          "bottom" => 20
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
end
