defmodule WandererNotifier.Web.Controllers.ActivityChartController do
  @moduledoc """
  Controller for activity chart related actions.
  """
  use Plug.Router
  require Logger
  alias WandererNotifier.ChartService.ActivityChartAdapter
  alias WandererNotifier.Api.Map.CharactersClient
  alias WandererNotifier.Core.Config

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

    Logger.info("Generating activity chart type: #{inspect(chart_type)}")

    if chart_type == "invalid" do
      conn
      |> put_resp_content_type("application/json")
      |> send_resp(400, Jason.encode!(%{status: "error", message: "Invalid chart type"}))
    else
      # Get activity data using new CharactersClient
      activity_data =
        case CharactersClient.get_character_activity() do
          {:ok, data} ->
            Logger.info("Successfully retrieved activity data for chart generation")
            data

          _ ->
            Logger.warning("Failed to retrieve activity data, using nil")
            nil
        end

      # Generate chart based on type
      chart_result =
        case chart_type do
          "activity_summary" ->
            ActivityChartAdapter.generate_activity_summary_chart(activity_data)

          "activity_timeline" ->
            ActivityChartAdapter.generate_activity_timeline_chart(activity_data)

          "activity_distribution" ->
            ActivityChartAdapter.generate_activity_distribution_chart(activity_data)

          _ ->
            {:error, "Unknown chart type"}
        end

      case chart_result do
        {:ok, chart_url, title} ->
          Logger.info("Generated chart: #{title}")

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
          Logger.info("Generated chart (new format): #{title}")

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
          Logger.error("Failed to generate #{chart_type} chart: #{inspect(reason)}")

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

    Logger.info("Sending #{chart_type} chart to Discord")

    if chart_type == :invalid do
      conn
      |> put_resp_content_type("application/json")
      |> send_resp(400, Jason.encode!(%{status: "error", message: "Invalid chart type"}))
    else
      # Get activity data using new CharactersClient
      activity_data =
        case CharactersClient.get_character_activity() do
          {:ok, data} ->
            Logger.info("Successfully retrieved activity data for sending chart")
            data

          _ ->
            Logger.warning("Failed to retrieve activity data, using nil")
            nil
        end

      # Call the controller's helper function to send the chart
      result = send_chart_to_discord(chart_type, activity_data)

      case result do
        {:ok, chart_url, title} ->
          Logger.info("Successfully sent chart to Discord: #{title}")

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
          Logger.error("Failed to send chart to Discord: #{inspect(reason)}")

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
    Logger.info("Request to send all activity charts to Discord")

    # Check if we have a map slug configured
    map_slug = Config.map_name()

    if map_slug == nil || map_slug == "" do
      Logger.info("No map slug configured, using mock data")
    end

    Logger.info(
      "Sending all charts with #{if map_slug == nil || map_slug == "", do: "mock", else: "real"} data"
    )

    # Get character activity data
    activity_data =
      case CharactersClient.get_character_activity() do
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
    Logger.info(
      "Completed sending all activity charts to Discord. Success: #{success_count}/#{length(results)}"
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
    Logger.info("Character activity data request received")

    response =
      case CharactersClient.get_character_activity() do
        {:ok, data} ->
          # Log the full data structure to see what we're working with
          Logger.info("Successfully retrieved character activity data")
          Logger.info("Data structure: #{inspect(data, pretty: true, limit: 5000)}")

          # Determine the structure of the data and log appropriate information
          characters =
            cond do
              # If data is a map with a "data" key that contains a list
              is_map(data) && Map.has_key?(data, "data") && is_list(data["data"]) ->
                Logger.info(
                  "Found data structure: map with 'data' key containing a list of #{length(data["data"])} records"
                )

                data["data"]

              # If data is a map with a "data" key that contains a map with a "characters" key
              is_map(data) && Map.has_key?(data, "data") && is_map(data["data"]) &&
                  Map.has_key?(data["data"], "characters") ->
                char_data = data["data"]["characters"]

                Logger.info(
                  "Found data structure: nested map with characters key containing #{length(char_data)} records"
                )

                char_data

              # If data is already a list of character data
              is_list(data) ->
                Logger.info("Found data structure: list with #{length(data)} records")
                data

              # Handle other cases
              true ->
                Logger.info("Unexpected data structure: #{inspect(data, limit: 200)}")
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
          Logger.error("Failed to retrieve character activity data")

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
    Logger.warning("Unmatched route in ActivityChartController: #{inspect(conn.request_path)}")

    conn
    |> put_resp_content_type("application/json")
    |> send_resp(404, Jason.encode!(%{error: "Not found"}))
  end

  # Helper function to send all charts to Discord
  # Returns a list of tuples with chart type and result
  defp send_all_charts(activity_data) do
    Logger.info("Sending all activity charts to Discord")

    # List of charts to send
    charts = [
      :activity_summary,
      :activity_timeline,
      :activity_distribution
    ]

    # Send each chart and collect the results
    Enum.map(charts, fn chart_type ->
      result = send_chart_to_discord(chart_type, activity_data)
      {chart_type, result}
    end)
  end

  # Helper function to send a specific chart to Discord
  defp send_chart_to_discord(chart_type, activity_data) do
    Logger.info("Sending #{chart_type} chart to Discord")
    Logger.info("Preparing to send #{chart_type} chart to Discord")

    # Get the appropriate channel ID for activity charts
    channel_id = WandererNotifier.Core.Config.discord_channel_id_for_activity_charts()
    Logger.info("Using Discord channel ID for activity charts: #{channel_id}")

    # Log the activity data info
    log_activity_data_info(activity_data)

    # Ensure we have activity data or fetch it
    activity_data = ensure_activity_data(activity_data)
    
    # Generate and send the appropriate chart based on type
    generate_and_send_chart(chart_type, activity_data, channel_id)
  end
  
  # Log information about the activity data
  defp log_activity_data_info(nil), do: Logger.info("Activity data type: nil")
  
  defp log_activity_data_info(data) when is_map(data) do
    Logger.info("Activity data type: map with keys: #{inspect(Map.keys(data))}")
  end
  
  defp log_activity_data_info(data) when is_list(data) do
    Logger.info("Activity data type: list with #{length(data)} items")
  end
  
  defp log_activity_data_info(data) do
    Logger.info("Activity data type: #{inspect(data, limit: 50)}")
  end
  
  # Ensure we have activity data or fetch it
  defp ensure_activity_data(nil) do
    Logger.info("Fetching character activity data from EVE Corp Tools API")
    fetch_activity_data()
  end
  
  defp ensure_activity_data(existing_data), do: existing_data
  
  # Fetch activity data from the API
  defp fetch_activity_data do
    case CharactersClient.get_character_activity() do
      {:ok, data} -> 
        data
        
      {:error, reason} ->
        Logger.error("Failed to fetch activity data: #{inspect(reason)}")
        nil
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
  
  defp generate_and_send_chart(:activity_timeline, activity_data, channel_id) do
    # Use generate_ instead of send_ since that's what the adapter provides
    with {:ok, url} <- ActivityChartAdapter.generate_activity_timeline_chart(activity_data),
         :ok <- WandererNotifier.ChartService.send_chart_to_discord(
                  url,
                  "Activity Timeline",
                  "Activity over time",
                  channel_id
                ) do
      {:ok, url, "Activity Timeline"}
    end
  end
  
  defp generate_and_send_chart(:activity_distribution, activity_data, channel_id) do
    # Use generate_ instead of send_ since that's what the adapter provides
    with {:ok, url} <- ActivityChartAdapter.generate_activity_distribution_chart(activity_data),
         :ok <- WandererNotifier.ChartService.send_chart_to_discord(
                  url,
                  "Activity Distribution",
                  "Distribution of activities",
                  channel_id
                ) do
      {:ok, url, "Activity Distribution"}
    end
  end
  
  defp generate_and_send_chart(unknown_type, _activity_data, _channel_id) do
    {:error, "Unknown chart type: #{inspect(unknown_type)}"}
  end
end
