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
  alias WandererNotifier.Data.Cache.CachexImpl
  alias WandererNotifier.KillmailProcessing.MetricRegistry
  alias WandererNotifier.Logger.Logger, as: AppLogger

  @doc """
  Starts the application.
  """
  def start(_type, _args) do
    # Initialize startup tracker
    AppLogger.init_startup_tracker()
    AppLogger.begin_startup_phase(:initialization, "Starting WandererNotifier")

    # Initialize batch logging for cache operations
    CachexImpl.init_batch_logging()

    # Log application version
    AppLogger.log_startup_state_change(:version, "Application version", %{
      value: Version.version()
    })

    AppLogger.log_startup_state_change(:environment, "Environment", %{
      value: Application.get_env(:wanderer_notifier, :env, :dev)
    })

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
        AppLogger.begin_startup_phase(:configuration, "Validating configuration")
        validate_configuration()
        AppLogger.begin_startup_phase(:services, "Starting main application")
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
           system_kill_channel: channels.system_kill.enabled,
           character_kill_channel: channels.character_kill.enabled,
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
    AppLogger.begin_startup_phase(:minimal, "Starting minimal application")

    children = [
      {WandererNotifier.NoopConsumer, []}
    ]

    opts = [strategy: :one_for_one, name: WandererNotifier.Supervisor]
    result = Supervisor.start_link(children, opts)

    AppLogger.complete_startup()
    result
  end

  defp start_test_application do
    # Minimal validation for test environment
    AppLogger.begin_startup_phase(:test, "Starting application in test mode")

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
        AppLogger.complete_startup()
        {:ok, pid}

      {:error, reason} = error ->
        AppLogger.startup_error("❌ Failed to start test application", error: inspect(reason))
        AppLogger.complete_startup()
        error
    end
  end

  defp start_main_application do
    # Initialize metric registry to ensure all metrics are pre-registered
    AppLogger.begin_startup_phase(:metrics, "Initializing metrics")
    initialize_metric_registry()

    AppLogger.begin_startup_phase(:children, "Starting child processes")
    children = get_children()
    opts = [strategy: :one_for_one, name: WandererNotifier.Supervisor]

    AppLogger.log_startup_state_change(:child_processes, "Starting child processes", %{
      child_count: length(children)
    })

    case Supervisor.start_link(children, opts) do
      {:ok, pid} ->
        AppLogger.startup_info("✨ WandererNotifier started successfully")
        AppLogger.complete_startup()
        {:ok, pid}

      {:error, {:already_started, pid}} ->
        AppLogger.startup_warn("⚠️ Supervisor already started", pid: inspect(pid))
        AppLogger.complete_startup()
        {:ok, pid}

      {:error, reason} = error ->
        AppLogger.startup_error("❌ Failed to start application", error: inspect(reason))
        AppLogger.complete_startup()
        error
    end
  end

  # Initialize metric registry
  defp initialize_metric_registry do
    # Register the metric atoms
    case MetricRegistry.initialize() do
      {:ok, atoms} ->
        AppLogger.log_startup_state_change(
          :metric_registry,
          "Metric registry initialized successfully",
          %{
            metric_count: length(atoms)
          }
        )

        :ok

      error ->
        AppLogger.startup_error("Failed to initialize metric registry",
          error: inspect(error)
        )

        error
    end
  end

  defp get_children do
    # Core services
    base_children = [
      {WandererNotifier.NoopConsumer, []},
      {WandererNotifier.License.Service, []},
      {WandererNotifier.Core.Stats, []},
      %{
        id: WandererNotifier.KillmailProcessing.Metrics,
        start: {WandererNotifier.KillmailProcessing.Metrics, :start_link, [[]]}
      },
      {WandererNotifier.Helpers.DeduplicationHelper, []},
      {WandererNotifier.Core.Application.Service, []},
      {Cachex, name: :wanderer_cache},
      {WandererNotifier.Data.Cache.Repository, []},
      {WandererNotifier.Data.Repo, []},
      {WandererNotifier.Web.Server, []}
    ]

    # Add ChartServiceManager only if charts are enabled
    charts_enabled = Features.kill_charts_enabled?() or Features.map_charts_enabled?()

    AppLogger.log_startup_state_change(:feature_status, "Charts enabled", %{
      feature: "charts",
      value: charts_enabled
    })

    children =
      if charts_enabled do
        base_children ++ [{WandererNotifier.ChartService.ChartServiceManager, []}]
      else
        base_children
      end

    # Add schedulers last
    children ++ [{WandererNotifier.Schedulers.Supervisor, []}]
  end
end
