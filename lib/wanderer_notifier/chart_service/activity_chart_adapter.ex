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
  alias WandererNotifier.Core.Logger, as: AppLogger

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
    AppLogger.api_info("Preparing character activity summary data")

    if activity_data == nil do
      AppLogger.api_error("No activity data provided")
      {:error, "No activity data provided"}
    else
      # Extract character data based on format
      characters = extract_character_data(activity_data)

      if characters && length(characters) > 0 do
        # Get top characters by activity
        top_characters = get_top_characters(characters, 5)

        AppLogger.api_info("Selected characters for activity chart",
          count: length(top_characters)
        )

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
    end
  rescue
    e ->
      AppLogger.api_error("Error preparing activity summary data", error: inspect(e))
      {:error, "Error preparing activity summary data: #{inspect(e)}"}
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
        AppLogger.api_error("Invalid data format - couldn't extract character data")
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
        AppLogger.api_error("Failed to generate chart", error: inspect(reason))
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
        # Return error for removed functionality
        {:error, "Activity Timeline chart has been removed"}

      "activity_distribution" ->
        # Return error for removed functionality
        {:error, "Activity Distribution chart has been removed"}

      _ ->
        {:error, "Unsupported chart type: #{chart_type}"}
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
        "Top characters by connections, passages, and signatures in the last 24 hours"

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

  # Get chart colors for consistent visual identity
  defp get_chart_colors do
    connection_color = "rgba(54, 162, 235, 0.8)"
    passage_color = "rgba(255, 99, 132, 0.8)"
    signature_color = "rgba(75, 192, 192, 0.8)"
    {connection_color, passage_color, signature_color}
  end

  @doc """
  Updates activity charts.
  """
  def update_activity_charts do
    if Features.activity_charts_enabled?() do
      # Implementation here
      {:ok, 0}
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
