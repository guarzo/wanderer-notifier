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
  """

  use Application

  alias WandererNotifier.Config.API
  alias WandererNotifier.Config.Database
  alias WandererNotifier.Config.Debug
  alias WandererNotifier.Config.Features
  alias WandererNotifier.Config.Notifications
  alias WandererNotifier.Config.Timings
  alias WandererNotifier.Config.Version
  alias WandererNotifier.Config.Web
  alias WandererNotifier.Config.Websocket
  alias WandererNotifier.Logger.Logger, as: AppLogger

  @doc """
  Starts the application.
  """
  def start(_type, _args) do
    minimal_test = Application.get_env(:wanderer_notifier, :minimal_test, false)

    if minimal_test do
      start_minimal_application()
    else
      # Check if we're in test mode
      is_test = Application.get_env(:wanderer_notifier, :env) == :test

      if is_test do
        # Start with minimal validation for tests
        start_test_application()
      else
        # Full validation for production
        validate_configuration()
        start_main_application()
      end
    end
  end

  @doc """
  Reloads modules.
  """
  def reload(modules) do
    AppLogger.config_info("Reloading modules", modules: inspect(modules))
    Code.compiler_options(ignore_module_conflict: true)

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
  end

  # Private functions

  defp validate_configuration do
    # Log application version on startup
    AppLogger.startup_debug("Starting application",
      version: Version.version(),
      environment: Application.get_env(:wanderer_notifier, :env, :dev)
    )

    # Define all configuration modules to validate with their display names and extra info
    config_modules = [
      {Database, "Database", []},
      {Web, "Web", [port: Web.port(), host: Web.host()]},
      {Websocket, "Websocket", [url: Websocket.url(), enabled: Websocket.enabled()]},
      {API, "API", []},
      {Features, "Features",
       fn ->
         status = Features.get_feature_status()

         [
           kill_notifications: status.kill_notifications_enabled,
           character_tracking: status.character_tracking_enabled,
           system_tracking: status.system_tracking_enabled
         ]
       end},
      {Notifications, "Notifications",
       fn ->
         channels = Notifications.config().channels

         [
           main_channel: channels.main.enabled,
           kill_channel: channels.kill.enabled,
           system_channel: channels.system.enabled
         ]
       end},
      {Timings, "Timings", []},
      {Debug, "Debug", [logging_enabled: Debug.debug_logging_enabled?()]}
    ]

    # Validate each module in parallel with Task.async_stream
    Task.async_stream(
      config_modules,
      fn module_info ->
        {module, name, info_fn} = module_info

        # Get extra info if it's a function
        info = if is_function(info_fn), do: info_fn.(), else: info_fn

        # Call the validate function on the module
        validate_module(module, name, info)
      end,
      timeout: :infinity
    )
    |> Stream.run()
  end

  defp process_validation_result(_module, name, info, result) do
    case result do
      :ok ->
        # Log success with any extra info at debug level
        AppLogger.config_debug("#{name} configuration validated successfully", info)
        :ok

      {:error, reason} when is_binary(reason) ->
        # Single error string
        AppLogger.config_error("Invalid #{name} configuration", error: reason)
        {:error, name, reason}

      {:error, errors} when is_list(errors) ->
        # List of error strings
        Enum.each(errors, fn error ->
          AppLogger.config_error("#{name} configuration validation error", error: error)
        end)

        {:error, name, errors}
    end
  end

  defp validate_module(module, name, info) do
    # Call the validate function on the module directly instead of using apply
    result = module.validate()
    process_validation_result(module, name, info, result)
  end

  defp start_minimal_application do
    children = [
      {WandererNotifier.NoopConsumer, []}
    ]

    opts = [strategy: :one_for_one, name: WandererNotifier.Supervisor]
    Supervisor.start_link(children, opts)
  end

  defp start_test_application do
    # Minimal validation for test environment
    AppLogger.startup_debug("Starting application in test mode")

    children = [
      # Core services needed for testing
      {WandererNotifier.NoopConsumer, []},
      {Cachex, name: :wanderer_cache},
      {WandererNotifier.Web.Server, []}
    ]

    opts = [strategy: :one_for_one, name: WandererNotifier.Supervisor]

    case Supervisor.start_link(children, opts) do
      {:ok, pid} ->
        AppLogger.startup_info("✨ Test application started")
        {:ok, pid}

      {:error, reason} = error ->
        AppLogger.startup_error("❌ Failed to start test application", error: inspect(reason))
        error
    end
  end

  defp start_main_application do
    children = get_children()
    opts = [strategy: :one_for_one, name: WandererNotifier.Supervisor]

    AppLogger.startup_info("🚀 Starting WandererNotifier", child_count: length(children))

    case Supervisor.start_link(children, opts) do
      {:ok, pid} ->
        AppLogger.startup_info("✨ WandererNotifier started successfully")
        {:ok, pid}

      {:error, {:already_started, pid}} ->
        AppLogger.startup_warn("⚠️ Supervisor already started", pid: inspect(pid))
        {:ok, pid}

      {:error, reason} = error ->
        AppLogger.startup_error("❌ Failed to start application", error: inspect(reason))
        error
    end
  end

  defp get_children do
    [
      # Core services
      {WandererNotifier.NoopConsumer, []},
      {WandererNotifier.License.Service, []},
      {WandererNotifier.Core.Stats, []},
      {WandererNotifier.Helpers.DeduplicationHelper, []},
      {WandererNotifier.Core.Application.Service, []},
      {Cachex, name: :wanderer_cache},
      {WandererNotifier.Data.Cache.Repository, []},
      {WandererNotifier.Data.Repo, []},
      {WandererNotifier.Web.Server, []},
      {WandererNotifier.Schedulers.Supervisor, []}
    ]
  end
end
