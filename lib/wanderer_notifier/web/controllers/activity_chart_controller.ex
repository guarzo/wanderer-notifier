defmodule WandererNotifier.Web.Controllers.ActivityChartController do
  @moduledoc """
  Controller for activity chart related actions.
  """
  use Plug.Router
  require Logger

  alias WandererNotifier.Api.Map.CharactersClient
  alias WandererNotifier.ChartService.ActivityChartAdapter
  alias WandererNotifier.Config
  alias WandererNotifier.Logger, as: AppLogger

  plug(:match)
  plug(:dispatch)

  # Match all requests and parse parameters
  plug(Plug.Parsers,
    parsers: [:urlencoded, :json],
    json_decoder: Jason
  )

  # Handles requests to generate activity charts based on type.
  # Responds with JSON containing the chart URL.
  get "/generate/:chart_type" do
    # Convert string type to atom
    chart_type =
      case chart_type do
        "activity_summary" -> "activity_summary"
        "activity_timeline" -> "activity_timeline"
        "activity_distribution" -> "activity_distribution"
        _ -> "invalid"
      end

    AppLogger.api_info("Generating activity chart", chart_type: chart_type)

    if chart_type == "invalid" do
      conn
      |> put_resp_content_type("application/json")
      |> send_resp(400, Jason.encode!(%{status: "error", message: "Invalid chart type"}))
    else
      # Get activity data using new CharactersClient
      activity_data =
        case CharactersClient.get_character_activity(nil, 7) do
          {:ok, data} ->
            AppLogger.api_info("Retrieved activity data for chart generation")
            data

          _ ->
            AppLogger.api_warn("Failed to retrieve activity data", fallback: "using nil")
            nil
        end

      # Generate chart based on type
      chart_result =
        case chart_type do
          "activity_summary" ->
            ActivityChartAdapter.generate_activity_summary_chart(activity_data)

          "activity_timeline" ->
            # This chart type has been removed
            {:error, "Activity Timeline chart has been removed"}

          "activity_distribution" ->
            # This chart type has been removed
            {:error, "Activity Distribution chart has been removed"}

          _ ->
            {:error, "Unknown chart type"}
        end

      case chart_result do
        {:ok, chart_url, title} ->
          AppLogger.api_info("Generated chart", title: title)

          conn
          |> put_resp_content_type("application/json")
          |> send_resp(
            200,
            Jason.encode!(%{
              status: "ok",
              chart_url: chart_url,
              title: title
            })
          )

        {:ok, chart_url} ->
          # Handle new return format from ChartService
          title = "Character Activity Chart"
          AppLogger.api_info("Generated chart", format: "new", title: title)

          conn
          |> put_resp_content_type("application/json")
          |> send_resp(
            200,
            Jason.encode!(%{
              status: "ok",
              chart_url: chart_url,
              title: title
            })
          )

        {:error, reason} ->
          AppLogger.api_error("Failed to generate chart",
            chart_type: chart_type,
            error: inspect(reason)
          )

          conn
          |> put_resp_content_type("application/json")
          |> send_resp(
            500,
            Jason.encode!(%{status: "error", message: "Failed to generate chart: #{reason}"})
          )
      end
    end
  end

  # Handles requests to send a chart to Discord.
  # Responds with JSON indicating success or failure.
  get "/send-to-discord/:chart_type" do
    # Convert string type to chart type
    chart_type =
      case chart_type do
        "activity_summary" -> :activity_summary
        "activity_timeline" -> :activity_timeline
        "activity_distribution" -> :activity_distribution
        _ -> :invalid
      end

    AppLogger.api_info("Sending chart to Discord", chart_type: chart_type)

    if chart_type == :invalid do
      conn
      |> put_resp_content_type("application/json")
      |> send_resp(400, Jason.encode!(%{status: "error", message: "Invalid chart type"}))
    else
      # Get activity data using new CharactersClient
      activity_data =
        case CharactersClient.get_character_activity(nil, 7) do
          {:ok, data} ->
            AppLogger.api_info("Retrieved activity data for sending chart")
            data

          _ ->
            AppLogger.api_warn("Failed to retrieve activity data", fallback: "using nil")
            nil
        end

      # Call the controller's helper function to send the chart
      result = send_chart_to_discord(chart_type, activity_data)

      case result do
        {:ok, chart_url, title} ->
          AppLogger.api_info("Sent chart to Discord", title: title)

          conn
          |> put_resp_content_type("application/json")
          |> send_resp(
            200,
            Jason.encode!(%{
              status: "ok",
              message: "Chart sent to Discord",
              chart_url: chart_url,
              title: title
            })
          )

        {:error, reason} ->
          AppLogger.api_error("Failed to send chart to Discord", error: inspect(reason))

          conn
          |> put_resp_content_type("application/json")
          |> send_resp(
            500,
            Jason.encode!(%{
              status: "error",
              message: "Failed to send chart to Discord: #{reason}"
            })
          )
      end
    end
  end

  # Handles requests to send all activity charts to Discord.
  # Returns a summary of the results.
  get "/send-all" do
    AppLogger.api_info("Request to send all activity charts to Discord")

    # Check if we have a map slug configured
    map_slug = Config.map_name()

    if map_slug == nil || map_slug == "" do
      AppLogger.api_info("No map slug configured", action: "using mock data")
    end

    AppLogger.api_info(
      "Sending all charts",
      data_type: if(map_slug == nil || map_slug == "", do: "mock", else: "real")
    )

    # Get character activity data
    activity_data =
      case CharactersClient.get_character_activity(nil, 7) do
        {:ok, data} -> data
        _ -> nil
      end

    # Send all the charts
    results = send_all_charts(activity_data)

    success_count =
      Enum.count(results, fn {_, result} ->
        case result do
          {:ok, _, _} -> true
          _ -> false
        end
      end)

    # Report the results
    AppLogger.api_info(
      "Completed sending all charts to Discord",
      success_count: success_count,
      total_count: length(results)
    )

    # Format the results in a way that can be encoded to JSON
    formatted_results =
      Enum.map(results, fn {chart_type, result} ->
        case result do
          {:ok, url, title} ->
            %{chart_type: chart_type, status: "success", url: url, title: title}

          {:error, message} ->
            %{chart_type: chart_type, status: "error", message: message}

          _ ->
            %{chart_type: chart_type, status: "error", message: "Unknown error"}
        end
      end)

    # Return the response
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(
      200,
      Jason.encode!(%{
        status: "ok",
        success_count: success_count,
        total_count: length(results),
        results: formatted_results
      })
    )
  end

  # Fetches character activity data for display in the UI.
  # Responds with JSON containing the activity data.
  get "/character-activity" do
    AppLogger.api_info("Character activity data request received")

    response =
      case CharactersClient.get_character_activity(nil, 7) do
        {:ok, data} ->
          # Log the data information
          AppLogger.api_info("Retrieved character activity data")

          AppLogger.api_debug("Character activity data structure",
            data: inspect(data, pretty: true, limit: 2000)
          )

          # Determine the structure of the data and log appropriate information
          characters =
            cond do
              # If data is a map with a "data" key that contains a list
              is_map(data) && Map.has_key?(data, "data") && is_list(data["data"]) ->
                AppLogger.api_debug(
                  "Found data structure",
                  type: "map with 'data' key containing a list",
                  record_count: length(data["data"])
                )

                data["data"]

              # If data is a map with a "data" key that contains a map with a "characters" key
              is_map(data) && Map.has_key?(data, "data") && is_map(data["data"]) &&
                  Map.has_key?(data["data"], "characters") ->
                char_data = data["data"]["characters"]

                AppLogger.api_debug(
                  "Found data structure",
                  type: "nested map with characters key",
                  record_count: length(char_data)
                )

                char_data

              # If data is already a list of character data
              is_list(data) ->
                AppLogger.api_debug("Found data structure",
                  type: "list",
                  record_count: length(data)
                )

                data

              # Handle other cases
              true ->
                AppLogger.api_warn("Unexpected data structure",
                  data_preview: inspect(data, limit: 200)
                )

                []
            end

          # Return success with the data in a consistent format
          conn
          |> put_resp_content_type("application/json")
          |> send_resp(
            200,
            Jason.encode!(%{
              status: "ok",
              data: %{characters: characters}
            })
          )

        _ ->
          # Fall back to error response
          AppLogger.api_error("Failed to retrieve character activity data")

          conn
          |> put_resp_content_type("application/json")
          |> send_resp(
            500,
            Jason.encode!(%{status: "error", message: "Failed to retrieve activity data"})
          )
      end

    response
  end

  # Catch-all route
  match _ do
    AppLogger.api_warn("Unmatched route",
      controller: "ActivityChartController",
      path: inspect(conn.request_path)
    )

    conn
    |> put_resp_content_type("application/json")
    |> send_resp(404, Jason.encode!(%{error: "Not found"}))
  end

  # Helper function to send all charts to Discord
  # Returns a list of tuples with chart type and result
  defp send_all_charts(activity_data) do
    AppLogger.api_info("Sending all activity charts to Discord")

    # List of charts to send
    charts = [
      :activity_summary
      # activity_timeline and activity_distribution have been removed
    ]

    # Send each chart and collect the results
    Enum.map(charts, fn chart_type ->
      result = send_chart_to_discord(chart_type, activity_data)
      {chart_type, result}
    end)
  end

  # Helper function to send a specific chart to Discord
  defp send_chart_to_discord(chart_type, activity_data) do
    AppLogger.api_info("Sending chart to Discord", chart_type: chart_type)
    AppLogger.api_debug("Preparing chart for Discord", chart_type: chart_type)

    # Get the appropriate channel ID for activity charts
    channel_id = Config.discord_channel_id_for_activity_charts()
    AppLogger.api_debug("Using Discord channel", channel_id: channel_id, chart_type: "activity")

    # Log the activity data info
    log_activity_data_info(activity_data)

    # Ensure we have activity data or fetch it
    activity_data = ensure_activity_data(activity_data)

    # Generate and send the appropriate chart based on type
    generate_and_send_chart(chart_type, activity_data, channel_id)
  end

  # Log information about the activity data
  defp log_activity_data_info(nil), do: AppLogger.api_debug("Activity data type", type: "nil")

  defp log_activity_data_info(data) when is_map(data) do
    AppLogger.api_debug("Activity data type", type: "map", keys: inspect(Map.keys(data)))
  end

  defp log_activity_data_info(data) when is_list(data) do
    AppLogger.api_debug("Activity data type", type: "list", item_count: length(data))
  end

  defp log_activity_data_info(data) do
    AppLogger.api_debug("Activity data type", type: "other", preview: inspect(data, limit: 50))
  end

  # Ensure we have activity data or fetch it
  defp ensure_activity_data(nil) do
    AppLogger.api_info("Fetching character activity data", source: "EVE Corp Tools API")
    fetch_activity_data()
  end

  defp ensure_activity_data(existing_data), do: existing_data

  # Fetch activity data from the API
  defp fetch_activity_data do
    case CharactersClient.get_character_activity(nil, 7) do
      {:ok, activity_data} ->
        {:ok, activity_data}

      {:error, reason} ->
        AppLogger.processor_error(
          "[ActivityChartController] Failed to fetch activity data: #{inspect(reason)}"
        )

        {:error, reason}
    end
  end

  # Handle chart generation and sending based on chart type
  defp generate_and_send_chart(:activity_summary, activity_data, channel_id) do
    ActivityChartAdapter.send_chart_to_discord(
      activity_data,
      "Character Activity Summary",
      "activity_summary",
      "Top characters by connections, passages, and signatures in the last 24 hours.\nData is refreshed daily.",
      channel_id
    )
  end

  defp generate_and_send_chart(:activity_timeline, _activity_data, _channel_id) do
    # This chart type has been removed
    {:error, "Activity Timeline chart has been removed"}
  end

  defp generate_and_send_chart(:activity_distribution, _activity_data, _channel_id) do
    # This chart type has been removed
    {:error, "Activity Distribution chart has been removed"}
  end

  defp generate_and_send_chart(unknown_type, _activity_data, _channel_id) do
    {:error, "Unknown chart type: #{inspect(unknown_type)}"}
  end
end
