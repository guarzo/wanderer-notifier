defmodule WandererNotifier.Web.Controllers.ChartController do
  @moduledoc """
  Controller for chart-related actions.
  """
  use Plug.Router
  require Logger
  alias WandererNotifier.CorpTools.JSChartAdapter
  alias WandererNotifier.CorpTools.Client, as: CorpToolsClient
  alias WandererNotifier.Map.Client, as: MapClient
  alias WandererNotifier.Config

  plug :match
  plug :dispatch

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

      case MapClient.get_character_activity(slug) do
        {:ok, data} ->
          conn
          |> put_resp_content_type("application/json")
          |> send_resp(200, Jason.encode!(%{status: "ok", data: data}))
        {:error, reason} ->
          conn
          |> put_resp_content_type("application/json")
          |> send_resp(500, Jason.encode!(%{status: "error", message: reason}))
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
        _ -> :invalid
      end

      _title = conn.params["title"] || "EVE Online Chart"
      _description = conn.params["description"] || "Generated chart"

      if chart_type == :invalid do
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(400, Jason.encode!(%{status: "error", message: "Invalid chart type"}))
      else
        case JSChartAdapter.generate_chart(chart_type) do
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
        _ -> :invalid
      end

      title = conn.params["title"] || "EVE Online Chart"
      description = conn.params["description"] || "Generated chart"

      if chart_type == :invalid do
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(400, Jason.encode!(%{status: "error", message: "Invalid chart type"}))
      else
        case JSChartAdapter.send_chart_to_discord(chart_type, title, description) do
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
