defmodule WandererNotifier.NoopConsumer do
  @moduledoc """
  A minimal Discord consumer that ignores all events.
  Used during application startup and testing to satisfy Nostrum requirements.
  """
  use Nostrum.Consumer

  @impl true
  def handle_event(_event), do: :ok
end

defmodule WandererNotifier.Application do
  @moduledoc """
  The WandererNotifier OTP application.
  """
  use Application
  require Logger

  alias WandererNotifier.Core.Config
  alias WandererNotifier.Core.License
  alias WandererNotifier.Core.Stats
  alias WandererNotifier.Core.Features
  alias WandererNotifier.Data.Cache.Repository, as: CacheRepo
  alias WandererNotifier.Notifiers.Factory, as: NotifierFactory
  alias WandererNotifier.Helpers.CacheHelpers

  @impl true
  def start(_type, _args) do
    if should_skip_app_start?() do
      Logger.info("Skipping full application start due to test environment configuration")
      start_minimal_test_components()
    else
      start_full_application()
    end
  end

  # Start the application with all components
  defp start_full_application do
    Logger.info("Starting WandererNotifier...")

    # Get the environment from system environment variable
    env = System.get_env("MIX_ENV", "prod") |> String.to_atom()

    # Handle development-specific setup
    maybe_start_dev_tools(env)

    # Set the environment in the application configuration
    Application.put_env(:wanderer_notifier, :env, env)

    # Log application startup information
    log_startup_info(env)

    # Start the supervisor and schedule startup message
    start_supervisor_and_notify()
  end

  # Start development tools if in dev environment
  defp maybe_start_dev_tools(:dev) do
    Logger.info("Starting ExSync for hot code reloading")

    case Application.ensure_all_started(:exsync) do
      {:ok, _} -> Logger.info("ExSync started successfully")
      {:error, _} -> Logger.warning("ExSync not available, continuing without hot reloading")
    end

    # Start watchers for frontend asset rebuilding in development
    start_watchers()
  end

  defp maybe_start_dev_tools(_other_env), do: :ok

  # Log application startup information
  defp log_startup_info(env) do
    Logger.info("Starting WandererNotifier application...")
    Logger.info("Environment: #{env}")

    # Log configuration details
    license_key = Config.license_key()

    Logger.debug(
      "License Key configured: #{if license_key && license_key != "", do: "Yes", else: "No"}"
    )

    Logger.debug(
      "License Manager: #{if Config.license_manager_api_url(), do: "Configured", else: "Not configured"}"
    )

    Logger.debug(
      "Bot API Token: #{if env == :prod, do: "Using production token", else: "Using environment token"}"
    )

    # Log persistence status
    Logger.info(
      "Database persistence: #{if persistence_enabled?(), do: "Enabled", else: "Disabled"}"
    )
  end

  # Start supervisor and schedule startup notification
  defp start_supervisor_and_notify do
    # Start the supervisor with all children including Nostrum.Consumer
    result =
      Supervisor.start_link(get_children(),
        strategy: :one_for_one,
        name: WandererNotifier.Supervisor
      )

    # Send startup message after a short delay to ensure all services are started
    Task.start(fn ->
      Process.sleep(2000)
      send_startup_message()
    end)

    result
  end

  defp should_skip_app_start? do
    disable_start = System.get_env("DISABLE_APP_START") == "true"
    app_env_disable = Application.get_env(:wanderer_notifier, :start_application) == false

    test_env_disable =
      Application.get_env(:wanderer_notifier, :start_external_connections) == false

    disable_start || app_env_disable || test_env_disable
  end

  defp send_startup_message do
    Logger.info("Sending startup message...")

    license_status =
      try do
        License.status()
      rescue
        e ->
          Logger.error("Error getting license status for startup message: #{inspect(e)}")
          %{valid: false, error_message: "Error retrieving license status"}
      catch
        type, error ->
          Logger.error("Error getting license status: #{inspect(type)}, #{inspect(error)}")
          %{valid: false, error_message: "Error retrieving license status"}
      end

    systems = get_tracked_systems()
    characters = CacheRepo.get("map:characters") || []
    features_status = Features.get_feature_status()
    stats = Stats.get_stats()
    title = "WandererNotifier Started"
    description = "The notification service has started successfully."

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

    discord_embed =
      WandererNotifier.Notifiers.StructuredFormatter.to_discord_format(generic_notification)

    NotifierFactory.notify(:send_discord_embed, [discord_embed, :general])
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

  defp get_children do
    children = [
      {WandererNotifier.NoopConsumer, []},
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

    # Conditionally add Postgres repo to supervision tree
    children =
      if persistence_enabled?() do
        Logger.info("Persistence enabled - starting database connection")
        children ++ [WandererNotifier.Repo]
      else
        children
      end

    children
  end

  # Check if persistence feature is enabled
  defp persistence_enabled? do
    Application.get_env(:wanderer_notifier, :persistence, [])
    |> Keyword.get(:enabled, false)
  end

  defp start_watchers do
    watchers = Application.get_env(:wanderer_notifier, :watchers, [])

    Enum.each(watchers, fn {cmd, args} ->
      Logger.info("Starting watcher: #{cmd} with args: #{inspect(args)}")
      {cmd_args, cd_path} = extract_watcher_args(args)
      cmd_str = to_string(cmd)

      Logger.info(
        "Processed watcher command: #{cmd_str} #{Enum.join(cmd_args, " ")} with options: #{inspect(cmd_args)}, cd: #{inspect(cd_path)}"
      )

      Task.start(fn ->
        try do
          system_opts = []
          system_opts = if cd_path, do: [cd: cd_path] ++ system_opts, else: system_opts
          system_opts = [into: IO.stream(:stdio, :line)] ++ system_opts

          Logger.info(
            "Running command: #{cmd_str} #{Enum.join(cmd_args, " ")} with options: #{inspect(system_opts)}"
          )

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

  defp extract_watcher_args(args) do
    Enum.reduce(args, {[], nil}, fn arg, {acc_args, acc_cd} ->
      case arg do
        {:cd, path} -> {acc_args, path}
        arg when is_binary(arg) -> {acc_args ++ [arg], acc_cd}
        _arg -> {acc_args, acc_cd}
      end
    end)
  end

  defp start_minimal_test_components do
    children = [
      # Only add essential components for testing
      {Registry, keys: :unique, name: WandererNotifier.Registry},
      {Cachex,
       name: Application.get_env(:wanderer_notifier, :cache_name, :wanderer_notifier_cache)}
    ]

    opts = [strategy: :one_for_one, name: WandererNotifier.TestSupervisor]
    Supervisor.start_link(children, opts)
  end
end
