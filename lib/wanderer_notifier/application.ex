defmodule WandererNotifier.Application do
  @moduledoc """
  The WandererNotifier OTP application.
  """
  use Application
  require Logger
  alias WandererNotifier.Config
  alias WandererNotifier.Cache.Repository, as: CacheRepo
  alias WandererNotifier.NotifierFactory
  alias WandererNotifier.Helpers.CacheHelpers
  alias WandererNotifier.CorpTools.Client, as: CorpToolsClient
  alias WandererNotifier.CorpTools.ChartScheduler

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

    Logger.info("License Key configured: #{if license_key && license_key != "", do: "Yes", else: "No"}")
    Logger.info("License Manager URL: #{license_manager_url || "Not configured"}")
    Logger.info("Bot API Token: #{if env == :prod, do: "Using production token", else: "Using environment token"}")

    # Check EVE Corp Tools API configuration
    corp_tools_api_url = Config.corp_tools_api_url()
    corp_tools_api_token = Config.corp_tools_api_token()

    if corp_tools_api_url && corp_tools_api_token do

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

      # Add the chart scheduler to the children list if EVE Corp Tools API is configured
      children = get_children()
      children = children ++ [
        # Start the chart scheduler
        {ChartScheduler, [interval: get_chart_scheduler_interval()]}
      ]

      # Start the supervisor with the updated children list
      Supervisor.start_link(children, strategy: :one_for_one, name: WandererNotifier.Supervisor)
    else
      Logger.warning("EVE Corp Tools API not fully configured. URL: #{corp_tools_api_url || "Not set"}, Token: #{if corp_tools_api_token, do: "Set", else: "Not set"}")

      # Start the supervisor with the default children list
      Supervisor.start_link(get_children(), strategy: :one_for_one, name: WandererNotifier.Supervisor)
    end
  end

  # Handle license validation asynchronously
  def handle_info(:validate_license, _state) do
    try do
      # Use a timeout to prevent blocking
      case GenServer.call(WandererNotifier.License, :validate, 3000) do
        license_status when is_map(license_status) ->
          if license_status.valid do
            Logger.info("License validation successful - License is valid")
          else
            error_message = license_status.error_message || "Unknown license error"
            Logger.error("License validation failed: #{error_message}")
            Logger.warning("The application will continue to run in limited mode")
          end
        _ ->
          Logger.error("License validation returned unexpected result")
      end
    rescue
      e ->
        Logger.error("License validation error: #{inspect(e)}")
        Logger.warning("The application will continue to run in limited mode")
    catch
      :exit, {:timeout, _} ->
        Logger.error("License validation timed out")
        Logger.warning("The application will continue to run in limited mode")
      type, reason ->
        Logger.error("License validation error: #{inspect(type)}, #{inspect(reason)}")
        Logger.warning("The application will continue to run in limited mode")
    end

    {:noreply, nil}
  end

  # This is not part of the Application behaviour, but we handle it for the test notification
  def handle_info(:send_test_notification, _state) do
    Logger.info("Sending test notification...")
    NotifierFactory.notify(:send_message, ["Test notification from WandererNotifier. If you see this, notifications are working!"])
    {:noreply, nil}
  end

  # Check cache status
  def handle_info(:check_cache_status, _state) do
    Logger.info("Checking cache status...")

    # Check if cache is available
    cache_available = case Cachex.stats(:wanderer_notifier_cache) do
      {:ok, _stats} -> true
      _ -> false
    end

    Logger.info("Cache available: #{cache_available}")

    # Get systems count
    systems = get_tracked_systems()
    Logger.info("Cache status - Systems: #{length(systems)}")

    # Get characters count
    characters = CacheRepo.get("map:characters") || []
    Logger.info("Cache status - Characters: #{length(characters)}")

    {:noreply, nil}
  end

  # Handle retry for EVE Corp Tools API health check
  def handle_info(:retry_corp_tools_health_check, _state) do
    Logger.info("Retrying EVE Corp Tools API health check...")

    case CorpToolsClient.health_check() do
      :ok ->
        Logger.info("EVE Corp Tools API health check passed on retry")
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

  @doc """
  Validates the license and bot assignment.
  If the license is invalid, logs an error but allows the application to continue with limited functionality.
  """
  def validate_license_and_bot_assignment do
    Logger.info("Starting license validation process...")
    license_status = WandererNotifier.License.validate()

    if license_status.valid do
      Logger.info("License validation successful - License is valid")
      :ok
    else
      error_message = license_status.error_message || "Unknown license error"
      Logger.error("License validation failed: #{error_message}")
      Logger.warning("The application will continue to run in limited mode")
      :ok
    end
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

  # Helper function to get the chart scheduler interval
  defp get_chart_scheduler_interval do
    # Default is 24 hours (in milliseconds)
    default_interval = 24 * 60 * 60 * 1000

    # Try to get the interval from the environment variable
    case System.get_env("CHART_SCHEDULER_INTERVAL_MS") do
      nil -> default_interval
      value ->
        case Integer.parse(value) do
          {interval, _} when interval > 0 -> interval
          _ -> default_interval
        end
    end
  end

  # Helper function to get the children list
  defp get_children do
    [
      # Start the License Manager
      {WandererNotifier.License, []},

      # Start the Stats tracking service
      {WandererNotifier.Stats, []},

      # Start the Cache Repository
      {CacheRepo, []},

      # Start the main service (which starts the WebSocket)
      {WandererNotifier.Service, []},

      # Start the Web Server
      {WandererNotifier.Web.Server, []},

      # Start the Activity Chart Scheduler if map tools are enabled
      if Config.map_tools_enabled?() do
        # Get the chart scheduler interval
        interval = get_chart_scheduler_interval()
        
        # Start the Activity Chart Scheduler
        {WandererNotifier.CorpTools.ActivityChartScheduler, [interval: interval]}
      end
    ]
    |> Enum.filter(& &1)
  end

  # Helper function to start watchers for frontend asset rebuilding
  defp start_watchers do
    watchers = Application.get_env(:wanderer_notifier, :watchers, [])
    
    Enum.each(watchers, fn {cmd, args} ->
      Logger.info("Starting watcher: #{cmd} with args: #{inspect(args)}")
      
      # Process each argument to extract cd path
      {cmd_args, cd_path} = extract_watcher_args(args)
      
      cmd_str = to_string(cmd)
      
      Logger.info("Processed watcher command: #{cmd_str} #{inspect(cmd_args)}, cd: #{inspect(cd_path)}")
      
      Task.start(fn ->
        try do
          # Create options for System.cmd
          system_opts = []
          system_opts = if cd_path, do: [cd: cd_path] ++ system_opts, else: system_opts
          
          # Add stdout redirection
          system_opts = [into: IO.stream(:stdio, :line)] ++ system_opts
          
          Logger.info("Running command: #{cmd_str} #{Enum.join(cmd_args, " ")} with options: #{inspect(system_opts)}")
          
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
        {:cd, path} -> {acc_args, path}  # Found cd option
        arg when is_binary(arg) -> {acc_args ++ [arg], acc_cd}  # Normal string arg
        arg -> {acc_args, acc_cd}  # Ignore any other types
      end
    end)
  end
end
