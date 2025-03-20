defmodule WandererNotifier.Web.Controllers.DebugController do
  @moduledoc """
  Provides debug and monitoring endpoints for the application.
  """
  use Plug.Router
  require Logger
  
  alias WandererNotifier.Config.Timings
  alias WandererNotifier.Schedulers.Registry, as: SchedulerRegistry
  alias WandererNotifier.Data.Cache.Repository, as: CacheRepo
  
  plug(:match)
  plug(Plug.Parsers, parsers: [:json], json_decoder: Jason)
  plug(:dispatch)
  
  # Application status endpoint
  get "/status" do
    status_data = %{
      application: %{
        name: "WandererNotifier",
        version: Application.spec(:wanderer_notifier, :vsn) || "development",
        started_at: get_start_time(),
        uptime: get_uptime_string()
      },
      runtime: %{
        elixir_version: System.version(),
        otp_version: :erlang.system_info(:otp_release) |> List.to_string(),
        system_architecture: :erlang.system_info(:system_architecture) |> List.to_string()
      },
      memory: %{
        total: :erlang.memory(:total) |> bytes_to_mb(),
        processes: :erlang.memory(:processes) |> bytes_to_mb(),
        atom: :erlang.memory(:atom) |> bytes_to_mb(),
        binary: :erlang.memory(:binary) |> bytes_to_mb(),
        code: :erlang.memory(:code) |> bytes_to_mb(),
        ets: :erlang.memory(:ets) |> bytes_to_mb()
      }
    }
    
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(200, Jason.encode!(status_data))
  end
  
  # Scheduler configurations endpoint
  get "/schedulers" do
    configured_schedulers = Timings.scheduler_configs()
    registered_schedulers = SchedulerRegistry.get_all_schedulers()
    
    # Convert registered schedulers to a map
    registered_map = 
      Enum.reduce(registered_schedulers, %{}, fn %{module: module, enabled: enabled, config: config}, acc ->
        key = module |> to_string() |> String.split(".") |> List.last() |> Macro.underscore() |> String.to_atom()
        Map.put(acc, key, %{module: module, enabled: enabled, config: config})
      end)
    
    scheduler_data = %{
      configured: configured_schedulers,
      registered: registered_map
    }
    
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(200, Jason.encode!(scheduler_data))
  end
  
  # Cache information endpoint
  get "/cache" do
    # Get configured TTLs
    cache_ttls = Timings.cache_ttls()
    
    # Get cache stats
    cache_stats = 
      case Cachex.stats(:wanderer_notifier_cache) do
        {:ok, stats} -> stats
        _ -> %{error: "Could not get cache stats"}
      end
    
    # Get counts for different categories
    systems = 
      case CacheRepo.get("map:systems") do
        systems when is_list(systems) -> length(systems)
        _ -> 0
      end
    
    characters_count = 
      case CacheRepo.get("map:characters") do
        chars when is_list(chars) -> length(chars)
        _ -> 0
      end
      
    cache_data = %{
      configuration: cache_ttls,
      statistics: cache_stats,
      counts: %{
        systems: systems,
        characters: characters_count,
        total: cache_stats[:size] || 0
      }
    }
    
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(200, Jason.encode!(cache_data))
  end
  
  # Execute all schedulers endpoint
  post "/schedulers/execute" do
    # Execute all registered schedulers
    SchedulerRegistry.execute_all()
    
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(200, Jason.encode!(%{status: "ok", message: "All schedulers triggered for execution"}))
  end
  
  # Catch-all route
  match _ do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(404, Jason.encode!(%{error: "Debug endpoint not found"}))
  end
  
  # Helper functions
  
  defp get_start_time do
    case :application.get_key(:wanderer_notifier, :start_time) do
      {:ok, start_time} -> 
        start_time
        |> :calendar.now_to_datetime()
        |> NaiveDateTime.from_erl!()
        |> NaiveDateTime.to_string()
      _ -> 
        "Unknown"
    end
  end
  
  defp get_uptime_string do
    case :application.get_key(:wanderer_notifier, :start_time) do
      {:ok, {megasec, sec, _microsec}} ->
        start_time = megasec * 1_000_000 + sec
        current_time = :erlang.system_time(:second)
        uptime_seconds = current_time - start_time
        
        days = div(uptime_seconds, 86400)
        hours = div(rem(uptime_seconds, 86400), 3600)
        minutes = div(rem(uptime_seconds, 3600), 60)
        seconds = rem(uptime_seconds, 60)
        
        "#{days}d #{hours}h #{minutes}m #{seconds}s"
      _ ->
        "Unknown"
    end
  end
  
  defp bytes_to_mb(bytes) do
    (bytes / 1_048_576) |> Float.round(2)
  end
  
  # No longer needed as we're using Plug.Router's send_resp
end