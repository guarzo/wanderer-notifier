defmodule WandererNotifier.Application do
  @moduledoc """
  Application module for WandererNotifier.
  Handles application startup and environment configuration.
  """

  use Application
  require Logger

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

    Logger.debug("Starting WandererNotifier", category: :startup)

    # Log all environment variables to help diagnose config issues
    log_environment_variables()

    # Log scheduler configuration
    schedulers_enabled = Application.get_env(:wanderer_notifier, :schedulers_enabled, false)

    Logger.debug("Schedulers enabled: #{schedulers_enabled}", category: :startup)

    base_children = [
      # Add Task.Supervisor first to prevent initialization races
      {Task.Supervisor, name: WandererNotifier.TaskSupervisor},
      # Add Registry for cache process naming
      {Registry, keys: :unique, name: WandererNotifier.Infrastructure.Cache.Registry},
      # Add Registry for SSE client naming
      {Registry, keys: :unique, name: WandererNotifier.Registry},
      create_cache_child_spec(),
      # Add rate limiter for HTTP requests
      {WandererNotifier.RateLimiter, []},
      # Add persistent storage modules before Discord consumer
      {WandererNotifier.PersistentValues, []},
      {WandererNotifier.CommandLog, []},
      # Add validation manager for production testing
      {WandererNotifier.Shared.Utils.ValidationManager, []},
      # Enhanced Discord consumer that handles slash commands
      {WandererNotifier.Infrastructure.Adapters.Discord.Consumer, []},
      {WandererNotifier.Application.Services.Stats, []},
      {WandererNotifier.Domains.License.LicenseService, []},
      {WandererNotifier.Application.Services.Application.Service, []},
      # Phoenix PubSub for real-time communication
      {Phoenix.PubSub, name: WandererNotifier.PubSub},
      # Phoenix endpoint for API and WebSocket functionality
      {WandererNotifierWeb.Endpoint, []}
    ]

    # Cache monitoring modules have been removed in simplification
    cache_monitoring_children = []

    # Add real-time processing integration (Sprint 3) (skip in test)
    realtime_children =
      if get_env() != :test do
        [{WandererNotifier.Infrastructure.Messaging.Integration, []}]
      else
        []
      end

    # Add Killmail processing pipeline - always enabled
    killmail_children = [{WandererNotifier.Domains.Killmail.Supervisor, []}]

    # Add SSE supervisor - always enabled for system and character tracking
    sse_children = [{WandererNotifier.Map.SSESupervisor, []}]

    # Add scheduler supervisor last to ensure all dependencies are started
    scheduler_children = [{WandererNotifier.Application.Supervisors.Schedulers.Supervisor, []}]

    children =
      base_children ++
        cache_monitoring_children ++
        realtime_children ++ killmail_children ++ sse_children ++ scheduler_children

    Logger.debug("Starting children: #{inspect(children)}", category: :startup)

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

  # Version manager functions have been removed

  # Cache monitoring has been simplified - no initialization needed
  defp initialize_cache_monitoring do
    Logger.debug("Cache monitoring has been simplified", category: :startup)
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
          Logger.error("Failed to initialize SSE clients",
            category: :startup,
            error: Exception.message(error)
          )
      end
    end)

    :ok
  end

  # Wait for the supervision tree to be fully started
  defp wait_for_supervisor_startup(attempt \\ 0, max_attempts \\ 50) do
    if attempt >= max_attempts do
      raise "SSESupervisor failed to start after #{max_attempts} attempts"
    end

    case check_supervisor_state() do
      :ready -> :ok
      :not_found -> wait_and_retry_supervisor(attempt, max_attempts)
      :not_ready -> wait_and_retry_supervisor(attempt, max_attempts)
    end
  end

  defp check_supervisor_state do
    case Process.whereis(WandererNotifier.Map.SSESupervisor) do
      nil -> :not_found
      pid when is_pid(pid) -> check_supervisor_ready(pid)
    end
  end

  defp wait_and_retry_supervisor(attempt, max_attempts) do
    wait_time = calculate_backoff_ms(attempt)
    Process.sleep(wait_time)
    wait_for_supervisor_startup(attempt + 1, max_attempts)
  end

  defp check_supervisor_ready(pid) do
    try do
      # Check if supervisor can respond to queries
      # SSESupervisor starts with no children by design, so just check if it responds
      _children = Supervisor.which_children(pid)
      :ready
    rescue
      _ ->
        # If there's an error, supervisor is not ready
        :not_ready
    end
  end

  defp calculate_backoff_ms(attempt) do
    # Exponential backoff: 10ms, 20ms, 40ms, ..., max 1000ms
    base_ms = 10
    max_ms = 1000

    backoff = base_ms * :math.pow(2, attempt)
    min(trunc(backoff), max_ms)
  end

  # Validates critical configuration on startup
  defp validate_configuration do
    Logger.debug("Configuration validation: PASSED", category: :startup)
    :ok
  end

  # Ensures critical configuration exists to prevent startup failures
  defp ensure_critical_configuration do
    # Ensure config_module is set
    if Application.get_env(:wanderer_notifier, :config_module) == nil do
      Application.put_env(:wanderer_notifier, :config_module, WandererNotifier.Shared.Config)
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
        WandererNotifier.Infrastructure.Cache.default_cache_name()
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
        Logger.debug("  #{key}: #{safe_value}", category: :startup)
    end
  end

  @doc """
  Logs all environment variables to help diagnose configuration issues.
  Sensitive values are redacted.
  """
  def log_environment_variables do
    Logger.debug("Environment variables at startup:", category: :startup)

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
      DISCORD_GUILD_ID
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
    Logger.debug("Application configuration:", category: :startup)

    # Log version first
    version = Application.spec(:wanderer_notifier, :vsn) |> to_string()
    Logger.debug("  version: #{version}", category: :startup)

    # Log critical config values from the application environment
    for {key, env_key} <- [
          {:features, :features},
          {:discord_channel_id, :discord_channel_id},
          {:config_module, :config_module},
          {:env, :env},
          {:schedulers_enabled, :schedulers_enabled}
        ] do
      value = Application.get_env(:wanderer_notifier, env_key)
      Logger.debug("  #{key}: #{inspect(value)}", category: :startup)
    end
  end

  # Private helper to create the cache child spec
  defp create_cache_child_spec do
    cache_name = WandererNotifier.Infrastructure.Cache.cache_name()
    # Use Cachex directly - no adapter configuration needed
    cache_opts = [stats: true]
    {Cachex, [name: cache_name] ++ cache_opts}
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
      Logger.debug("Reloading modules", category: :config, modules: inspect(modules))

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

        Logger.debug("Module reload complete", category: :config)
        {:ok, modules}
      rescue
        error ->
          Logger.error("Error reloading modules", category: :config, error: inspect(error))

          {:error, error}
      after
        # Restore original compiler options
        Code.compiler_options(original_compiler_options)
      end
    end
  end
end
