defmodule WandererNotifier.Api.Controllers.CacheController do
  @moduledoc """
  Cache analytics API controller.

  Provides RESTful endpoints for cache analytics, insights, and monitoring data.
  """

  use Plug.Router
  require Logger

  alias WandererNotifier.Infrastructure.Cache.Analytics
  alias WandererNotifier.Infrastructure.Cache.Insights

  # Enable request parsing
  plug(Plug.Parsers,
    parsers: [:json],
    pass: ["application/json"],
    json_decoder: Jason
  )

  # Enable routing
  plug(:match)
  plug(:dispatch)

  # CORS headers
  plug(:add_cors_headers)

  get "/analytics" do
    try do
      usage_report = Analytics.get_usage_report()
      efficiency_metrics = Analytics.get_efficiency_metrics()
      patterns = Analytics.analyze_patterns()

      response_data = %{
        usage_report: usage_report,
        efficiency_metrics: efficiency_metrics,
        patterns: patterns,
        timestamp: DateTime.utc_now()
      }

      send_json_response(conn, 200, response_data)
    rescue
      error ->
        Logger.error("Cache analytics error: #{inspect(error)}")
        send_json_response(conn, 500, %{error: "Internal server error"})
    end
  end

  get "/health" do
    try do
      health_score = Insights.get_health_score()
      send_json_response(conn, 200, health_score)
    rescue
      error ->
        Logger.error("Cache health error: #{inspect(error)}")
        send_json_response(conn, 500, %{error: "Internal server error"})
    end
  end

  get "/insights" do
    try do
      recommendations = Insights.get_optimization_recommendations()
      send_json_response(conn, 200, %{recommendations: recommendations})
    rescue
      error ->
        Logger.error("Cache insights error: #{inspect(error)}")
        send_json_response(conn, 500, %{error: "Internal server error"})
    end
  end

  get "/dashboard" do
    try do
      dashboard_data = Insights.get_dashboard_data()
      send_json_response(conn, 200, dashboard_data)
    rescue
      error ->
        Logger.error("Cache dashboard error: #{inspect(error)}")
        send_json_response(conn, 500, %{error: "Internal server error"})
    end
  end

  get "/report" do
    try do
      report = Insights.generate_performance_report()
      send_json_response(conn, 200, report)
    rescue
      error ->
        Logger.error("Cache report error: #{inspect(error)}")
        send_json_response(conn, 500, %{error: "Internal server error"})
    end
  end

  get "/trends" do
    try do
      # Get time range from query params (default 24 hours)
      time_range =
        case get_query_param(conn, "time_range") do
          # 24 hours
          nil ->
            24 * 60 * 60 * 1000

          range_str ->
            case Integer.parse(range_str) do
              {range, _} -> range
              :error -> 24 * 60 * 60 * 1000
            end
        end

      trends = Insights.analyze_trends(time_range)
      send_json_response(conn, 200, trends)
    rescue
      error ->
        Logger.error("Cache trends error: #{inspect(error)}")
        send_json_response(conn, 500, %{error: "Internal server error"})
    end
  end

  get "/alerts" do
    try do
      alerts = Insights.get_alerts()
      send_json_response(conn, 200, %{alerts: alerts})
    rescue
      error ->
        Logger.error("Cache alerts error: #{inspect(error)}")
        send_json_response(conn, 500, %{error: "Internal server error"})
    end
  end

  get "/status" do
    try do
      status = Analytics.get_status()
      send_json_response(conn, 200, status)
    rescue
      error ->
        Logger.error("Cache status error: #{inspect(error)}")
        send_json_response(conn, 500, %{error: "Internal server error"})
    end
  end

  post "/reset" do
    try do
      Analytics.reset_analytics()
      send_json_response(conn, 200, %{message: "Analytics data reset successfully"})
    rescue
      error ->
        Logger.error("Cache reset error: #{inspect(error)}")
        send_json_response(conn, 500, %{error: "Internal server error"})
    end
  end

  post "/collection/start" do
    try do
      Analytics.start_collection()
      send_json_response(conn, 200, %{message: "Analytics collection started"})
    rescue
      error ->
        Logger.error("Cache collection start error: #{inspect(error)}")
        send_json_response(conn, 500, %{error: "Internal server error"})
    end
  end

  post "/collection/stop" do
    try do
      Analytics.stop_collection()
      send_json_response(conn, 200, %{message: "Analytics collection stopped"})
    rescue
      error ->
        Logger.error("Cache collection stop error: #{inspect(error)}")
        send_json_response(conn, 500, %{error: "Internal server error"})
    end
  end

  get "/historical" do
    try do
      # Get time range from query params (default 24 hours)
      time_range =
        case get_query_param(conn, "time_range") do
          # 24 hours
          nil ->
            24 * 60 * 60 * 1000

          range_str ->
            case Integer.parse(range_str) do
              {range, _} -> range
              :error -> 24 * 60 * 60 * 1000
            end
        end

      historical_data = Analytics.get_historical_data(time_range)
      send_json_response(conn, 200, historical_data)
    rescue
      error ->
        Logger.error("Cache historical error: #{inspect(error)}")
        send_json_response(conn, 500, %{error: "Internal server error"})
    end
  end

  # OPTIONS for CORS preflight
  options _ do
    send_resp(conn, 200, "")
  end

  # Catch-all for unsupported endpoints
  match _ do
    send_json_response(conn, 404, %{error: "Endpoint not found"})
  end

  # Helper functions

  defp add_cors_headers(conn, _opts) do
    conn
    |> put_resp_header("access-control-allow-origin", "*")
    |> put_resp_header("access-control-allow-methods", "GET, POST, PUT, DELETE, OPTIONS")
    |> put_resp_header("access-control-allow-headers", "Content-Type, Authorization")
    |> put_resp_header("access-control-max-age", "86400")
  end

  defp send_json_response(conn, status, data) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(status, Jason.encode!(data))
  end

  defp get_query_param(conn, param) do
    case conn.query_params do
      %{^param => value} -> value
      _ -> nil
    end
  end
end
