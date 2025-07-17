defmodule WandererNotifier.Application do
  @moduledoc """
  Application module for WandererNotifier.
  Handles application startup and environment configuration.
  """

  use Application

  @doc """
  Starts the WandererNotifier application.
  """
  def start(_type, _args) do
    # Ensure critical configuration exists to prevent startup failures
    ensure_critical_configuration()

    # Set application start time for uptime calculation
    Application.put_env(:wanderer_notifier, :start_time, System.monotonic_time(:second))

    # Validate configuration on startup
    validate_configuration()

    WandererNotifier.Logger.Logger.startup_info("Starting WandererNotifier")

    # Log all environment variables to help diagnose config issues
    log_environment_variables()

    # Log scheduler configuration
    schedulers_enabled = Application.get_env(:wanderer_notifier, :schedulers_enabled, false)
    WandererNotifier.Logger.Logger.startup_info("Schedulers enabled: #{schedulers_enabled}")

    base_children = [
      # Add Task.Supervisor first to prevent initialization races
      {Task.Supervisor, name: WandererNotifier.TaskSupervisor},
      # Add Registry for cache process naming
      {Registry, keys: :unique, name: WandererNotifier.Cache.Registry},
      # Add Registry for SSE client naming
      {Registry, keys: :unique, name: WandererNotifier.Registry},
      create_cache_child_spec(),
      # Add persistent storage modules before Discord consumer
      {WandererNotifier.PersistentValues, []},
      {WandererNotifier.CommandLog, []},
      # Enhanced Discord consumer that handles slash commands
      {WandererNotifier.Discord.Consumer, []},
      {WandererNotifier.Core.Stats, []},
      {WandererNotifier.License.Service, []},
      {WandererNotifier.Core.Application.Service, []},
      # Phoenix PubSub for real-time communication
      {Phoenix.PubSub, name: WandererNotifier.PubSub},
      # Phoenix endpoint for API and WebSocket functionality  
      {WandererNotifierWeb.Endpoint, []}
    ]

    # Add cache metrics and performance monitoring (skip in test)
    cache_monitoring_children =
      if get_env() != :test do
        [
          {WandererNotifier.Cache.Metrics, []},
          {WandererNotifier.Cache.PerformanceMonitor, []},
          {WandererNotifier.Cache.Warmer, []},
          {WandererNotifier.Cache.Versioning, []},
          {WandererNotifier.Cache.Analytics, []}
        ]
      else
        []
      end

    # Add real-time processing integration (Sprint 3) (skip in test)
    realtime_children =
      if get_env() != :test do
        [{WandererNotifier.Realtime.Integration, []}]
      else
        []
      end

    # Add Killmail processing pipeline - always enabled
    killmail_children = [{WandererNotifier.Killmail.Supervisor, []}]

    # Add SSE supervisor - always enabled for system and character tracking
    sse_children = [{WandererNotifier.Map.SSESupervisor, []}]

    # Add scheduler supervisor last to ensure all dependencies are started
    scheduler_children = [{WandererNotifier.Schedulers.Supervisor, []}]

    children =
      base_children ++
        cache_monitoring_children ++
        realtime_children ++ killmail_children ++ sse_children ++ scheduler_children

    WandererNotifier.Logger.Logger.startup_info("Starting children: #{inspect(children)}")

    opts = [strategy: :one_for_one, name: WandererNotifier.Supervisor]
    result = Supervisor.start_link(children, opts)

    # Initialize cache metrics and performance monitoring
    initialize_cache_monitoring()

    # Initialize SSE clients after supervisors are started (skip in test mode)
    if get_env() != :test do
      initialize_sse_clients()
    end

    result
  end

  # Initialize cache metrics and performance monitoring
  defp initialize_cache_monitoring do
    # Skip cache monitoring initialization in test environment
    if get_env() == :test do
      WandererNotifier.Logger.Logger.startup_info(
        "Skipping cache monitoring initialization in test environment"
      )
    else
      try do
        # Initialize cache metrics telemetry
        WandererNotifier.Cache.Metrics.init()

        # Start performance monitoring
        WandererNotifier.Cache.PerformanceMonitor.start_monitoring()

        # Cache warming disabled for startup performance
        # WandererNotifier.Cache.Warmer.start_warming()

        # Initialize version manager
        WandererNotifier.Cache.VersionManager.initialize()

        # Start cache analytics collection
        WandererNotifier.Cache.Analytics.start_collection()

        WandererNotifier.Logger.Logger.startup_info(
          "Cache performance monitoring, warming, versioning, and analytics initialized"
        )
      rescue
        error ->
          WandererNotifier.Logger.Logger.startup_error("Failed to initialize cache monitoring",
            error: Exception.message(error)
          )
      end
    end
  end

  # Initialize SSE clients with proper error handling
  defp initialize_sse_clients do
    # Schedule SSE client initialization to happen after supervision tree is fully started
    # This prevents race conditions during application startup
    Task.start(fn ->
      # Wait for supervision tree to be fully started by checking if supervisor is alive
      wait_for_supervisor_startup()

      try do
        WandererNotifier.Map.SSESupervisor.initialize_sse_clients()
      rescue
        error ->
          WandererNotifier.Logger.Logger.startup_error("Failed to initialize SSE clients",
            error: Exception.message(error)
          )
      end
    end)

    :ok
  end

  # Wait for the supervision tree to be fully started
  defp wait_for_supervisor_startup do
    case Process.whereis(WandererNotifier.Map.SSESupervisor) do
      nil ->
        # Supervisor not started yet, wait a bit and retry
        Process.sleep(100)
        wait_for_supervisor_startup()

      pid when is_pid(pid) ->
        # Supervisor is running, check if it's responsive
        case Supervisor.which_children(pid) do
          children when is_list(children) ->
            # Supervisor is responsive and ready
            :ok

          _ ->
            # Supervisor exists but not responsive, wait and retry
            Process.sleep(100)
            wait_for_supervisor_startup()
        end
    end
  rescue
    _ ->
      # If there's an error, wait a bit and try again
      Process.sleep(100)
      wait_for_supervisor_startup()
  end

  # Validates configuration on startup and logs any issues
  defp validate_configuration do
    environment = get_env()

    case WandererNotifier.Config.Validator.validate_from_env(environment) do
      :ok ->
        WandererNotifier.Logger.Logger.startup_info("Configuration validation: PASSED")

      {:error, errors} ->
        WandererNotifier.Config.Validator.log_validation_errors(errors)

        summary = WandererNotifier.Config.Validator.validation_summary(errors)

        WandererNotifier.Logger.Logger.startup_info(
          "Configuration validation summary: #{summary.total_errors} errors " <>
            "(#{summary.critical_errors} critical, #{summary.warnings} warnings)"
        )

        # Fail startup on critical errors in production
        if environment == :prod and summary.critical_errors > 0 do
          error_details = WandererNotifier.Config.Validator.format_errors(errors)

          raise """
          Critical configuration errors detected. Application cannot start.

          #{error_details}

          Please fix these configuration issues and restart the application.
          """
        end
    end
  end

  # Ensures critical configuration exists to prevent startup failures
  defp ensure_critical_configuration do
    # Ensure config_module is set
    if Application.get_env(:wanderer_notifier, :config_module) == nil do
      Application.put_env(:wanderer_notifier, :config_module, WandererNotifier.Config)
    end

    # Ensure features is set
    if Application.get_env(:wanderer_notifier, :features) == nil do
      Application.put_env(:wanderer_notifier, :features, [])
    end

    # Ensure cache name is set
    if Application.get_env(:wanderer_notifier, :cache_name) == nil do
      Application.put_env(
        :wanderer_notifier,
        :cache_name,
        WandererNotifier.Cache.Config.default_cache_name()
      )
    end

    # Ensure schedulers are enabled
    if Application.get_env(:wanderer_notifier, :schedulers_enabled) == nil do
      Application.put_env(:wanderer_notifier, :schedulers_enabled, true)
    end

    # Discord Application ID is only required if slash commands are enabled
    # We'll validate this later when CommandRegistrar actually tries to register commands
  end

  defp log_env_variable(key, sensitive_keys) do
    case System.get_env(key) do
      nil ->
        :ok

      value ->
        # Redact sensitive values
        safe_value = if key in sensitive_keys, do: "[REDACTED]", else: value
        WandererNotifier.Logger.Logger.startup_info("  #{key}: #{safe_value}")
    end
  end

  @doc """
  Logs all environment variables to help diagnose configuration issues.
  Sensitive values are redacted.
  """
  def log_environment_variables do
    WandererNotifier.Logger.Logger.startup_info("Environment variables at startup:")

    sensitive_keys = ~w(
      DISCORD_BOT_TOKEN
      MAP_API_KEY
      NOTIFIER_API_TOKEN
      LICENSE_KEY
    )

    # List of environment variables we care about
    relevant_keys = ~w(
      DISCORD_BOT_TOKEN
      DISCORD_APPLICATION_ID
      DISCORD_CHANNEL_ID
      LICENSE_KEY
      MAP_URL
      MAP_NAME
      MAP_API_KEY
      NOTIFIER_API_TOKEN
      WEBSOCKET_URL
      WANDERER_KILLS_URL
      PORT
      HOST
      NOTIFICATIONS_ENABLED
      KILL_NOTIFICATIONS_ENABLED
      SYSTEM_NOTIFICATIONS_ENABLED
      CHARACTER_NOTIFICATIONS_ENABLED
    )

    # Log relevant environment variables
    relevant_keys
    |> Enum.each(&log_env_variable(&1, sensitive_keys))

    # Log app config as well
    log_application_config()
  end

  @doc """
  Logs key application configuration settings.
  """
  def log_application_config do
    WandererNotifier.Logger.Logger.startup_info("Application configuration:")

    # Log version first
    version = Application.spec(:wanderer_notifier, :vsn) |> to_string()
    WandererNotifier.Logger.Logger.startup_info("  version: #{version}")

    # Log critical config values from the application environment
    for {key, env_key} <- [
          {:features, :features},
          {:discord_channel_id, :discord_channel_id},
          {:config_module, :config_module},
          {:env, :env},
          {:schedulers_enabled, :schedulers_enabled}
        ] do
      value = Application.get_env(:wanderer_notifier, env_key)
      WandererNotifier.Logger.Logger.startup_info("  #{key}: #{inspect(value)}")
    end
  end

  # Private helper to create the cache child spec
  defp create_cache_child_spec do
    cache_name = WandererNotifier.Cache.Config.cache_name()
    cache_adapter = Application.get_env(:wanderer_notifier, :cache_adapter, Cachex)

    case cache_adapter do
      Cachex ->
        # Use the cache config which includes stats: true
        cache_config = WandererNotifier.Cache.Config.cache_config()
        {Cachex, cache_config}

      WandererNotifier.Cache.ETSCache ->
        {WandererNotifier.Cache.ETSCache, name: cache_name}

      other ->
        raise "Unknown cache adapter: #{inspect(other)}"
    end
  end

  @doc """
  Gets the current environment.
  """
  def get_env do
    Application.get_env(:wanderer_notifier, :env, :dev)
  end

  @doc """
  Gets a configuration value for the given key.
  """
  def get_config(key, default \\ nil) do
    Application.get_env(:wanderer_notifier, key, default)
  end

  @doc """
  Reloads modules.
  """
  def reload(modules) do
    if get_env() == :prod do
      {:error, :not_allowed_in_production}
    else
      WandererNotifier.Logger.Logger.config_info("Reloading modules", modules: inspect(modules))

      # Save current compiler options
      original_compiler_options = Code.compiler_options()

      # Set ignore_module_conflict to true
      Code.compiler_options(ignore_module_conflict: true)

      try do
        Enum.each(modules, fn module ->
          :code.purge(module)
          :code.delete(module)
          :code.load_file(module)
        end)

        WandererNotifier.Logger.Logger.config_info("Module reload complete")
        {:ok, modules}
      rescue
        error ->
          WandererNotifier.Logger.Logger.config_error("Error reloading modules",
            error: inspect(error)
          )

          {:error, error}
      after
        # Restore original compiler options
        Code.compiler_options(original_compiler_options)
      end
    end
  end
end
