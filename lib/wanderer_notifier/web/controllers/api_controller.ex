defmodule WandererNotifier.Web.Controllers.ApiController do
  @moduledoc """
  API controller for the web interface.
  """
  use Plug.Router
  require Logger
  alias WandererNotifier.CorpTools.Client, as: CorpToolsClient
  alias WandererNotifier.CorpTools.ChartGenerator
  alias WandererNotifier.CorpTools.TPSChartAdapter

  plug :match
  plug :dispatch

  # Health check endpoint
  get "/health" do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(200, Jason.encode!(%{status: "ok"}))
  end

  # Test EVE Corp Tools API integration
  get "/test-corp-tools" do
    case CorpToolsClient.health_check() do
      :ok ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(200, Jason.encode!(%{status: "ok", message: "EVE Corp Tools API is operational"}))
      {:error, reason} ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(500, Jason.encode!(%{status: "error", message: "EVE Corp Tools API health check failed", reason: inspect(reason)}))
    end
  end

  # Get tracked entities from EVE Corp Tools API
  get "/corp-tools/tracked" do
    case CorpToolsClient.get_tracked_entities() do
      {:ok, data} ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(200, Jason.encode!(data))
      {:error, reason} ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(500, Jason.encode!(%{status: "error", message: "Failed to get tracked entities", reason: inspect(reason)}))
    end
  end

  # Get TPS data from EVE Corp Tools API
  get "/corp-tools/tps-data" do
    case CorpToolsClient.get_tps_data() do
      {:ok, data} ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(200, Jason.encode!(data))
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

  # Refresh TPS data on EVE Corp Tools API
  get "/corp-tools/refresh-tps" do
    case CorpToolsClient.refresh_tps_data() do
      :ok ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(200, Jason.encode!(%{status: "ok", message: "TPS data refresh triggered"}))
      {:error, reason} ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(500, Jason.encode!(%{status: "error", message: "Failed to trigger TPS data refresh", reason: inspect(reason)}))
    end
  end

  # Appraise loot using EVE Corp Tools API
  post "/corp-tools/appraise-loot" do
    {:ok, body, conn} = read_body(conn)

    case CorpToolsClient.appraise_loot(body) do
      {:ok, data} ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(200, Jason.encode!(data))
      {:error, reason} ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(500, Jason.encode!(%{status: "error", message: "Failed to appraise loot", reason: inspect(reason)}))
    end
  end

  # Get chart for kills by ship type
  get "/corp-tools/charts/kills-by-ship-type" do
    case TPSChartAdapter.generate_kills_by_ship_type_chart() do
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

  # Get chart for kills by month
  get "/corp-tools/charts/kills-by-month" do
    case TPSChartAdapter.generate_kills_by_month_chart() do
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

  # Get chart for total kills and value
  get "/corp-tools/charts/total-kills-value" do
    case TPSChartAdapter.generate_total_kills_value_chart() do
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

  # Get all TPS charts in a single response
  get "/corp-tools/charts/all" do
    charts = TPSChartAdapter.generate_all_charts()

    if map_size(charts) > 0 do
      conn
      |> put_resp_content_type("application/json")
      |> send_resp(200, Jason.encode!(%{status: "ok", charts: charts}))
    else
      conn
      |> put_resp_content_type("application/json")
      |> send_resp(500, Jason.encode!(%{status: "error", message: "Failed to generate any charts"}))
    end
  end

  # Send a specific TPS chart to Discord
  get "/corp-tools/charts/send-to-discord/:chart_type" do
    chart_type = case conn.params["chart_type"] do
      "kills-by-ship-type" -> :kills_by_ship_type
      "kills-by-month" -> :kills_by_month
      "total-kills-value" -> :total_kills_value
      _ -> :invalid
    end

    if chart_type == :invalid do
      conn
      |> put_resp_content_type("application/json")
      |> send_resp(400, Jason.encode!(%{status: "error", message: "Invalid chart type"}))
    else
      title = case chart_type do
        :kills_by_ship_type -> "Top Ship Types by Kills"
        :kills_by_month -> "Kills by Month"
        :total_kills_value -> "Kills and Value Over Time"
      end

      description = case chart_type do
        :kills_by_ship_type -> "Shows the top 10 ship types used in kills over the last 12 months"
        :kills_by_month -> "Shows the number of kills per month over the last 12 months"
        :total_kills_value -> "Shows the number of kills and estimated value over time"
      end

      case TPSChartAdapter.send_chart_to_discord(chart_type, title, description) do
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

  # Send all TPS charts to Discord
  get "/corp-tools/charts/send-all-to-discord" do
    results = TPSChartAdapter.send_all_charts_to_discord()

    # Check if any of the charts were sent successfully
    any_success = Enum.any?(Map.values(results), fn result -> result == :ok end)

    if any_success do
      conn
      |> put_resp_content_type("application/json")
      |> send_resp(200, Jason.encode!(%{status: "ok", message: "Charts sent to Discord", results: results}))
    else
      conn
      |> put_resp_content_type("application/json")
      |> send_resp(500, Jason.encode!(%{status: "error", message: "Failed to send any charts to Discord", results: results}))
    end
  end

  # Trigger the TPS chart scheduler manually
  get "/corp-tools/charts/trigger-scheduler" do
    if Process.whereis(WandererNotifier.Service.TPSChartScheduler) do
      WandererNotifier.Service.TPSChartScheduler.send_charts_now()

      conn
      |> put_resp_content_type("application/json")
      |> send_resp(200, Jason.encode!(%{status: "ok", message: "TPS chart scheduler triggered"}))
    else
      conn
      |> put_resp_content_type("application/json")
      |> send_resp(500, Jason.encode!(%{status: "error", message: "TPS chart scheduler not running"}))
    end
  end

  # Catch-all route
  match _ do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(404, Jason.encode!(%{error: "Not found"}))
  end
end
