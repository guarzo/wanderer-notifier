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
      create_cache_child_spec(),
      # Add persistent storage modules before Discord consumer
      {WandererNotifier.PersistentValues, []},
      {WandererNotifier.CommandLog, []},
      # Enhanced Discord consumer that handles slash commands
      {WandererNotifier.Discord.Consumer, []},
      {WandererNotifier.Core.Stats, []},
      {WandererNotifier.License.Service, []},
      {WandererNotifier.Core.Application.Service, []},
      {WandererNotifier.Web.Server, []}
    ]

    # Add Killmail processing pipeline if RedisQ is enabled
    redisq_enabled = WandererNotifier.Config.redisq_enabled?()
    WandererNotifier.Logger.Logger.startup_info("RedisQ enabled: #{redisq_enabled}")

    killmail_children =
      if redisq_enabled do
        [{WandererNotifier.Killmail.Supervisor, []}]
      else
        []
      end

    # Add MapEvents WebSocket client if configured
    map_events_children = build_map_events_children()

    # Add scheduler supervisor last to ensure all dependencies are started
    scheduler_children = [{WandererNotifier.Schedulers.Supervisor, []}]

    children = base_children ++ killmail_children ++ map_events_children ++ scheduler_children

    WandererNotifier.Logger.Logger.startup_info("Starting children: #{inspect(children)}")

    opts = [strategy: :one_for_one, name: WandererNotifier.Supervisor]
    {:ok, _} = Supervisor.start_link(children, opts)
  end

  # Build MapEvents children if WebSocket map events are enabled
  defp build_map_events_children do
    # Check if we have the required configuration
    map_name = Application.get_env(:wanderer_notifier, :map_name)
    map_id = Application.get_env(:wanderer_notifier, :map_id)
    # This is what runtime.exs sets
    map_api_key = Application.get_env(:wanderer_notifier, :map_token)
    websocket_map_url = Application.get_env(:wanderer_notifier, :websocket_map_url)

    WandererNotifier.Logger.Logger.startup_info(
      "MapEvents configuration check",
      map_name: inspect(map_name),
      map_id: inspect(map_id),
      map_api_key: if(map_api_key, do: "present", else: "missing"),
      websocket_map_url: inspect(websocket_map_url)
    )

    # Use map_id if available, otherwise fall back to map_name
    map_identifier = map_id || map_name

    if map_identifier && map_api_key && websocket_map_url do
      WandererNotifier.Logger.Logger.startup_info(
        "Starting MapEvents WebSocket client",
        map_identifier: map_identifier,
        url: websocket_map_url
      )

      # Use the MapEvents supervisor which handles connection failures gracefully
      [
        {WandererNotifier.MapEvents.Supervisor,
         [
           map_identifier: map_identifier,
           api_key: map_api_key
         ]}
      ]
    else
      missing = []
      missing = if is_nil(map_identifier), do: ["map_id or map_name" | missing], else: missing
      missing = if is_nil(map_api_key), do: ["map_api_key" | missing], else: missing
      missing = if is_nil(websocket_map_url), do: ["websocket_map_url" | missing], else: missing

      WandererNotifier.Logger.Logger.startup_info(
        "MapEvents WebSocket client NOT started - missing configuration",
        missing: missing
      )

      []
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

  @doc """
  Logs all environment variables to help diagnose configuration issues.
  Sensitive values are redacted.
  """
  def log_environment_variables do
    WandererNotifier.Logger.Logger.startup_info("Environment variables at startup:")

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
      WandererNotifier.Logger.Logger.startup_info("  #{key}: #{safe_value}")
    end)

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
        Cachex.child_spec(name: cache_name)

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
