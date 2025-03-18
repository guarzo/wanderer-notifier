defmodule WandererNotifier.Web.Controllers.ChartController do
  @moduledoc """
  Controller for chart-related actions.
  """
  use Plug.Router
  require Logger
  alias WandererNotifier.CorpTools.JSChartAdapter
  alias WandererNotifier.CorpTools.Client, as: CorpToolsClient
  alias WandererNotifier.Map.Client, as: MapClient
  alias WandererNotifier.CorpTools.ActivityChartAdapter
  alias WandererNotifier.CorpTools.ActivityChartScheduler
  alias WandererNotifier.Config
  alias WandererNotifier.Web.Controllers.ActivityChartController

  plug :match
  plug :dispatch

  # Forward activity chart requests to the ActivityChartController
  forward "/activity", to: ActivityChartController

  # Get configuration for charts and map tools
  get "/config" do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(200, Jason.encode!(%{
      corp_tools_enabled: Config.corp_tools_enabled?(),
      map_tools_enabled: Config.map_tools_enabled?()
    }))
  end

  # Get character activity data
  get "/character-activity" do
    # Check if map tools functionality is enabled
    if not Config.map_tools_enabled?() do
      conn
      |> put_resp_content_type("application/json")
      |> send_resp(404, Jason.encode!(%{status: "error", message: "Map Tools functionality is not enabled"}))
    else
      # Extract slug parameter if provided
      slug = conn.params["slug"]

      # Log the slug for debugging
      if slug do
        Logger.info("Character activity request with explicit slug: #{slug}")
      else
        configured_slug = Config.map_name()
        Logger.info("Character activity request using configured slug: #{configured_slug || "none"}")
      end

      case MapClient.get_character_activity(slug) do
        {:ok, data} ->
          conn
          |> put_resp_content_type("application/json")
          |> send_resp(200, Jason.encode!(%{status: "ok", data: data}))
        {:error, reason} ->
          # Log the error for server-side debugging
          Logger.error("Error in character activity endpoint: #{inspect(reason)}")

          # Provide a more user-friendly error message
          error_message = case reason do
            "Map slug not provided and not configured" ->
              "Map slug not configured. Please set MAP_NAME in your environment or provide a slug parameter."
            error when is_binary(error) ->
              error
            _ ->
              "An error occurred while fetching character activity data: #{inspect(reason)}"
          end

          conn
          |> put_resp_content_type("application/json")
          |> send_resp(500, Jason.encode!(%{
            status: "error",
            message: error_message,
            details: inspect(reason)
          }))
      end
    end
  end

  # Generate a chart based on the provided type
  get "/generate" do
    # Check if corp tools functionality is enabled
    if not Config.corp_tools_enabled?() do
      conn
      |> put_resp_content_type("application/json")
      |> send_resp(404, Jason.encode!(%{status: "error", message: "Corp Tools functionality is not enabled"}))
    else
      # Extract parameters from the query string
      chart_type = case conn.params["type"] do
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
        chart_result = case chart_type do
          :damage_final_blows -> JSChartAdapter.generate_chart(chart_type)
          :combined_losses -> JSChartAdapter.generate_chart(chart_type)
          :kill_activity -> JSChartAdapter.generate_chart(chart_type)
          :activity_summary -> ActivityChartAdapter.generate_character_activity_chart()
          :activity_timeline -> ActivityChartAdapter.generate_activity_timeline_chart()
          :activity_distribution -> ActivityChartAdapter.generate_activity_distribution_chart()
        end

        case chart_result do
          {:ok, url} ->
            conn
            |> put_resp_content_type("application/json")
            |> send_resp(200, Jason.encode!(%{status: "ok", chart_url: url}))
          {:error, reason} ->
            conn
            |> put_resp_content_type("application/json")
            |> send_resp(500, Jason.encode!(%{status: "error", message: "Failed to generate chart", reason: reason}))
        end
      end
    end
  end

  # Send a chart to Discord
  get "/send-to-discord" do
    # Check if corp tools functionality is enabled
    if not Config.corp_tools_enabled?() do
      conn
      |> put_resp_content_type("application/json")
      |> send_resp(404, Jason.encode!(%{status: "error", message: "Corp Tools functionality is not enabled"}))
    else
      # Extract parameters from the query string
      chart_type = case conn.params["type"] do
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
        # Determine which adapter to use based on chart type
        result = case chart_type do
          :damage_final_blows -> JSChartAdapter.send_chart_to_discord(chart_type, title, description)
          :combined_losses -> JSChartAdapter.send_chart_to_discord(chart_type, title, description)
          :kill_activity -> JSChartAdapter.send_chart_to_discord(chart_type, title, description)
          :activity_summary -> ActivityChartAdapter.send_chart_to_discord(chart_type, title, description)
          :activity_timeline -> ActivityChartAdapter.send_chart_to_discord(chart_type, title, description)
          :activity_distribution -> ActivityChartAdapter.send_chart_to_discord(chart_type, title, description)
        end

        case result do
          :ok ->
            conn
            |> put_resp_content_type("application/json")
            |> send_resp(200, Jason.encode!(%{status: "ok", message: "Chart sent to Discord"}))
          {:error, reason} ->
            conn
            |> put_resp_content_type("application/json")
            |> send_resp(500, Jason.encode!(%{status: "error", message: "Failed to send chart to Discord", reason: reason}))
        end
      end
    end
  end

  # Send all activity charts to Discord
  get "/send-all-activity-charts" do
    # Check if map tools functionality is enabled
    if not Config.map_tools_enabled?() do
      conn
      |> put_resp_content_type("application/json")
      |> send_resp(404, Jason.encode!(%{status: "error", message: "Map Tools functionality is not enabled"}))
    else
      # This route is kept for backward compatibility
      # Forward to the activity controller's send-all endpoint
      Logger.info("Forwarding send-all-activity-charts request to /charts/activity/send-all")
      
      # Trigger the activity chart scheduler through the adapter
      results = ActivityChartAdapter.send_all_charts_to_discord()
      
      # Check if any chart was successfully sent
      any_success = Enum.any?(Map.values(results), fn result -> result == :ok end)
      
      if any_success do
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(200, Jason.encode!(%{status: "ok", message: "Activity charts sent to Discord", results: inspect(results)}))
      else
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(500, Jason.encode!(%{status: "error", message: "Failed to send any activity charts to Discord", results: inspect(results)}))
      end
    end
  end

  # Get TPS data for debugging
  get "/debug-tps-structure" do
    # Check if corp tools functionality is enabled
    if not Config.corp_tools_enabled?() do
      conn
      |> put_resp_content_type("application/json")
      |> send_resp(404, Jason.encode!(%{status: "error", message: "Corp Tools functionality is not enabled"}))
    else
      case CorpToolsClient.get_tps_data() do
        {:ok, data} ->
          conn
          |> put_resp_content_type("application/json")
          |> send_resp(200, Jason.encode!(%{status: "ok", data: data}))
        {:loading, message} ->
          conn
          |> put_resp_content_type("application/json")
          |> send_resp(206, Jason.encode!(%{status: "loading", message: message}))
        {:error, reason} ->
          conn
          |> put_resp_content_type("application/json")
          |> send_resp(500, Jason.encode!(%{status: "error", message: "Failed to get TPS data", reason: inspect(reason)}))
      end
    end
  end

  # Catch-all route
  match _ do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(404, Jason.encode!(%{error: "Not found"}))
  end
end
