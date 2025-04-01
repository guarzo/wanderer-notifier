defmodule WandererNotifier.Api.Controllers.KillController do
  @moduledoc """
  Controller for kill-related endpoints.
  """
  use WandererNotifier.Api.Controllers.BaseController
  alias WandererNotifier.Processing.Killmail.{Cache, Comparison, Processor}

  # Get recent kills
  get "/recent" do
    case get_recent_kills(conn) do
      {:ok, kills} -> send_success_response(conn, kills)
      {:error, reason} -> send_error_response(conn, 500, reason)
    end
  end

  # Get kill details
  get "/kill/:kill_id" do
    case Cache.get_kill(kill_id) do
      {:ok, kill} -> send_success_response(conn, kill)
      {:error, :not_cached} -> send_error_response(conn, 404, "Kill not found in cache")
      {:error, :not_found} -> send_error_response(conn, 404, "Kill not found")
      {:error, reason} -> send_error_response(conn, 500, reason)
    end
  end

  # Get kill comparison data from cache
  get "/compare-cache" do
    # Get time range type from query params, default to "4h"
    time_range_type = Map.get(conn.params, "type", "4h")

    # Calculate start and end dates based on time range
    {start_datetime, end_datetime} = get_time_range_dates(time_range_type)

    case Comparison.generate_and_cache_comparison_data(
           time_range_type,
           start_datetime,
           end_datetime
         ) do
      {:ok, comparison_data} ->
        send_success_response(conn, comparison_data)

      {:error, reason} ->
        send_error_response(conn, 500, "Failed to generate comparison data: #{inspect(reason)}")
    end
  end

  match _ do
    send_error_response(conn, 404, "Not found")
  end

  defp get_recent_kills(conn) do
    {:ok, Processor.get_recent_kills()}
  rescue
    error -> handle_error(conn, error, __MODULE__)
  end

  # Helper to calculate start and end dates based on time range type
  defp get_time_range_dates(time_range_type) do
    now = DateTime.utc_now()

    {hours_ago, _} =
      case time_range_type do
        "1h" -> {1, "1 hour"}
        "4h" -> {4, "4 hours"}
        "12h" -> {12, "12 hours"}
        "24h" -> {24, "24 hours"}
        # 7 * 24
        "7d" -> {168, "7 days"}
        # default to 4 hours
        _ -> {4, "4 hours"}
      end

    start_datetime = DateTime.add(now, -hours_ago * 3600, :second)
    {start_datetime, now}
  end
end
