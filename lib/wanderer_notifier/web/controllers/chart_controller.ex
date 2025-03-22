defmodule WandererNotifier.Web.Controllers.ChartController do
  @moduledoc """
  Controller for chart-related actions.
  """
  use Plug.Router
  require Logger
  alias WandererNotifier.ChartService.ActivityChartAdapter
  alias WandererNotifier.Api.Map.CharactersClient
  alias WandererNotifier.Core.Config
  alias WandererNotifier.Web.Controllers.ActivityChartController

  plug(:match)
  plug(:dispatch)

  # Forward activity chart requests to the ActivityChartController
  forward("/activity", to: ActivityChartController)

  # Get configuration for charts and map tools
  get "/config" do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(
      200,
      Jason.encode!(%{
        tps_charts_enabled: Config.tps_charts_enabled?(),
        map_tools_enabled: Config.map_tools_enabled?()
      })
    )
  end

  # Get character activity data
  get "/character-activity" do
    # Check if map tools functionality is enabled
    if Config.map_tools_enabled?() do
      # Extract slug parameter if provided
      slug = conn.params["slug"]

      # Log the slug for debugging
      if slug do
        Logger.info("Character activity request with explicit slug: #{slug}")
      else
        configured_slug = Config.map_name()

        Logger.info(
          "Character activity request using configured slug: #{configured_slug || "none"}"
        )
      end

      case CharactersClient.get_character_activity(slug) do
        {:ok, data} ->
          conn
          |> put_resp_content_type("application/json")
          |> send_resp(200, Jason.encode!(%{status: "ok", data: data}))

        {:error, reason} ->
          # Log the error for server-side debugging
          Logger.error("Error in character activity endpoint: #{inspect(reason)}")

          # Provide a more user-friendly error message
          error_message =
            case reason do
              "Map slug not provided and not configured" ->
                "Map slug not configured. Please set MAP_NAME in your environment or provide a slug parameter."

              error when is_binary(error) ->
                error

              _ ->
                "An error occurred while fetching character activity data: #{inspect(reason)}"
            end

          conn
          |> put_resp_content_type("application/json")
          |> send_resp(
            500,
            Jason.encode!(%{
              status: "error",
              message: error_message,
              details: inspect(reason)
            })
          )
      end
    else
      conn
      |> put_resp_content_type("application/json")
      |> send_resp(
        404,
        Jason.encode!(%{status: "error", message: "Map Tools functionality is not enabled"})
      )
    end
  end

  # Generate a chart based on the provided type
  get "/generate" do
    # Check if TPS charts functionality is enabled
    if Config.tps_charts_enabled?() do
      # Extract parameters from the query string
      chart_type =
        case conn.params["type"] do
          "damage_final_blows" -> :damage_final_blows
          "combined_losses" -> :combined_losses
          "kill_activity" -> :kill_activity
          "activity_summary" -> :activity_summary
          "activity_timeline" -> :activity_timeline
          "activity_distribution" -> :activity_distribution
          _ -> :invalid
        end

      _title = conn.params["title"] || "EVE Online Chart"
      _description = conn.params["description"] || "Generated chart"

      if chart_type == :invalid do
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(400, Jason.encode!(%{status: "error", message: "Invalid chart type"}))
      else
        # Determine which adapter to use based on chart type
        chart_result =
          case chart_type do
            :damage_final_blows ->
              # TPS functionality has been removed
              {:error, "TPS chart functionality has been removed"}

            :combined_losses ->
              # TPS functionality has been removed
              {:error, "TPS chart functionality has been removed"}

            :kill_activity ->
              # TPS functionality has been removed
              {:error, "TPS chart functionality has been removed"}

            :activity_summary ->
              # Get activity data first
              case CharactersClient.get_character_activity() do
                {:ok, data} -> ActivityChartAdapter.generate_activity_summary_chart(data)
                _ -> {:error, "Failed to get activity data"}
              end

            :activity_timeline ->
              # Get activity data first
              case CharactersClient.get_character_activity() do
                {:ok, data} -> ActivityChartAdapter.generate_activity_timeline_chart(data)
                _ -> {:error, "Failed to get activity data"}
              end

            :activity_distribution ->
              # Get activity data first
              case CharactersClient.get_character_activity() do
                {:ok, data} ->
                  ActivityChartAdapter.generate_activity_distribution_chart(data)

                _ ->
                  {:error, "Failed to get activity data"}
              end
          end

        case chart_result do
          {:ok, url} ->
            conn
            |> put_resp_content_type("application/json")
            |> send_resp(200, Jason.encode!(%{status: "ok", chart_url: url}))

          {:error, reason} ->
            conn
            |> put_resp_content_type("application/json")
            |> send_resp(
              500,
              Jason.encode!(%{
                status: "error",
                message: "Failed to generate chart",
                reason: reason
              })
            )
        end
      end
    else
      conn
      |> put_resp_content_type("application/json")
      |> send_resp(
        404,
        Jason.encode!(%{status: "error", message: "TPS charts functionality is not enabled"})
      )
    end
  end

  # Send a chart to Discord
  get "/send-to-discord" do
    # Check if TPS charts functionality is enabled
    if Config.tps_charts_enabled?() do
      # Extract parameters from the query string
      chart_type =
        case conn.params["type"] do
          "damage_final_blows" -> :damage_final_blows
          "combined_losses" -> :combined_losses
          "kill_activity" -> :kill_activity
          "activity_summary" -> :activity_summary
          "activity_timeline" -> :activity_timeline
          "activity_distribution" -> :activity_distribution
          _ -> :invalid
        end

      title = conn.params["title"] || "EVE Online Chart"
      description = conn.params["description"] || "Generated chart"

      if chart_type == :invalid do
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(400, Jason.encode!(%{status: "error", message: "Invalid chart type"}))
      else
        # Get the appropriate channel ID based on chart type
        channel_id =
          case chart_type do
            type when type in [:activity_summary, :activity_timeline, :activity_distribution] ->
              # Use the activity charts channel ID
              channel = Config.discord_channel_id_for_activity_charts()
              Logger.info("Using Discord channel ID for activity charts: #{channel}")
              channel

            _ ->
              # For TPS charts, use the TPS charts channel or the main channel
              channel = Config.discord_channel_id_for(:tps_charts)
              Logger.info("Using Discord channel ID for TPS charts: #{channel}")
              channel
          end

        # Determine which adapter to use based on chart type
        result =
          case chart_type do
            :damage_final_blows ->
              # TPS functionality has been removed
              {:error, "TPS chart functionality has been removed"}

            :combined_losses ->
              # TPS functionality has been removed
              {:error, "TPS chart functionality has been removed"}

            :kill_activity ->
              # TPS functionality has been removed
              {:error, "TPS chart functionality has been removed"}

            :activity_summary ->
              # Get activity data first for chart generation
              case CharactersClient.get_character_activity() do
                {:ok, data} ->
                  ActivityChartAdapter.send_chart_to_discord(
                    data,
                    title,
                    "activity_summary",
                    description,
                    channel_id
                  )

                _ ->
                  {:error, "Failed to get activity data"}
              end

            :activity_timeline ->
              # Get activity data first for chart generation
              case CharactersClient.get_character_activity() do
                {:ok, data} ->
                  ActivityChartAdapter.send_chart_to_discord(
                    data,
                    title,
                    "activity_timeline",
                    description,
                    channel_id
                  )

                _ ->
                  {:error, "Failed to get activity data"}
              end

            :activity_distribution ->
              # Get activity data first for chart generation
              case CharactersClient.get_character_activity() do
                {:ok, data} ->
                  ActivityChartAdapter.send_chart_to_discord(
                    data,
                    title,
                    "activity_distribution",
                    description,
                    channel_id
                  )

                _ ->
                  {:error, "Failed to get activity data"}
              end
          end

        case result do
          :ok ->
            conn
            |> put_resp_content_type("application/json")
            |> send_resp(200, Jason.encode!(%{status: "ok", message: "Chart sent to Discord"}))

          {:error, reason} ->
            conn
            |> put_resp_content_type("application/json")
            |> send_resp(
              500,
              Jason.encode!(%{
                status: "error",
                message: "Failed to send chart to Discord",
                reason: reason
              })
            )
        end
      end
    else
      conn
      |> put_resp_content_type("application/json")
      |> send_resp(
        404,
        Jason.encode!(%{status: "error", message: "TPS charts functionality is not enabled"})
      )
    end
  end

  # Special route for sending all activity charts
  get "/activity/send-all" do
    Logger.info("Forwarding request to send all activity charts to Discord")

    # Only allow this if map tools are enabled
    if Config.map_tools_enabled?() do
      Logger.info("Forwarding request to activity controller send-all endpoint")

      # Get character activity data
      activity_data =
        case CharactersClient.get_character_activity() do
          {:ok, data} ->
            Logger.info(
              "Successfully retrieved character activity data: #{inspect(data, limit: 500)}"
            )

            data

          error ->
            Logger.error("Failed to retrieve character activity data: #{inspect(error)}")
            nil
        end

      # Get the appropriate channel ID for activity charts
      channel_id = Config.discord_channel_id_for_activity_charts()
      Logger.info("Using Discord channel ID for activity charts: #{channel_id}")

      # Use the ActivityChartAdapter directly to send all charts
      results = ActivityChartAdapter.send_all_charts_to_discord(activity_data, channel_id)

      # Format the results for proper JSON encoding
      formatted_results =
        Enum.map(results, fn {chart_type, result} ->
          case result do
            {:ok, url, title} ->
              %{chart_type: chart_type, status: "success", url: url, title: title}

            {:error, reason} ->
              %{chart_type: chart_type, status: "error", message: reason}

            _ ->
              %{chart_type: chart_type, status: "error", message: "Unknown result format"}
          end
        end)

      # Check if any charts were sent successfully
      success_count = Enum.count(formatted_results, fn result -> result.status == "success" end)

      # Always return success as long as we got a response - a "no data" chart is still a success
      conn
      |> put_resp_content_type("application/json")
      |> send_resp(
        200,
        Jason.encode!(%{
          status: "ok",
          success_count: success_count,
          total_count: length(formatted_results),
          results: formatted_results
        })
      )
    else
      Logger.warning("Map tools are not enabled, cannot send activity charts")

      conn
      |> put_resp_content_type("application/json")
      |> send_resp(404, Jason.encode!(%{status: "error", message: "Map tools are not enabled"}))
    end
  end

  # Get TPS data for debugging
  get "/debug-tps-structure" do
    # Check if TPS charts functionality is enabled
    if Config.tps_charts_enabled?() do
      conn
      |> put_resp_content_type("application/json")
      |> send_resp(200, Jason.encode!(%{status: "ok", message: "TPS charts enabled", data: %{}}))
    else
      conn
      |> put_resp_content_type("application/json")
      |> send_resp(
        404,
        Jason.encode!(%{status: "error", message: "TPS charts functionality is not enabled"})
      )
    end
  end

  # Catch-all route
  match _ do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(404, Jason.encode!(%{error: "Not found"}))
  end
end
