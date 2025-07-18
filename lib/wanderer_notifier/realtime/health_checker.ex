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
    ping_score = assess_ping_health(connection)
    uptime_score = assess_uptime_health(connection)
    heartbeat_score = assess_heartbeat_health(connection)
    status_score = assess_status_health(connection)

    # Adjust weights based on connection type
    # SSE connections don't have heartbeats, so redistribute that weight
    {ping_weight, uptime_weight, heartbeat_weight, status_weight} =
      case connection.type do
        :sse ->
          # No heartbeat for SSE, redistribute to uptime and status
          {0.3, 0.5, 0.0, 0.2}

        :websocket ->
          # Standard weights for WebSocket connections
          {0.3, 0.4, 0.2, 0.1}

        _ ->
          # Default weights
          {0.3, 0.4, 0.2, 0.1}
      end

    weighted_score =
      ping_score * ping_weight +
        uptime_score * uptime_weight +
        heartbeat_score * heartbeat_weight +
        status_score * status_weight

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
      nil ->
        0.0

      connected_at ->
        now = DateTime.utc_now()
        total_seconds = DateTime.diff(now, connected_at, :second)

        # For now, we'll use a simple calculation based on current status
        # In a real implementation, you'd track disconnect periods
        case connection.status do
          :connected ->
            # If currently connected, assume good uptime unless we track disconnections
            # Give new connections benefit of doubt after grace period
            if total_seconds > 300 do
              # After 5 minutes, assume good uptime (99.0%) for stable connections
              99.0
            else
              # Grace period for new connections - don't penalize them
              99.0
            end

          :connecting ->
            85.0

          :reconnecting ->
            80.0

          :failed ->
            0.0

          :disconnected ->
            50.0
        end
    end
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
    recommendations = []

    recommendations =
      if connection.type == :websocket and not heartbeat_healthy?(connection) do
        ["Check heartbeat mechanism - no recent heartbeat detected" | recommendations]
      else
        recommendations
      end

    recommendations =
      case get_average_ping(connection) do
        nil ->
          recommendations

        ping when ping > @poor_ping_threshold ->
          ["High latency detected - consider connection optimization" | recommendations]

        _ ->
          recommendations
      end

    recommendations =
      if connection.status == :failed do
        ["Connection failed - check network connectivity" | recommendations]
      else
        recommendations
      end

    uptime = calculate_uptime_percentage(connection)

    recommendations =
      if uptime < @poor_uptime_threshold do
        ["Low uptime detected - investigate connection stability" | recommendations]
      else
        recommendations
      end

    case recommendations do
      [] -> ["Connection appears healthy"]
      recs -> recs
    end
  end
end
