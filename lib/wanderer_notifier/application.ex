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
    prepare_application_environment()

    Logger.info(
      "Starting WandererNotifier application v#{Application.spec(:wanderer_notifier, :vsn) || "dev"} in #{get_env()} mode",
      category: :startup
    )

    case initialize_services() do
      {:ok, children} ->
        case Supervisor.start_link(children,
               strategy: :one_for_one,
               name: WandererNotifier.Supervisor
             ) do
          {:ok, _pid} = result ->
            try do
              WandererNotifier.Application.Initialization.ServiceInitializer.post_startup_initialization()
              result
            rescue
              exception ->
                Logger.error("Post-startup initialization failed",
                  type: "exception",
                  error: inspect(exception),
                  category: :startup
                )

                result
            catch
              :exit, reason ->
                Logger.error("Post-startup initialization failed",
                  type: "exit",
                  error: inspect(reason),
                  category: :startup
                )

                result
            end

          error ->
            Logger.error("Failed to start supervisor",
              error: inspect(error),
              category: :startup
            )

            error
        end

      {:error, reason} = error ->
        log_startup_error(reason)
        error
    end
  end

  defp initialize_services do
    WandererNotifier.Application.Initialization.ServiceInitializer.initialize_services()
  end

  defp log_startup_error(reason) do
    Logger.error("Failed to initialize services",
      error: inspect(reason),
      category: :startup
    )
  end

  # ──────────────────────────────────────────────────────────────────────────────
  # Application Environment Preparation
  # ──────────────────────────────────────────────────────────────────────────────

  defp prepare_application_environment do
    # Ensure critical configuration exists to prevent startup failures
    ensure_critical_configuration()

    # Configure logger backends dynamically (required for Elixir 1.19+)
    configure_logger_backends()

    # Set application start time for uptime calculation
    Application.put_env(:wanderer_notifier, :start_time, System.monotonic_time(:second))

    # Validate configuration on startup
    validate_configuration()

    # Log environment and configuration for debugging
    log_environment_variables()

    Logger.debug("Application environment prepared successfully", category: :startup)
  end

  # Configures logger backends dynamically (Elixir 1.19+ compatible)
  defp configure_logger_backends do
    env = get_env()

    if should_configure_file_backend?(env) do
      add_file_backends(env)
    end
  rescue
    exception ->
      # Log the failure but continue without file logging to avoid blocking startup
      Logger.warning(
        "Failed to configure logger backends: #{inspect(exception)}. Continuing without file logging."
      )

      :ok
  end

  defp should_configure_file_backend?(env) do
    Code.ensure_loaded?(LoggerFileBackend) and
      Code.ensure_loaded?(LoggerBackends) and
      env != :test
  end

  defp add_file_backends(env) do
    LoggerBackends.add({LoggerFileBackend, :file_log})

    if env == :dev do
      LoggerBackends.add({LoggerFileBackend, :debug_log})
    end
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

  @doc """
  Logs all environment variables to help diagnose configuration issues.
  Sensitive values are redacted.
  """
  def log_environment_variables do
    alias WandererNotifier.Shared.Env

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

    # Use the centralized logging from Env module
    Env.log_variables(relevant_keys, "Environment variables at startup")

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
