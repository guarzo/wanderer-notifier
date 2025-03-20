defmodule WandererNotifier.Application do
  @moduledoc """
  The WandererNotifier OTP application.
  """
  use Application
  require Logger

  alias WandererNotifier.Core.Config
  alias WandererNotifier.Data.Cache.Repository, as: CacheRepo
  alias WandererNotifier.Notifiers.Factory, as: NotifierFactory
  alias WandererNotifier.Helpers.CacheHelpers
  alias WandererNotifier.CorpTools.CorpToolsClient

  @impl true
  def start(_type, _args) do
    Logger.info("Starting WandererNotifier...")

    # Get the environment from system environment variable
    env = System.get_env("MIX_ENV", "prod") |> String.to_atom()

    # Start ExSync in development mode
    if env == :dev do
      Logger.info("Starting ExSync for hot code reloading")
      # Handle the case where ExSync is not available
      case Application.ensure_all_started(:exsync) do
        {:ok, _} -> Logger.info("ExSync started successfully")
        {:error, _} -> Logger.warning("ExSync not available, continuing without hot reloading")
      end

      # Start watchers for frontend asset rebuilding in development
      start_watchers()
    end

    # Set the environment in the application configuration
    Application.put_env(:wanderer_notifier, :env, env)

    Logger.info("Starting WandererNotifier application...")
    Logger.info("Environment: #{env}")

    # Log configuration details
    license_key = Config.license_key()
    license_manager_url = Config.license_manager_api_url()
    # Bot API token is determined by the environment

    # Log at debug level since this is mostly informational
    Logger.debug(
      "License Key configured: #{if license_key && license_key != "", do: "Yes", else: "No"}"
    )

    Logger.debug("License Manager URL: #{license_manager_url || "Not configured"}")

    Logger.debug(
      "Bot API Token: #{if env == :prod, do: "Using production token", else: "Using environment token"}"
    )

    # Check EVE Corp Tools API configuration
    corp_tools_api_url = Config.corp_tools_api_url()
    corp_tools_api_token = Config.corp_tools_api_token()

    if corp_tools_api_url && corp_tools_api_token && Config.corp_tools_enabled?() do
      # Perform health check
      Task.start(fn ->
        # Add a small delay to ensure the application is fully started
        Process.sleep(2000)

        case CorpToolsClient.health_check() do
          :ok ->
            # Schedule periodic health checks
            schedule_corp_tools_health_check()

          {:error, :connection_refused} ->
            Logger.warning("EVE Corp Tools API connection refused. Will retry in 30 seconds.")
            # Schedule a retry after 30 seconds
            Process.send_after(self(), :retry_corp_tools_health_check, 30_000)

          {:error, reason} ->
            Logger.error("EVE Corp Tools API health check failed: #{inspect(reason)}")
            # Schedule a retry after 60 seconds
            Process.send_after(self(), :retry_corp_tools_health_check, 60_000)
        end
      end)
    end

    # Start the supervisor with all children
    result = Supervisor.start_link(get_children(), strategy: :one_for_one, name: WandererNotifier.Supervisor)
    
    # Send startup message after a short delay to ensure all services are started
    Task.start(fn ->
      # Wait a bit for everything to start up
      Process.sleep(2000)
      send_startup_message()
    end)
    
    result
  end

  # Send a rich startup message with system information
  defp send_startup_message do
    Logger.info("Sending startup message...")
    
    # Get license information
    license_status = WandererNotifier.Core.License.status()
    license_valid = if license_status.valid, do: "Valid", else: "Invalid"
    license_type = if license_status.premium, do: "Premium", else: "Standard"
    
    # Get feature information
    features = WandererNotifier.Core.Features.get_feature_status()
    
    # Get tracking information
    systems = get_tracked_systems()
    characters = CacheRepo.get("map:characters") || []
    
    # Format message
    title = "WandererNotifier Started"
    description = "The notification service has started successfully."
    
    # Build fields for the embed
    fields = [
      %{name: "License Status", value: "#{license_valid} (#{license_type})", inline: true},
      %{name: "Tracked Systems", value: "#{length(systems)}", inline: true},
      %{name: "Tracked Characters", value: "#{length(characters)}", inline: true}
    ]
    
    # Add WebSocket status
    websocket_status = get_websocket_status()
    fields = fields ++ [%{name: "WebSocket Status", value: websocket_status, inline: true}]
    
    # Add notification counts
    stats = WandererNotifier.Core.Stats.get_stats()
    notifications = stats.notifications
    fields = fields ++ [
      %{name: "Notifications Sent", value: format_notification_counts(notifications), inline: false}
    ]
    
    # Add feature status section
    enabled_features = format_feature_status(features)
    fields = fields ++ [%{name: "Enabled Features", value: enabled_features, inline: false}]
    
    # Send the rich embed notification
    NotifierFactory.notify(:send_embed, [
      title,
      description,
      nil,  # No URL
      0x3498DB,  # Blue color
      :general   # Send to general channel
    ])
  end
  
  # Helper to get WebSocket connection status
  defp get_websocket_status do
    stats = WandererNotifier.Core.Stats.get_stats()
    
    if stats.websocket.connected do
      last_message = stats.websocket.last_message
      
      if last_message do
        time_diff = DateTime.diff(DateTime.utc_now(), last_message, :second)
        
        cond do
          time_diff < 60 -> "Connected (active)"
          time_diff < 300 -> "Connected (last message #{div(time_diff, 60)} min ago)"
          true -> "Connected (inactive for #{div(time_diff, 60)} min)"
        end
      else
        "Connected (no messages yet)"
      end
    else
      reconnects = Map.get(stats.websocket, :reconnects, 0)
      
      if reconnects > 0 do
        "Disconnected (#{reconnects} reconnect attempts)"
      else
        "Disconnected"
      end
    end
  end
  
  # Helper to format notification counts
  defp format_notification_counts(notifications) do
    total = Map.get(notifications, :total, 0)
    kills = Map.get(notifications, :kills, 0)
    systems = Map.get(notifications, :systems, 0)
    characters = Map.get(notifications, :characters, 0)
    
    "Total: #{total} (Kills: #{kills}, Systems: #{systems}, Characters: #{characters})"
  end
  
  # Helper to format feature status
  defp format_feature_status(features) do
    enabled = Enum.filter(features, fn {_feature, enabled} -> enabled end)
    |> Enum.map(fn {feature, _} -> 
      # Convert atom to string and format nicely
      feature
      |> Atom.to_string()
      |> String.replace("_", " ")
      |> String.split()
      |> Enum.map(&String.capitalize/1)
      |> Enum.join(" ")
    end)
    
    if enabled == [] do
      "No features enabled"
    else
      Enum.join(enabled, ", ")
    end
  end


  # This is not part of the Application behaviour, but we handle it for the test notification
  def handle_info(:send_test_notification, _state) do
    Logger.info("Sending test notification...")

    NotifierFactory.notify(:send_message, [
      "Test notification from WandererNotifier. If you see this, notifications are working!"
    ])

    {:noreply, nil}
  end

  # Check cache status
  def handle_info(:check_cache_status, _state) do
    Logger.debug("Checking cache status...")

    # Check if cache is available
    cache_available =
      case Cachex.stats(:wanderer_notifier_cache) do
        {:ok, _stats} -> true
        _ -> false
      end

    # Only log at INFO level if there's a problem
    if cache_available do
      Logger.debug("Cache is available")
    else
      Logger.warning("Cache is NOT available")
    end

    # Get systems count
    systems = get_tracked_systems()
    characters = CacheRepo.get("map:characters") || []
    Logger.debug("Cache status - Systems: #{length(systems)}, Characters: #{length(characters)}")

    {:noreply, nil}
  end

  # Handle retry for EVE Corp Tools API health check
  def handle_info(:retry_corp_tools_health_check, _state) do
    Logger.debug("Retrying EVE Corp Tools API health check...")

    case CorpToolsClient.health_check() do
      :ok ->
        Logger.debug("EVE Corp Tools API health check passed on retry")
        # Schedule periodic health checks
        schedule_corp_tools_health_check()

      {:error, :connection_refused} ->
        Logger.warning("EVE Corp Tools API connection still refused. Will retry in 60 seconds.")
        # Schedule another retry after 60 seconds
        Process.send_after(self(), :retry_corp_tools_health_check, 60_000)

      {:error, reason} ->
        Logger.error("EVE Corp Tools API health check failed on retry: #{inspect(reason)}")
        # Schedule another retry after 120 seconds
        Process.send_after(self(), :retry_corp_tools_health_check, 120_000)
    end

    {:noreply, nil}
  end

  # Handle periodic health check for EVE Corp Tools API
  def handle_info(:corp_tools_health_check, _state) do
    Logger.debug("Performing periodic EVE Corp Tools API health check...")

    case CorpToolsClient.health_check() do
      :ok ->
        Logger.debug("Periodic EVE Corp Tools API health check passed")
        # Schedule the next health check
        schedule_corp_tools_health_check()

      {:error, reason} ->
        Logger.warning("Periodic EVE Corp Tools API health check failed: #{inspect(reason)}")
        # Schedule a retry sooner
        Process.send_after(self(), :retry_corp_tools_health_check, 30_000)
    end

    {:noreply, nil}
  end

  # Schedule periodic health checks for EVE Corp Tools API
  defp schedule_corp_tools_health_check do
    # Schedule a health check every 5 minutes
    Process.send_after(self(), :corp_tools_health_check, 5 * 60 * 1000)
  end


  defp get_tracked_systems do
    CacheHelpers.get_tracked_systems()
  end

  @doc """
  Called when a file is changed and code is reloaded in development.
  This replaces the functionality in DevCallbacks.
  """
  def reload(modules) do
    Logger.info("Reloaded modules: #{inspect(modules)}")
    :ok
  end

  # Helper function to get the children list
  defp get_children do
    [
      # Start the License Manager
      {WandererNotifier.Core.License, []},

      # Start the Stats tracking service
      {WandererNotifier.Core.Stats, []},

      # Start the Cache Repository
      {WandererNotifier.Data.Cache.Repository, []},

      # Start the Chart Service Manager (if enabled)
      {WandererNotifier.ChartService.ChartServiceManager, []},

      # Start the main service (which starts the WebSocket)
      {WandererNotifier.Services.Service, []},

      # Start the Maintenance service
      {WandererNotifier.Services.Maintenance, []},

      # Start the Web Server
      {WandererNotifier.Web.Server, []},

      # Start the Scheduler Supervisor
      {WandererNotifier.Schedulers.Supervisor, []}
    ]
  end

  # Helper function to start watchers for frontend asset rebuilding
  defp start_watchers do
    watchers = Application.get_env(:wanderer_notifier, :watchers, [])

    Enum.each(watchers, fn {cmd, args} ->
      Logger.info("Starting watcher: #{cmd} with args: #{inspect(args)}")

      # Process each argument to extract cd path
      {cmd_args, cd_path} = extract_watcher_args(args)

      cmd_str = to_string(cmd)

      Logger.info(
        "Processed watcher command: #{cmd_str} #{inspect(cmd_args)}, cd: #{inspect(cd_path)}"
      )

      Task.start(fn ->
        try do
          # Create options for System.cmd
          system_opts = []
          system_opts = if cd_path, do: [cd: cd_path] ++ system_opts, else: system_opts

          # Add stdout redirection
          system_opts = [into: IO.stream(:stdio, :line)] ++ system_opts

          Logger.info(
            "Running command: #{cmd_str} #{Enum.join(cmd_args, " ")} with options: #{inspect(system_opts)}"
          )

          # Start the watcher with correctly formatted options
          {_output, status} = System.cmd(cmd_str, cmd_args, system_opts)

          if status == 0 do
            Logger.info("Watcher #{cmd} completed successfully")
          else
            Logger.error("Watcher #{cmd} exited with status #{status}")
          end
        rescue
          e ->
            Logger.error("Error starting watcher: #{inspect(e)}")
            Logger.error(Exception.format_stacktrace())
        end
      end)
    end)
  end

  # Extract watcher args and cd path
  defp extract_watcher_args(args) do
    Enum.reduce(args, {[], nil}, fn arg, {acc_args, acc_cd} ->
      case arg do
        # Found cd option
        {:cd, path} -> {acc_args, path}
        # Normal string arg
        arg when is_binary(arg) -> {acc_args ++ [arg], acc_cd}
        # Ignore any other types
        _arg -> {acc_args, acc_cd}
      end
    end)
  end
end
