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

    children = [
      {WandererNotifier.NoopConsumer, []},
      create_cache_child_spec(),
      {WandererNotifier.Core.Stats, []},
      {WandererNotifier.License.Service, []},
      {WandererNotifier.Core.Application.Service, []},
      {WandererNotifier.Web.Server, []}
    ]

    # Conditionally add scheduler supervisor if enabled
    children =
      children ++
        if Application.get_env(:wanderer_notifier, :scheduler_supervisor_enabled, false) do
          [WandererNotifier.Schedulers.Supervisor]
        else
          []
        end

    opts = [strategy: :one_for_one, name: WandererNotifier.Supervisor]
    Supervisor.start_link(children, opts)
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
      Application.put_env(:wanderer_notifier, :cache_name, :wanderer_cache)
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
    |> Enum.each(fn {key, value} ->
      # Redact sensitive values
      safe_value = if key in sensitive_keys, do: "[REDACTED]", else: value
      # Log each variable individually, and focus on WANDERER_ variables
      if String.starts_with?(key, "WANDERER_") do
        AppLogger.startup_info("  #{key}: #{safe_value}")
      end
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
    [
      {:features, Application.get_env(:wanderer_notifier, :features)},
      {:discord_channel_id, Application.get_env(:wanderer_notifier, :discord_channel_id)},
      {:config_module, Application.get_env(:wanderer_notifier, :config)},
      {:env, Application.get_env(:wanderer_notifier, :env)}
    ]
    |> Enum.each(fn {key, value} ->
      AppLogger.startup_info("  #{key}: #{inspect(value)}")
    end)
  end

  # Private helper to create the cache child spec
  defp create_cache_child_spec do
    cache_name = Application.get_env(:wanderer_notifier, :cache_name, :wanderer_cache)
    {Cachex, name: cache_name}
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
