defmodule WandererNotifier.Realtime.HealthChecker do
  @moduledoc """
  Health checking utilities for real-time connections.

  Provides functions to assess connection health, calculate uptime percentages,
  and determine connection quality based on various metrics.
  """

  alias WandererNotifier.Realtime.ConnectionMonitor.Connection

  # Quality thresholds
  @excellent_ping_threshold 100
  @good_ping_threshold 500
  @poor_ping_threshold 2000

  @excellent_uptime_threshold 99.0
  @good_uptime_threshold 95.0
  @poor_uptime_threshold 85.0

  @heartbeat_timeout_seconds 90

  @doc """
  Assesses the overall quality of a connection based on multiple factors.

  Returns one of: :excellent, :good, :poor, :critical
  """
  def assess_connection_quality(%Connection{} = connection) do
    scores = calculate_health_scores(connection)
    weights = get_connection_weights(connection.type)

    weighted_score = calculate_weighted_score(scores, weights)
    categorize_quality_score(weighted_score)
  end

  defp calculate_health_scores(connection) do
    %{
      ping: assess_ping_health(connection),
      uptime: assess_uptime_health(connection),
      heartbeat: assess_heartbeat_health(connection),
      status: assess_status_health(connection)
    }
  end

  defp get_connection_weights(:sse) do
    # No heartbeat for SSE, redistribute to uptime and status
    %{ping: 0.3, uptime: 0.5, heartbeat: 0.0, status: 0.2}
  end

  defp get_connection_weights(:websocket) do
    # Standard weights for WebSocket connections
    %{ping: 0.3, uptime: 0.4, heartbeat: 0.2, status: 0.1}
  end

  defp get_connection_weights(_) do
    # Default weights
    %{ping: 0.3, uptime: 0.4, heartbeat: 0.2, status: 0.1}
  end

  defp calculate_weighted_score(scores, weights) do
    scores.ping * weights.ping +
      scores.uptime * weights.uptime +
      scores.heartbeat * weights.heartbeat +
      scores.status * weights.status
  end

  defp categorize_quality_score(weighted_score) do
    cond do
      weighted_score >= 0.9 -> :excellent
      weighted_score >= 0.7 -> :good
      weighted_score >= 0.5 -> :poor
      true -> :critical
    end
  end

  @doc """
  Calculates the uptime percentage for a connection.
  """
  def calculate_uptime_percentage(%Connection{} = connection) do
    case connection.connected_at do
      nil -> 0.0
      connected_at -> calculate_uptime_from_connection_time(connection, connected_at)
    end
  end

  defp calculate_uptime_from_connection_time(%Connection{} = connection, connected_at) do
    now = DateTime.utc_now()

    # Calculate total time since first connection
    _time_since_first_connect = DateTime.diff(now, connected_at, :second)

    # Calculate current session time if connected
    current_session_time =
      if connection.status == :connected and connection.connected_at do
        DateTime.diff(now, connection.connected_at, :second)
      else
        0
      end

    # Total connected time includes past sessions plus current session
    total_connected_time = connection.total_connected_time + current_session_time

    # Calculate total disconnect time from events
    total_disconnect_time = calculate_total_disconnect_time(connection, now)

    # Calculate actual uptime percentage
    total_time = total_connected_time + total_disconnect_time

    if total_time > 0 do
      uptime = total_connected_time / total_time * 100.0
      Float.round(uptime, 1)
    else
      # New connection with no history
      if connection.status == :connected do
        # Give new connections benefit of doubt
        99.0
      else
        0.0
      end
    end
  end

  defp calculate_total_disconnect_time(%Connection{} = connection, now) do
    # Sum up all completed disconnect periods
    completed_disconnect_time =
      connection.disconnect_events
      |> Enum.map(fn event ->
        # Each event tracks when disconnected and how long was connected before
        # So we need to calculate the disconnect duration from the next connect
        Map.get(event, :disconnect_duration, 0)
      end)
      |> Enum.sum()

    # Add current disconnect period if currently disconnected
    current_disconnect_time =
      if connection.status in [:disconnected, :failed] and connection.last_disconnect_at do
        DateTime.diff(now, connection.last_disconnect_at, :second)
      else
        0
      end

    completed_disconnect_time + current_disconnect_time
  end

  @doc """
  Checks if a connection's heartbeat is healthy.
  """
  def heartbeat_healthy?(%Connection{} = connection) do
    case connection.last_heartbeat do
      nil ->
        false

      last_heartbeat ->
        seconds_since = DateTime.diff(DateTime.utc_now(), last_heartbeat, :second)
        seconds_since <= @heartbeat_timeout_seconds
    end
  end

  @doc """
  Gets the average ping time for a connection.
  """
  def get_average_ping(%Connection{} = connection) do
    ping_samples = connection.metrics[:ping_samples] || []

    case ping_samples do
      [] -> nil
      samples -> (Enum.sum(samples) / length(samples)) |> round()
    end
  end

  @doc """
  Generates a health report for a connection.
  """
  def generate_health_report(%Connection{} = connection) do
    %{
      connection_id: connection.id,
      type: connection.type,
      status: connection.status,
      quality: assess_connection_quality(connection),
      uptime_percentage: calculate_uptime_percentage(connection),
      heartbeat_healthy: heartbeat_healthy?(connection),
      average_ping: get_average_ping(connection),
      connected_duration: get_connected_duration(connection),
      last_heartbeat: connection.last_heartbeat,
      recommendations: generate_recommendations(connection)
    }
  end

  # Private functions

  defp assess_ping_health(%Connection{} = connection) do
    case get_average_ping(connection) do
      # No data, assume moderate
      nil -> 0.5
      ping when ping <= @excellent_ping_threshold -> 1.0
      ping when ping <= @good_ping_threshold -> 0.8
      ping when ping <= @poor_ping_threshold -> 0.5
      _ -> 0.2
    end
  end

  defp assess_uptime_health(%Connection{} = connection) do
    uptime = calculate_uptime_percentage(connection)

    cond do
      uptime >= @excellent_uptime_threshold -> 1.0
      uptime >= @good_uptime_threshold -> 0.8
      uptime >= @poor_uptime_threshold -> 0.5
      true -> 0.2
    end
  end

  defp assess_heartbeat_health(%Connection{} = connection) do
    if heartbeat_healthy?(connection), do: 1.0, else: 0.0
  end

  defp assess_status_health(%Connection{} = connection) do
    case connection.status do
      :connected -> 1.0
      :connecting -> 0.7
      :reconnecting -> 0.5
      :disconnected -> 0.2
      :failed -> 0.0
    end
  end

  defp get_connected_duration(%Connection{} = connection) do
    case connection.connected_at do
      nil -> 0
      connected_at -> DateTime.diff(DateTime.utc_now(), connected_at, :second)
    end
  end

  defp generate_recommendations(%Connection{} = connection) do
    recommendations =
      []
      |> check_heartbeat_recommendation(connection)
      |> check_ping_recommendation(connection)
      |> check_status_recommendation(connection)
      |> check_uptime_recommendation(connection)

    case recommendations do
      [] -> ["Connection appears healthy"]
      recs -> recs
    end
  end

  defp check_heartbeat_recommendation(recommendations, connection) do
    if connection.type == :websocket and not heartbeat_healthy?(connection) do
      ["Check heartbeat mechanism - no recent heartbeat detected" | recommendations]
    else
      recommendations
    end
  end

  defp check_ping_recommendation(recommendations, connection) do
    case get_average_ping(connection) do
      nil ->
        recommendations

      ping when ping > @poor_ping_threshold ->
        ["High latency detected - consider connection optimization" | recommendations]

      _ ->
        recommendations
    end
  end

  defp check_status_recommendation(recommendations, connection) do
    if connection.status == :failed do
      ["Connection failed - check network connectivity" | recommendations]
    else
      recommendations
    end
  end

  defp check_uptime_recommendation(recommendations, connection) do
    uptime = calculate_uptime_percentage(connection)

    if uptime < @poor_uptime_threshold do
      ["Low uptime detected - investigate connection stability" | recommendations]
    else
      recommendations
    end
  end
end
