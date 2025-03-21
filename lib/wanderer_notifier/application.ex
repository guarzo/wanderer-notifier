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

    # Only log if certain features are configured, not any actual sensitive values
    Logger.debug(
      "License Key configured: #{if license_key && license_key != "", do: "Yes", else: "No"}"
    )

    Logger.debug(
      "License Manager: #{if Config.license_manager_api_url(), do: "Configured", else: "Not configured"}"
    )

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
    result =
      Supervisor.start_link(get_children(),
        strategy: :one_for_one,
        name: WandererNotifier.Supervisor
      )

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

    # Get license information safely
    license_status =
      try do
        WandererNotifier.Core.License.status()
      rescue
        e ->
          Logger.error("Error getting license status for startup message: #{inspect(e)}")
          %{valid: false, error_message: "Error retrieving license status"}
      catch
        type, error ->
          Logger.error("Error getting license status: #{inspect(type)}, #{inspect(error)}")
          %{valid: false, error_message: "Error retrieving license status"}
      end

    # Get tracking information
    systems = get_tracked_systems()
    characters = CacheRepo.get("map:characters") || []

    # Get feature information
    features_status = WandererNotifier.Core.Features.get_feature_status()

    # Get stats
    stats = WandererNotifier.Core.Stats.get_stats()

    # Use the new structured formatter
    title = "WandererNotifier Started"
    description = "The notification service has started successfully."

    # Create a structured notification using our formatter
    generic_notification =
      WandererNotifier.Notifiers.StructuredFormatter.format_system_status_message(
        title,
        description,
        stats,
        nil,
        features_status,
        license_status,
        length(systems),
        length(characters)
      )

    # Convert to Discord format
    discord_embed =
      WandererNotifier.Notifiers.StructuredFormatter.to_discord_format(generic_notification)

    # Send the notification using the Discord notifier through the factory
    NotifierFactory.notify(:send_discord_embed, [discord_embed, :general])
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

      # Start the Deduplication Helper
      {WandererNotifier.Helpers.DeduplicationHelper, []},

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
        "Processed watcher command: #{cmd_str} #{Enum.join(cmd_args, " ")} with options: #{inspect(cmd_args)}, cd: #{inspect(cd_path)}"
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
