defmodule WandererNotifier.ChartService.ActivityChartAdapter do
  @moduledoc """
  Adapter for generating character activity charts using the ChartService.

  This adapter is focused solely on data preparation, extracting and transforming
  character activity data into chart-ready formats. It delegates rendering and
  delivery to the ChartService module.
  """
  alias WandererNotifier.Api.Map.CharactersClient
  alias WandererNotifier.ChartService
  alias WandererNotifier.ChartService.ChartConfig
  alias WandererNotifier.ChartService.FallbackStrategy
  alias WandererNotifier.Config.Features
  alias WandererNotifier.Config.Notifications
  alias WandererNotifier.Logger.Logger, as: AppLogger
  alias WandererNotifier.Notifiers.Discord.NeoClient, as: DiscordClient

  @doc """
  Generates an activity summary chart from the provided data.
  """
  def generate_activity_summary_chart(activity_data) do
    AppLogger.api_debug("Starting activity summary chart generation",
      data_preview: inspect(activity_data, limit: 1000)
    )

    with {:ok, character_data} <- extract_character_data(activity_data),
         {:ok, config} <- create_chart_config(character_data) do
      generate_chart_with_fallback(config)
    else
      {:error, reason} = error ->
        AppLogger.api_error("Failed to generate activity summary chart",
          error: inspect(reason),
          step: "data_preparation",
          data_preview: inspect(activity_data, limit: 1000)
        )

        error
    end
  end

  # Create chart configuration from character data
  defp create_chart_config(character_data) do
    # Extract chart elements
    labels = extract_character_labels(character_data)

    {connections_data, passages_data, signatures_data} =
      extract_activity_metrics(character_data)

    AppLogger.api_debug("Creating chart configuration with data",
      labels: labels,
      connections: connections_data,
      passages: passages_data,
      signatures: signatures_data,
      character_data: inspect(character_data, limit: 2000)
    )

    # Create chart data with proper structure
    chart_data = %{
      labels: labels,
      datasets: [
        %{
          label: "Connections",
          data: connections_data,
          backgroundColor: "rgba(54, 162, 235, 0.8)",
          borderColor: "rgba(54, 162, 235, 0.8)",
          borderWidth: 1,
          stack: "stack1"
        },
        %{
          label: "Passages",
          data: passages_data,
          backgroundColor: "rgba(255, 99, 132, 0.8)",
          borderColor: "rgba(255, 99, 132, 0.8)",
          borderWidth: 1,
          stack: "stack1"
        },
        %{
          label: "Signatures",
          data: signatures_data,
          backgroundColor: "rgba(75, 192, 192, 0.8)",
          borderColor: "rgba(75, 192, 192, 0.8)",
          borderWidth: 1,
          stack: "stack1"
        }
      ]
    }

    AppLogger.api_debug("Created chart data structure",
      chart_data: inspect(chart_data, pretty: true, limit: 2000)
    )

    options = %{
      "type" => "bar",
      "responsive" => true,
      "maintainAspectRatio" => false,
      "indexAxis" => "y",
      "plugins" => %{
        "legend" => %{
          "display" => true,
          "position" => "top",
          "labels" => %{
            "color" => "rgb(255, 255, 255)",
            "font" => %{
              "size" => 12
            }
          }
        },
        "title" => %{
          "display" => false
        },
        "datalabels" => %{
          "display" => false
        }
      },
      "scales" => %{
        "x" => %{
          "stacked" => true,
          "grid" => %{
            "color" => "rgba(255, 255, 255, 0.1)"
          },
          "ticks" => %{
            "beginAtZero" => true,
            "color" => "rgb(255, 255, 255)",
            "precision" => 0
          }
        },
        "y" => %{
          "stacked" => true,
          "grid" => %{
            "color" => "rgba(255, 255, 255, 0.1)"
          },
          "ticks" => %{
            "color" => "rgb(255, 255, 255)"
          }
        }
      },
      "layout" => %{
        "padding" => %{
          "left" => 20,
          "right" => 20,
          "top" => 20,
          "bottom" => 20
        }
      },
      "animation" => %{
        "duration" => 0
      }
    }

    case ChartConfig.new("bar", chart_data, "Character Activity Summary", options) do
      {:ok, config} ->
        AppLogger.api_debug("Chart configuration created successfully",
          config: inspect(config, limit: 2000)
        )

        {:ok, config}

      {:error, reason} = error ->
        AppLogger.api_error("Failed to create chart configuration",
          error: inspect(reason),
          chart_data: inspect(chart_data, pretty: true, limit: 2000),
          character_data: inspect(character_data, limit: 2000)
        )

        error
    end
  rescue
    e ->
      AppLogger.api_error("Error creating chart configuration",
        error: inspect(e),
        stacktrace: Exception.format_stacktrace(__STACKTRACE__),
        character_data: inspect(character_data, limit: 2000)
      )

      {:error, "Error creating chart configuration: #{inspect(e)}"}
  end

  # Generate chart with fallback strategy
  defp generate_chart_with_fallback(config) do
    AppLogger.api_debug("Attempting to generate chart with config",
      config: inspect(config, limit: 2000)
    )

    case ChartService.generate_chart_image(config) do
      {:ok, image_data} ->
        AppLogger.api_debug("Chart image generated successfully",
          size: byte_size(image_data)
        )

        {:ok, image_data}

      {:error, reason} = error ->
        AppLogger.api_error(
          "Failed to generate chart image, attempting fallback  #{inspect(error)}",
          error: inspect(reason),
          config: inspect(config, limit: 2000)
        )

        case FallbackStrategy.handle_chart_failure(config) do
          {:ok, _} = success ->
            AppLogger.api_debug("Successfully generated chart using fallback strategy")
            success

          {:error, fallback_reason} = fallback_error ->
            AppLogger.api_error("Fallback strategy also _debug",
              original_error: inspect(reason),
              fallback_error: inspect(fallback_reason)
            )

            fallback_error
        end
    end
  rescue
    e ->
      AppLogger.api_error("Unexpected error generating chart",
        error: inspect(e),
        stacktrace: Exception.format_stacktrace(__STACKTRACE__),
        config: inspect(config, limit: 1000)
      )

      {:error, "Unexpected error generating chart: #{inspect(e)}"}
  end

  @doc """
  Prepares chart data for character activity summary.
  Returns {:ok, chart_data, title, options} or {:error, reason}.
  """
  def prepare_activity_summary_data(activity_data) do
    AppLogger.api_debug("Preparing character activity summary data")

    if activity_data == nil do
      AppLogger.api_error("No activity data provided")
      {:error, "No activity data provided"}
    else
      # Extract character data based on format
      case extract_character_data(activity_data) do
        {:ok, characters} ->
          AppLogger.api_debug("Extracted character data",
            count: length(characters),
            data_preview: inspect(characters, limit: 1000)
          )

          # Get top characters by activity
          top_characters = get_top_characters(characters, 5)

          AppLogger.api_debug("Selected characters for activity chart",
            count: length(top_characters),
            characters: inspect(top_characters, pretty: true, limit: 1000)
          )

          # Extract chart elements
          character_labels = extract_character_labels(top_characters)
          AppLogger.api_debug("Extracted character labels", labels: character_labels)

          {connections_data, passages_data, signatures_data} =
            extract_activity_metrics(top_characters)

          AppLogger.api_debug("Extracted activity metrics",
            connections: connections_data,
            passages: passages_data,
            signatures: signatures_data
          )

          # Create chart data structure
          chart_data =
            create_summary_chart_data(
              character_labels,
              connections_data,
              passages_data,
              signatures_data
            )

          options = create_summary_chart_options()

          AppLogger.api_debug("Created chart data structure",
            chart_data: inspect(chart_data, pretty: true, limit: 2000),
            options: inspect(options, pretty: true, limit: 2000)
          )

          {:ok, chart_data, "Character Activity Summary", options}

        {:error, reason} ->
          AppLogger.api_error("No character data available",
            data_preview: inspect(activity_data, limit: 1000),
            error: reason
          )

          {:error, reason}
      end
    end
  rescue
    e ->
      AppLogger.api_error("Error preparing activity summary data",
        error: inspect(e),
        stacktrace: Exception.format_stacktrace(__STACKTRACE__)
      )

      {:error, "Error preparing activity summary data: #{inspect(e)}"}
  end

  # Extracts character data from various formats
  defp extract_character_data(activity_data) do
    log_data_format(activity_data)

    result =
      case determine_data_format(activity_data) do
        :list ->
          # Check if this is a list of character data
          if Enum.all?(activity_data, &character_data?/1) do
            activity_data
          else
            []
          end

        :data_list ->
          activity_data["data"]

        :characters_map ->
          activity_data["characters"]

        :invalid ->
          handle_invalid_format(activity_data)
      end

    if is_list(result) && length(result) > 0 do
      {:ok, result}
    else
      {:error, "No valid character data found"}
    end
  end

  # Check if the map has character data structure
  defp character_data?(data) when is_map(data) do
    Map.has_key?(data, "character") &&
      (Map.has_key?(data, "connections") ||
         Map.has_key?(data, "passages") ||
         Map.has_key?(data, "signatures"))
  end

  defp character_data?(_), do: false

  # Log the data format for debugging
  defp log_data_format(activity_data) do
    AppLogger.api_debug("Extracting character data from format",
      data_type: get_data_type(activity_data),
      data_preview: inspect(activity_data, limit: 1000)
    )
  end

  # Get the type of data for logging
  defp get_data_type(data) do
    cond do
      is_nil(data) -> "nil"
      is_map(data) -> "map"
      is_list(data) -> "list"
      true -> inspect(data.__struct__) || "unknown"
    end
  end

  # Determine the format of the activity data
  defp determine_data_format(activity_data) do
    cond do
      is_list(activity_data) -> :list
      is_map(activity_data) && has_data_list?(activity_data) -> :data_list
      is_map(activity_data) && has_characters_key?(activity_data) -> :characters_map
      true -> :invalid
    end
  end

  # Check if the map has a "data" key with a list
  defp has_data_list?(map) do
    Map.has_key?(map, "data") && is_list(map["data"])
  end

  # Check if the map has a "characters" key
  defp has_characters_key?(map) do
    Map.has_key?(map, "characters")
  end

  # Handle invalid data format
  defp handle_invalid_format(activity_data) do
    AppLogger.api_error("Invalid data format - couldn't extract character data",
      data_type: get_data_type(activity_data),
      data_preview: inspect(activity_data, limit: 1000)
    )

    []
  end

  # Gets top N characters sorted by total activity
  defp get_top_characters(characters, limit) do
    sorted_characters =
      characters
      |> Enum.sort_by(
        fn char ->
          connections = Map.get(char, "connections", 0)
          passages = Map.get(char, "passages", 0)
          signatures = Map.get(char, "signatures", 0)
          total = connections + passages + signatures

          AppLogger.api_debug("Character activity score",
            character: get_in(char, ["character", "name"]),
            connections: connections,
            passages: passages,
            signatures: signatures,
            total: total
          )

          total
        end,
        :desc
      )
      |> Enum.take(limit)

    AppLogger.api_debug("Top characters sorted by activity",
      characters:
        Enum.map(sorted_characters, fn char ->
          %{
            name: get_in(char, ["character", "name"]),
            connections: Map.get(char, "connections", 0),
            passages: Map.get(char, "passages", 0),
            signatures: Map.get(char, "signatures", 0)
          }
        end)
    )

    sorted_characters
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
    AppLogger.api_debug("Extracting activity metrics from characters",
      characters: inspect(characters, pretty: true, limit: 5000)
    )

    connections_data =
      Enum.map(characters, fn char ->
        connections = Map.get(char, "connections", 0)

        AppLogger.api_debug("Extracted connections for character",
          character: get_in(char, ["character", "name"]),
          connections: connections,
          raw_data: inspect(char)
        )

        connections
      end)

    passages_data =
      Enum.map(characters, fn char ->
        passages = Map.get(char, "passages", 0)

        AppLogger.api_debug("Extracted passages for character",
          character: get_in(char, ["character", "name"]),
          passages: passages,
          raw_data: inspect(char)
        )

        passages
      end)

    signatures_data =
      Enum.map(characters, fn char ->
        signatures = Map.get(char, "signatures", 0)

        AppLogger.api_debug("Extracted signatures for character",
          character: get_in(char, ["character", "name"]),
          signatures: signatures,
          raw_data: inspect(char)
        )

        signatures
      end)

    AppLogger.api_debug("Extracted all metrics",
      connections: connections_data,
      passages: passages_data,
      signatures: signatures_data
    )

    {connections_data, passages_data, signatures_data}
  end

  # Creates chart data structure for summary chart
  defp create_summary_chart_data(labels, connections_data, passages_data, signatures_data) do
    # Define vibrant colors with good contrast
    {connection_color, passage_color, signature_color} = get_chart_colors()

    AppLogger.api_debug("Creating summary chart data",
      labels: labels,
      connections: connections_data,
      passages: passages_data,
      signatures: signatures_data
    )

    # Create the chart data
    %{
      "type" => "bar",
      "data" => %{
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
      },
      "options" => create_summary_chart_options()
    }
  end

  # Creates options for summary chart
  defp create_summary_chart_options do
    options = %{
      "type" => "bar",
      "responsive" => true,
      "maintainAspectRatio" => false,
      "indexAxis" => "y",
      "plugins" => %{
        "legend" => %{
          "display" => true,
          "position" => "top",
          "labels" => %{
            "color" => "rgb(255, 255, 255)",
            "font" => %{
              "size" => 12
            }
          }
        },
        "title" => %{
          "display" => false
        },
        "datalabels" => %{
          "display" => false
        }
      },
      "scales" => %{
        "x" => %{
          "stacked" => true,
          "grid" => %{
            "color" => "rgba(255, 255, 255, 0.1)"
          },
          "ticks" => %{
            "beginAtZero" => true,
            "color" => "rgb(255, 255, 255)",
            "precision" => 0
          }
        },
        "y" => %{
          "stacked" => true,
          "grid" => %{
            "color" => "rgba(255, 255, 255, 0.1)"
          },
          "ticks" => %{
            "color" => "rgb(255, 255, 255)"
          }
        }
      },
      "layout" => %{
        "padding" => %{
          "left" => 20,
          "right" => 20,
          "top" => 20,
          "bottom" => 20
        }
      },
      "animation" => %{
        "duration" => 0
      }
    }

    AppLogger.api_debug("Created chart options",
      options: inspect(options, pretty: true, limit: 2000)
    )

    options
  end

  @doc """
  Generates a chart URL for activity timeline.
  Returns {:ok, url} on success, {:error, reason} on failure.
  """
  def generate_activity_timeline_chart(_activity_data) do
    # This functionality has been removed
    {:error, "Activity Timeline chart has been removed"}
  end

  @doc """
  Prepares chart data for activity timeline.
  Returns {:ok, chart_data, title, options} or {:error, reason}.
  """
  def prepare_activity_timeline_data(_activity_data) do
    # This functionality has been removed
    {:error, "Activity Timeline chart has been removed"}
  end

  @doc """
  Generates a chart URL for activity distribution.
  Returns {:ok, url} on success, {:error, reason} on failure.
  """
  def generate_activity_distribution_chart(_activity_data) do
    # This functionality has been removed
    {:error, "Activity Distribution chart has been removed"}
  end

  @doc """
  Prepares chart data for activity distribution.
  Returns {:ok, chart_data, title, options} or {:error, reason}.
  """
  def prepare_activity_distribution_data(_activity_data) do
    # This functionality has been removed
    {:error, "Activity Distribution chart has been removed"}
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
    - {:ok, %{url: url, title: title}} if successful with URL
    - {:ok, %{title: title}} if successful with file
    - {:error, reason} if something fails
  """
  def send_chart_to_discord(
        activity_data,
        title,
        chart_type \\ "activity_summary",
        description \\ "Top characters by connections, passages, and signatures in the last 24 hours",
        channel_id \\ nil
      ) do
    # Determine actual parameters based on input format
    {actual_chart_type, actual_title, actual_description} =
      resolve_chart_parameters(activity_data, title, chart_type, description)

    # Generate the chart based on the chart type
    chart_result = generate_chart_by_type(actual_chart_type, activity_data)

    # Send the chart to Discord using the ChartService
    case chart_result do
      {:ok, image_data} ->
        # Build embed parameters
        embed_title = resolve_embed_title(actual_title, actual_chart_type)
        enhanced_description = resolve_embed_description(actual_description, actual_chart_type)

        # Create embed with string keys
        embed = %{
          "title" => embed_title,
          "description" => enhanced_description,
          "color" => 3_447_003,
          "footer" => %{
            "text" => "Generated by WandererNotifier"
          },
          "timestamp" => DateTime.utc_now() |> DateTime.to_iso8601()
        }

        # Generate a unique filename
        filename = "chart_#{:os.system_time(:millisecond)}.png"

        # Send directly using NeoClient
        case DiscordClient.send_file(
               filename,
               image_data,
               embed_title,
               enhanced_description,
               channel_id,
               embed
             ) do
          :ok ->
            AppLogger.api_debug("Successfully sent chart to Discord", title: embed_title)
            {:ok, %{title: embed_title}}

          {:error, reason} ->
            AppLogger.api_error("Failed to send chart to Discord", error: inspect(reason))
            {:error, reason}
        end

      {:error, reason} ->
        AppLogger.api_error("Failed to generate chart", error: inspect(reason))
        {:error, reason}
    end
  end

  # Resolves input parameters to determine actual chart type, title, and description
  defp resolve_chart_parameters(activity_data, title, chart_type, description) do
    if is_binary(activity_data) do
      # If activity_data is a string, it's likely the old chart_type format
      {chart_type, title, description}
    else
      # Otherwise, use the new format
      {chart_type, title, description}
    end
  end

  # Generates chart based on the specified type
  defp generate_chart_by_type(chart_type, activity_data) do
    case chart_type do
      type when type in ["activity_summary", :activity_summary] ->
        generate_activity_summary_chart(activity_data)

      type when type in ["activity_timeline", :activity_timeline] ->
        {:error, "Activity Timeline chart has been removed"}

      type when type in ["activity_distribution", :activity_distribution] ->
        {:error, "Activity Distribution chart has been removed"}

      _ ->
        {:error, "Unsupported chart type: #{inspect(chart_type)}"}
    end
  end

  # Resolves the embed title based on provided title and chart type
  defp resolve_embed_title(nil, chart_type) do
    case chart_type do
      type when type in ["activity_summary", :activity_summary] ->
        "Character Activity Summary"

      type when type in ["activity_timeline", :activity_timeline] ->
        "Activity Timeline (Removed)"

      type when type in ["activity_distribution", :activity_distribution] ->
        "Activity Distribution (Removed)"

      _ ->
        "EVE Online Character Activity"
    end
  end

  defp resolve_embed_title(title, _), do: title

  # Resolves the embed description based on provided description and chart type
  defp resolve_embed_description(nil, chart_type) do
    case chart_type do
      type when type in ["activity_summary", :activity_summary] ->
        "Over the last 24 hours"

      type when type in ["activity_timeline", :activity_timeline] ->
        "This chart type has been removed"

      type when type in ["activity_distribution", :activity_distribution] ->
        "This chart type has been removed"

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
        get_activity_charts_channel_id()
      else
        channel_id
      end

    AppLogger.api_debug("Sending activity charts to Discord channel",
      channel_id: actual_channel_id
    )

    # Chart types and their descriptions
    charts = [
      {"activity_summary", "Character Activity Summary", "Over the last 24 hours"}
      # Timeline and distribution charts removed
    ]

    # Send each chart and collect results
    Enum.reduce(charts, %{}, fn {chart_type, title, description}, results ->
      result =
        send_chart_to_discord(activity_data, title, chart_type, description, actual_channel_id)

      Map.put(results, chart_type, result)
    end)
  end

  # Get chart colors for consistent visual identity
  defp get_chart_colors do
    connection_color = "rgba(54, 162, 235, 0.8)"
    passage_color = "rgba(255, 99, 132, 0.8)"
    signature_color = "rgba(75, 192, 192, 0.8)"
    {connection_color, passage_color, signature_color}
  end

  @doc """
  Updates activity charts by generating and sending them to Discord.
  Returns {:ok, count} where count is the number of charts generated and sent,
  or {:error, reason} if the feature is disabled or an error occurs.
  """
  def update_activity_charts do
    if Features.map_charts_enabled?() do
      do_update_activity_charts()
    else
      {:error, :feature_disabled}
    end
  end

  # Main function to update activity charts
  defp do_update_activity_charts do
    AppLogger.api_debug("Generating activity charts")

    with {:ok, activity_data} <- fetch_activity_data(),
         {:ok, channel_id} <- get_discord_channel(),
         {:ok, _} <- send_activity_chart(activity_data, channel_id) do
      {:ok, 1}
    end
  end

  # Fetch activity data from the API
  defp fetch_activity_data do
    case CharactersClient.get_character_activity(nil, 1) do
      {:ok, _data} = result ->
        result

      {:error, reason} ->
        AppLogger.api_error("Failed to get activity data", error: inspect(reason))
        {:error, reason}
    end
  end

  # Get Discord channel ID for sending charts
  defp get_discord_channel do
    case get_activity_charts_channel_id() do
      nil ->
        AppLogger.api_error("No Discord channel configured for activity charts")
        {:error, :no_channel_configured}

      channel_id ->
        {:ok, channel_id}
    end
  end

  # Send activity chart to Discord
  defp send_activity_chart(activity_data, channel_id) do
    case send_chart_to_discord(
           activity_data,
           "Character Activity Summary",
           :activity_summary,
           "Over the last 24 hours",
           channel_id
         ) do
      {:ok, %{title: _title}} = result ->
        AppLogger.api_debug("Successfully sent activity chart to Discord")
        result

      {:error, reason} = error ->
        AppLogger.api_error("Failed to send activity chart to Discord",
          error: inspect(reason)
        )

        error
    end
  end

  @doc """
  Gets the Discord channel ID for activity charts.
  """
  def get_activity_charts_channel_id do
    Notifications.get_discord_channel_id_for(:activity_charts)
  end

  @doc """
  Generates and sends an activity chart to Discord with standardized parameters.
  This is the recommended entry point for generating and sending activity charts.

  ## Parameters
    - activity_data: The activity data to chart
    - channel_id: The Discord channel ID to send to (optional, will use configured default)

  ## Returns
    - {:ok, result} on success
    - {:error, reason} on failure
  """
  def generate_and_send_activity_chart(activity_data, channel_id \\ nil) do
    # Get channel ID from parameter or use configured default
    target_channel = channel_id || Notifications.get_discord_channel_id_for(:activity_charts)

    # Generate the chart
    case generate_activity_summary_chart(activity_data) do
      {:ok, image_data} ->
        # Generate a unique filename
        filename = "chart_#{:os.system_time(:millisecond)}.png"

        # Create embed with image attachment reference
        embed = %{
          "title" => "Character Activity Summary",
          "description" => "Over the last 24 hours",
          "color" => 3_447_003,
          "image" => %{
            "url" => "attachment://#{filename}"
          },
          "footer" => %{
            "text" => "Generated by WandererNotifier"
          },
          "timestamp" => DateTime.utc_now() |> DateTime.to_iso8601()
        }

        # Send directly using NeoClient
        case DiscordClient.send_file(
               filename,
               image_data,
               "Character Activity Summary",
               "Over the last 24 hours",
               target_channel,
               embed
             ) do
          :ok ->
            AppLogger.api_debug("Successfully sent chart to Discord",
              title: "Character Activity Summary"
            )

            {:ok, %{title: "Character Activity Summary"}}

          {:error, reason} ->
            AppLogger.api_error("Failed to send chart to Discord", error: inspect(reason))
            {:error, reason}
        end

      {:error, reason} ->
        AppLogger.api_error("Failed to generate chart", error: inspect(reason))
        {:error, reason}
    end
  end
end
