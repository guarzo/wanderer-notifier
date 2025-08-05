defmodule WandererNotifier.Shared.Health do
  @moduledoc """
  Simple health checking without complex state management.

  Provides lightweight health checks for all services without
  the overhead of a GenServer or complex dependency tracking.
  """

  require Logger
  alias WandererNotifier.Shared.Utils.TimeUtils
  alias WandererNotifier.Shared.Dependencies
  alias WandererNotifier.Shared.Config

  @doc """
  Checks the health of all critical services.

  Returns a map with service health status and overall system health.
  """
  @spec check_all_services() :: map()
  def check_all_services do
    services = %{
      cache: check_cache(),
      http: check_http(),
      discord: check_discord(),
      websocket: check_websocket(),
      map_tracking: check_map_tracking()
    }

    %{
      status: overall_status(services),
      services: services,
      uptime: get_uptime(),
      metrics: get_metrics_summary()
    }
  end

  @doc """
  Gets a simple health check response for HTTP endpoints.
  """
  @spec simple_health_check() :: map()
  def simple_health_check do
    %{
      status: :ok,
      uptime: get_uptime(),
      version: Application.spec(:wanderer_notifier, :vsn) |> to_string()
    }
  end

  # ──────────────────────────────────────────────────────────────────────────────
  # Individual Service Checks
  # ──────────────────────────────────────────────────────────────────────────────

  defp check_cache do
    cache_name = Dependencies.cache_name()

    case Process.whereis(cache_name) do
      nil ->
        :unhealthy

      pid when is_pid(pid) ->
        if Process.alive?(pid), do: :healthy, else: :degraded
    end
  rescue
    _ -> :unknown
  end

  defp check_http do
    # Check if HTTP client module is loaded and accessible
    case Code.ensure_loaded(WandererNotifier.Infrastructure.Http) do
      {:module, _} -> :healthy
      _ -> :unhealthy
    end
  end

  defp check_discord do
    # Check if Discord consumer is running
    case Process.whereis(WandererNotifier.Infrastructure.Adapters.Discord.Consumer) do
      nil ->
        :degraded

      pid when is_pid(pid) ->
        if Process.alive?(pid), do: :healthy, else: :degraded
    end
  rescue
    _ -> :unknown
  end

  defp check_websocket do
    # Check if WebSocket client is running
    case Process.whereis(WandererNotifier.Domains.Killmail.WebSocketClient) do
      nil ->
        :degraded

      pid when is_pid(pid) ->
        if Process.alive?(pid), do: :healthy, else: :degraded
    end
  rescue
    _ -> :unknown
  end

  defp check_map_tracking do
    # Check if SSE client is running using Registry lookup
    try do
      map_slug = Config.map_name()

      case Registry.lookup(WandererNotifier.Registry, {:sse_client, map_slug}) do
        [] ->
          :degraded

        [{pid, _}] when is_pid(pid) ->
          if Process.alive?(pid), do: :healthy, else: :degraded
      end
    rescue
      _ -> :unknown
    end
  end

  # ──────────────────────────────────────────────────────────────────────────────
  # Helper Functions
  # ──────────────────────────────────────────────────────────────────────────────

  defp overall_status(services) do
    statuses = Map.values(services)

    cond do
      Enum.any?(statuses, &(&1 == :unhealthy)) -> :unhealthy
      Enum.any?(statuses, &(&1 == :degraded)) -> :degraded
      Enum.any?(statuses, &(&1 == :unknown)) -> :degraded
      true -> :healthy
    end
  end

  defp get_uptime do
    case Process.whereis(WandererNotifier.Shared.Metrics) do
      nil ->
        "0s"

      _pid ->
        seconds = WandererNotifier.Shared.Metrics.get_uptime_seconds()
        TimeUtils.format_uptime(seconds)
    end
  rescue
    _ -> "unknown"
  end

  defp get_metrics_summary do
    case Process.whereis(WandererNotifier.Shared.Metrics) do
      nil ->
        %{}

      _pid ->
        stats = WandererNotifier.Shared.Metrics.get_stats()

        %{
          notifications: Map.get(stats, :notifications_sent, %{}),
          counters: Map.get(stats, :counters, %{}),
          tracked_systems: Map.get(stats, :systems_count, 0),
          tracked_characters: Map.get(stats, :characters_count, 0)
        }
    end
  rescue
    _ -> %{}
  end
end
