defmodule WandererNotifier.ChartService.ActivityChartAdapter do
  @moduledoc """
  Adapter for generating character activity charts using the ChartService.

  This adapter is focused solely on data preparation, extracting and transforming
  character activity data into chart-ready formats. It delegates rendering and
  delivery to the ChartService module.
  """

  alias WandererNotifier.ChartService
  alias WandererNotifier.ChartService.ChartConfig
  alias WandererNotifier.ChartService.ChartTypes
  alias WandererNotifier.Config.Features
  alias WandererNotifier.Config.Notifications
  alias WandererNotifier.Logger.Logger, as: AppLogger
  alias WandererNotifier.Api.Map.CharactersClient

  @doc """
  Generates a chart URL for character activity summary.
  Returns {:ok, url} on success, {:error, reason} on failure.
  """
  def generate_activity_summary_chart(activity_data) do
    case prepare_activity_summary_data(activity_data) do
      {:ok, chart_data, title, options} ->
        # Log the chart configuration
        AppLogger.api_debug("Generating activity summary chart with config",
          chart_type: "bar",
          data_preview: %{
            "labels_count" => length(chart_data["labels"] || []),
            "datasets_count" => length(chart_data["datasets"] || []),
            "first_label" => List.first(chart_data["labels"] || [])
          },
          options: options
        )

        # Create chart configuration using the ChartConfig struct
        case ChartConfig.new(
               "bar",
               chart_data,
               title,
               options
             ) do
          {:ok, config} ->
            AppLogger.api_debug("Chart configuration created successfully",
              config_preview: inspect(config, pretty: true, limit: 5000)
            )

            # Use generate_chart_image instead of generate_chart_url
            result = ChartService.generate_chart_image(config)

            case result do
              {:ok, image_data} ->
                AppLogger.api_info("Chart image generated successfully")
                result

              {:error, reason} = error ->
                AppLogger.api_error("Failed to generate chart image", error: inspect(reason))
                error
            end

          {:error, reason} = error ->
            AppLogger.api_error("Failed to create chart configuration", error: inspect(reason))
            error
        end

      {:error, reason} = error ->
        AppLogger.api_error("Failed to prepare activity summary data", error: inspect(reason))
        error
    end
  end

  @doc """
  Prepares chart data for character activity summary.
  Returns {:ok, chart_data, title, options} or {:error, reason}.
  """
  def prepare_activity_summary_data(activity_data) do
    AppLogger.api_info("Preparing character activity summary data")

    if activity_data == nil do
      AppLogger.api_error("No activity data provided")
      {:error, "No activity data provided"}
    else
      # Extract character data based on format
      characters = extract_character_data(activity_data)

      AppLogger.api_debug("Extracted character data",
        count: length(characters),
        data_preview: inspect(characters, limit: 1000)
      )

      if characters && length(characters) > 0 do
        # Get top characters by activity
        top_characters = get_top_characters(characters, 5)

        AppLogger.api_info("Selected characters for activity chart",
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
      else
        AppLogger.api_error("No character data available",
          data_preview: inspect(activity_data, limit: 1000)
        )

        {:error, "No character data available"}
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
    AppLogger.api_debug("Extracting character data from format",
      data_type:
        case activity_data do
          nil -> "nil"
          data when is_map(data) -> "map"
          data when is_list(data) -> "list"
          data -> inspect(data.__struct__) || "unknown"
        end,
      data_preview: inspect(activity_data, limit: 1000)
    )

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
        AppLogger.api_error("Invalid data format - couldn't extract character data",
          data_type:
            case activity_data do
              nil -> "nil"
              data when is_map(data) -> "map"
              data when is_list(data) -> "list"
              data -> inspect(data.__struct__) || "unknown"
            end,
          data_preview: inspect(activity_data, limit: 1000)
        )

        []
    end
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
    connections_data = Enum.map(characters, fn char -> Map.get(char, "connections", 0) end)
    passages_data = Enum.map(characters, fn char -> Map.get(char, "passages", 0) end)
    signatures_data = Enum.map(characters, fn char -> Map.get(char, "signatures", 0) end)

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
    chart_data = %{
      "type" => "bar",
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

    AppLogger.api_debug("Created chart data structure",
      chart_data: inspect(chart_data, pretty: true, limit: 2000)
    )

    chart_data
  end

  # Creates options for summary chart
  defp create_summary_chart_options do
    options = %{
      "type" => "bar",
      "responsive" => true,
      "maintainAspectRatio" => false,
      "indexAxis" => "y",
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
    - {:ok, message_id} if successful
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

        # Send the embed with the chart
        ChartService.send_chart_to_discord(
          image_data,
          embed_title,
          enhanced_description,
          channel_id
        )

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
      "activity_summary" -> generate_activity_summary_chart(activity_data)
      :activity_summary -> generate_activity_summary_chart(activity_data)
      "activity_timeline" -> {:error, "Activity Timeline chart has been removed"}
      :activity_timeline -> {:error, "Activity Timeline chart has been removed"}
      "activity_distribution" -> {:error, "Activity Distribution chart has been removed"}
      :activity_distribution -> {:error, "Activity Distribution chart has been removed"}
      _ -> {:error, "Unsupported chart type: #{inspect(chart_type)}"}
    end
  end

  # Resolves the embed title based on provided title and chart type
  defp resolve_embed_title(nil, chart_type) do
    case chart_type do
      "activity_summary" -> "Character Activity Summary"
      "activity_timeline" -> "Activity Timeline (Removed)"
      "activity_distribution" -> "Activity Distribution (Removed)"
      _ -> "EVE Online Character Activity"
    end
  end

  defp resolve_embed_title(title, _), do: title

  # Resolves the embed description based on provided description and chart type
  defp resolve_embed_description(nil, chart_type) do
    case chart_type do
      "activity_summary" ->
        "Over the last 24 hours"

      "activity_timeline" ->
        "This chart type has been removed"

      "activity_distribution" ->
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

    AppLogger.api_info("Sending activity charts to Discord channel",
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
      AppLogger.api_info("Generating activity charts")

      # Get activity data
      case CharactersClient.get_character_activity(nil, 1) do
        {:ok, activity_data} ->
          # Get Discord channel ID
          channel_id = get_activity_charts_channel_id()

          if channel_id do
            # Generate and send the activity summary chart
            case send_chart_to_discord(
                   activity_data,
                   "Character Activity Summary",
                   "activity_summary",
                   "Over the last 24 hours",
                   channel_id
                 ) do
              {:ok, _url, _title} ->
                AppLogger.api_info("Successfully sent activity chart to Discord")
                {:ok, 1}

              {:error, reason} ->
                AppLogger.api_error("Failed to send activity chart to Discord",
                  error: inspect(reason)
                )

                {:error, reason}
            end
          else
            AppLogger.api_error("No Discord channel configured for activity charts")
            {:error, :no_channel_configured}
          end

        {:error, reason} ->
          AppLogger.api_error("Failed to get activity data", error: inspect(reason))
          {:error, reason}
      end
    else
      {:error, :feature_disabled}
    end
  end

  @doc """
  Gets the Discord channel ID for activity charts.
  """
  def get_activity_charts_channel_id do
    Notifications.get_discord_channel_id_for(:activity_charts)
  end
end
