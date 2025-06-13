defmodule WandererNotifier.Application do
  @moduledoc """
  Application module for WandererNotifier.
  Handles application startup and environment configuration.
  """

  use Application

  alias WandererNotifier.Logger.Logger, as: AppLogger

  @doc """
  Starts the WandererNotifier application.
  """
  def start(_type, _args) do
    # Ensure critical configuration exists to prevent startup failures
    ensure_critical_configuration()

    AppLogger.startup_info("Starting WandererNotifier")

    # Log all environment variables to help diagnose config issues
    log_environment_variables()

    # Log scheduler configuration
    schedulers_enabled = Application.get_env(:wanderer_notifier, :schedulers_enabled, false)
    AppLogger.startup_info("Schedulers enabled: #{schedulers_enabled}")

    base_children = [
      # Add Task.Supervisor first to prevent initialization races
      {Task.Supervisor, name: WandererNotifier.TaskSupervisor},
      # Add Registry for cache process naming
      {Registry, keys: :unique, name: WandererNotifier.Cache.Registry},
      create_cache_child_spec(),
      # Add persistent storage modules before Discord consumer
      WandererNotifier.PersistentValues,
      WandererNotifier.CommandLog,
      # Enhanced Discord consumer that handles slash commands
      {WandererNotifier.Discord.Consumer, []},
      {WandererNotifier.Core.Stats, []},
      {WandererNotifier.License.Service, []},
      {WandererNotifier.Core.Application.Service, []},
      {WandererNotifier.Web.Server, []}
    ]

    # Add Killmail processing pipeline if RedisQ is enabled
    redisq_enabled = WandererNotifier.Config.redisq_enabled?()
    AppLogger.startup_info("RedisQ enabled: #{redisq_enabled}")

    killmail_children =
      if redisq_enabled do
        [{WandererNotifier.Killmail.Supervisor, []}]
      else
        []
      end

    # Add scheduler supervisor last to ensure all dependencies are started
    scheduler_children = [{WandererNotifier.Schedulers.Supervisor, []}]

    children = base_children ++ killmail_children ++ scheduler_children

    AppLogger.startup_info("Starting children: #{inspect(children)}")

    opts = [strategy: :one_for_one, name: WandererNotifier.Supervisor]
    {:ok, _} = Supervisor.start_link(children, opts)
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

    # Ensure Discord Application ID is configured for slash commands
    discord_app_id = System.get_env("DISCORD_APPLICATION_ID")
    if is_nil(discord_app_id) or String.trim(discord_app_id) == "" do
      raise """
      DISCORD_APPLICATION_ID environment variable is required for Discord slash commands.
      Please set this to your Discord application ID from the Discord Developer Portal.
      """
    end
  end

  @doc """
  Logs all environment variables to help diagnose configuration issues.
  Sensitive values are redacted.
  """
  def log_environment_variables do
    AppLogger.startup_info("Environment variables at startup:")

    sensitive_keys = ~w(
      WANDERER_DISCORD_BOT_TOKEN
      WANDERER_MAP_TOKEN
      WANDERER_NOTIFIER_API_TOKEN
      WANDERER_LICENSE_KEY
    )

    # Get all environment variables, sorted by key
    System.get_env()
    |> Enum.sort_by(fn {k, _} -> k end)
    |> Enum.filter(fn {key, _} -> String.starts_with?(key, "WANDERER_") end)
    |> Enum.each(fn {key, value} ->
      # Redact sensitive values
      safe_value = if key in sensitive_keys, do: "[REDACTED]", else: value
      AppLogger.startup_info("  #{key}: #{safe_value}")
    end)

    # Log app config as well
    log_application_config()
  end

  @doc """
  Logs key application configuration settings.
  """
  def log_application_config do
    AppLogger.startup_info("Application configuration:")

    # Log critical config values from the application environment
    for {key, env_key} <- [
          {:features, :features},
          {:discord_channel_id, :discord_channel_id},
          {:config_module, :config_module},
          {:env, :env},
          {:schedulers_enabled, :schedulers_enabled}
        ] do
      value = Application.get_env(:wanderer_notifier, env_key)
      AppLogger.startup_info("  #{key}: #{inspect(value)}")
    end
  end

  # Private helper to create the cache child spec
  defp create_cache_child_spec do
    cache_name = WandererNotifier.Cache.Config.cache_name()
    cache_adapter = Application.get_env(:wanderer_notifier, :cache_adapter, Cachex)

    case cache_adapter do
      Cachex ->
        Cachex.child_spec(name: cache_name)

      WandererNotifier.Cache.ETSCache ->
        {WandererNotifier.Cache.ETSCache, name: cache_name}

      WandererNotifier.Cache.SimpleETSCache ->
        {WandererNotifier.Cache.SimpleETSCache, name: cache_name}

      other ->
        raise "Unknown cache adapter: #{inspect(other)}"
    end
  end

  @doc """
  Gets the current environment.
  """
  def get_env do
    Application.get_env(:wanderer_notifier, :environment, :dev)
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
      AppLogger.config_info("Reloading modules", modules: inspect(modules))

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

        AppLogger.config_info("Module reload complete")
        {:ok, modules}
      rescue
        error ->
          AppLogger.config_error("Error reloading modules", error: inspect(error))
          {:error, error}
      after
        # Restore original compiler options
        Code.compiler_options(original_compiler_options)
      end
    end
  end
end
