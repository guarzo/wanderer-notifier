defmodule WandererNotifier.Api.Controllers.HealthController do
  @moduledoc """
  Production-ready health check controller with comprehensive monitoring.

  Provides multiple health check endpoints for different monitoring needs:
  - Basic health check for load balancers
  - Detailed health check for monitoring systems
  - Readiness check for orchestration platforms
  - Liveness check for container health
  """
  use WandererNotifier.Api.ApiPipeline
  import Plug.Conn
  import WandererNotifier.Api.Helpers

  alias WandererNotifier.Api.Controllers.SystemInfo
  alias WandererNotifier.Infrastructure.Cache
  alias WandererNotifier.Shared.Config
  alias WandererNotifier.Shared.Utils.ErrorHandler

  # Basic health check endpoint - optimized for load balancers
  get "/" do
    case perform_basic_health_check() do
      {:ok, status} ->
        send_success(conn, status)

      {:error, reason} ->
        send_error(conn, 503, "service_unavailable: #{reason}")
    end
  end

  # Support HEAD requests for health checks (common in orchestration)
  head "/" do
    case perform_basic_health_check() do
      {:ok, _} -> send_resp(conn, 200, "")
      {:error, _} -> send_resp(conn, 503, "")
    end
  end

  # Kubernetes/Docker readiness probe
  get "/ready" do
    case perform_readiness_check() do
      {:ok, status} ->
        send_success(conn, status)

      {:error, reason} ->
        send_error(conn, 503, "not_ready: #{reason}")
    end
  end

  # Kubernetes/Docker liveness probe
  get "/live" do
    case perform_liveness_check() do
      {:ok, status} ->
        send_success(conn, status)

      {:error, reason} ->
        send_error(conn, 503, "not_alive: #{reason}")
    end
  end

  # Detailed health check with comprehensive system information
  get "/details" do
    detailed_status = perform_detailed_health_check()
    send_success(conn, detailed_status)
  end

  # Performance metrics endpoint for monitoring
  get "/metrics" do
    case Config.feature_enabled?(:enable_test_endpoints) do
      true ->
        metrics = collect_performance_metrics()
        send_success(conn, metrics)

      false ->
        send_error(conn, 403, "Metrics endpoint disabled in production")
    end
  end

  match _ do
    send_error(conn, 404, "not_found")
  end

  # Private health check functions

  defp perform_basic_health_check do
    ErrorHandler.safe_execute(
      fn ->
        status = %{
          status: "OK",
          timestamp: WandererNotifier.Shared.Utils.TimeUtils.log_timestamp(),
          version: Config.version(),
          uptime: get_uptime_seconds()
        }

        {:ok, status}
      end,
      context: %{operation: :basic_health_check, category: :health}
    )
  end

  defp perform_readiness_check do
    ErrorHandler.safe_execute(
      fn ->
        checks = perform_health_checks()
        process_readiness_results(checks)
      end,
      context: %{operation: :readiness_check, category: :health}
    )
  end

  defp perform_health_checks do
    [
      {"configuration", check_configuration()},
      {"cache", check_cache_availability()},
      {"external_services", check_external_services()}
    ]
  end

  defp process_readiness_results(checks) do
    failed_checks = checks |> Enum.filter(fn {_name, result} -> result != :ok end)

    case failed_checks do
      [] ->
        create_success_response(checks)

      failed ->
        create_failure_response(failed)
    end
  end

  defp create_success_response(checks) do
    {:ok,
     %{
       status: "ready",
       timestamp: WandererNotifier.Shared.Utils.TimeUtils.log_timestamp(),
       checks: checks |> Enum.map(fn {name, _} -> {name, "ok"} end) |> Map.new()
     }}
  end

  defp create_failure_response(failed) do
    failure_details =
      failed |> Enum.map(fn {name, result} -> {name, inspect(result)} end) |> Map.new()

    {:error, "Readiness checks failed: #{inspect(failure_details)}"}
  end

  defp perform_liveness_check do
    ErrorHandler.safe_execute(
      fn ->
        # Basic liveness checks - should be fast and lightweight
        process_count = length(Process.list())
        memory_usage = :erlang.memory(:total)

        # Check if we have critical processes running
        supervisor_alive = Process.whereis(WandererNotifier.Application) != nil

        if supervisor_alive and process_count > 10 and memory_usage > 0 do
          {:ok,
           %{
             status: "alive",
             timestamp: WandererNotifier.Shared.Utils.TimeUtils.log_timestamp(),
             process_count: process_count,
             memory_bytes: memory_usage
           }}
        else
          {:error,
           "Liveness check failed: supervisor=#{supervisor_alive}, processes=#{process_count}"}
        end
      end,
      context: %{operation: :liveness_check, category: :health}
    )
  end

  defp perform_detailed_health_check do
    basic_info = SystemInfo.collect_detailed_status()

    additional_checks = %{
      cache_status: get_cache_status(),
      external_connectivity: check_external_connectivity(),
      resource_usage: get_resource_usage(),
      feature_flags: get_feature_status(),
      recent_errors: get_recent_errors()
    }

    Map.merge(basic_info, additional_checks)
  end

  defp check_configuration do
    ErrorHandler.safe_execute(
      fn ->
        # Verify critical configuration is present
        required_configs = [:map_url, :license_key, :discord_bot_token]

        missing_configs =
          required_configs
          |> Enum.filter(&config_missing?/1)

        case missing_configs do
          [] -> :ok
          missing -> {:error, "Missing configurations: #{inspect(missing)}"}
        end
      end,
      context: %{operation: :check_configuration, category: :health}
    )
    |> case do
      {:ok, result} -> result
      {:error, _} -> {:error, "Configuration check failed"}
    end
  end

  defp check_cache_availability do
    ErrorHandler.safe_execute(
      fn ->
        # Test cache with a simple operation
        test_key = "health_check_#{:rand.uniform(1000)}"
        Cache.put_with_ttl(test_key, "test_value", Cache.ttl(:health_check))

        case Cache.get(test_key) do
          {:ok, "test_value"} ->
            Cache.delete(test_key)
            :ok

          _ ->
            {:error, "Cache read/write failed"}
        end
      end,
      context: %{operation: :check_cache_availability, category: :health}
    )
    |> case do
      {:ok, result} -> result
      {:error, _} -> {:error, "Cache check failed"}
    end
  end

  defp config_missing?(:map_url), do: config_value_missing?(&Config.map_url/0)
  defp config_missing?(:license_key), do: config_value_missing?(&Config.license_key/0)
  defp config_missing?(:discord_bot_token), do: config_value_missing?(&Config.discord_bot_token/0)
  defp config_missing?(_), do: true

  defp config_value_missing?(config_func) do
    try do
      config_func.()
      false
    rescue
      _ -> true
    end
  end

  defp check_external_services do
    # Basic connectivity check - don't make actual API calls during health checks
    # This would be too expensive for frequent health checks
    :ok
  end

  defp check_external_connectivity do
    %{
      # Would require actual API call
      map_api: "not_checked",
      # Would require actual API call
      discord_api: "not_checked",
      # Would require actual API call
      license_service: "not_checked"
    }
  end

  defp get_cache_status do
    ErrorHandler.safe_execute(
      fn ->
        cache_stats = Cache.stats()

        %{
          enabled: true,
          stats: cache_stats,
          memory_usage: :erlang.memory(:ets)
        }
      end,
      fallback: fn _ -> %{enabled: false, error: "Cache status unavailable"} end,
      context: %{operation: :get_cache_status, category: :health}
    )
    |> case do
      {:ok, result} -> result
      {:error, result} -> result
    end
  end

  defp get_resource_usage do
    memory = :erlang.memory()

    %{
      memory: %{
        total: memory[:total],
        processes: memory[:processes],
        system: memory[:system],
        atom: memory[:atom],
        binary: memory[:binary],
        ets: memory[:ets]
      },
      process_count: length(Process.list()),
      port_count: length(Port.list()),
      uptime_seconds: get_uptime_seconds()
    }
  end

  defp get_feature_status do
    Config.features()
  end

  defp get_recent_errors do
    # This would typically integrate with your error tracking system
    %{
      enabled: false,
      message: "Error tracking not implemented in health checks"
    }
  end

  defp collect_performance_metrics do
    %{
      vm_metrics: %{
        process_count: length(Process.list()),
        port_count: length(Port.list()),
        memory: :erlang.memory(),
        system_info: %{
          otp_release: :erlang.system_info(:otp_release),
          erts_version: :erlang.system_info(:version),
          logical_processors: :erlang.system_info(:logical_processors),
          schedulers: :erlang.system_info(:schedulers)
        }
      },
      cache_metrics: get_cache_performance_metrics()
    }
  end

  defp get_cache_performance_metrics do
    ErrorHandler.safe_execute(
      fn -> Cache.stats() end,
      fallback: fn _ -> %{error: "Cache metrics unavailable"} end,
      context: %{operation: :get_cache_performance_metrics, category: :health}
    )
    |> case do
      {:ok, result} -> result
      {:error, result} -> result
    end
  end

  defp get_uptime_seconds do
    {uptime_ms, _} = :erlang.statistics(:wall_clock)
    div(uptime_ms, 1000)
  end
end
