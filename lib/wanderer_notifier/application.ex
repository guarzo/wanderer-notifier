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
  alias WandererNotifier.Logger, as: AppLogger

  alias WandererNotifier.Core.Config
  alias WandererNotifier.Core.License
  alias WandererNotifier.Core.Stats
  alias WandererNotifier.Core.Features
  alias WandererNotifier.Data.Cache.Repository, as: CacheRepo
  alias WandererNotifier.Notifiers.Factory, as: NotifierFactory
  alias WandererNotifier.Helpers.CacheHelpers

  @impl true
  def start(_type, _args) do
    # Get the runtime environment from config
    env =
      Application.get_env(:wanderer_notifier, :env) ||
        String.to_atom(System.get_env("MIX_ENV", "prod"))

    Logger.info("[STARTUP] Starting application")
    Logger.info("[STARTUP] INITIALIZATION: Starting WandererNotifier")
    Logger.info("[STARTUP] ENVIRONMENT: #{env}")
    WandererNotifier.Logger.config_info("ENVIRONMENT: #{env}")

    # Continue with regular startup
    WandererNotifier.Logger.config_info("DEPENDENCIES: Checking feature status")

    # Start main application or minimal test version based on config
    if Application.get_env(:wanderer_notifier, :minimal_test_mode, false) do
      AppLogger.startup_info("Starting in minimal test mode")
      start_minimal_test_components()
    else
      start_main_application()
    end
  end

  # Start the application with all components
  defp start_main_application do
    # Initialize the startup tracker for consolidated logging
    WandererNotifier.Logger.StartupTracker.init()

    # Begin initialization phase
    WandererNotifier.Logger.StartupTracker.begin_phase(
      :initialization,
      "Starting WandererNotifier"
    )

    # Get the environment from system environment variable
    env = System.get_env("MIX_ENV", "prod") |> String.to_atom()

    # Handle development-specific setup
    maybe_start_dev_tools(env)

    # Set the environment in the application configuration
    Application.put_env(:wanderer_notifier, :env, env)

    # Log environment as a state change
    WandererNotifier.Logger.StartupTracker.log_state_change(:environment, "#{env}")

    # Log feature status (avoids duplicate logs)
    log_feature_status()

    # Begin services phase that includes starting the supervisor
    WandererNotifier.Logger.StartupTracker.begin_phase(:services, "Starting core services")

    # Start the supervisor and schedule startup message
    result = start_supervisor_and_notify()

    # Begin database phase (only if needed)
    if database_required?() do
      WandererNotifier.Logger.StartupTracker.begin_phase(
        :database,
        "Establishing database connection"
      )

      # Wait for database connection
      wait_for_database_connection()
    else
      WandererNotifier.Logger.StartupTracker.log_state_change(
        :database_status,
        "Database connection not required"
      )
    end

    # Pre-generate cache for kill comparison data
    schedule_comparison_cache_generation()

    # Complete startup tracking
    WandererNotifier.Logger.StartupTracker.complete_startup()

    result
  end

  # Check if database is required based on feature flags
  defp database_required? do
    Config.map_charts_enabled?() || Config.kill_charts_enabled?()
  end

  # Wait for the database connection to be established
  defp wait_for_database_connection do
    # Only record this event, not log it directly
    WandererNotifier.Logger.StartupTracker.record_event(:database_connection, %{
      status: "attempting"
    })

    # Try up to 5 times with increasing delays
    Enum.reduce_while(1..5, 500, fn attempt, delay ->
      Process.sleep(delay)

      case check_database_connection() do
        {:ok, ping_time} ->
          # Log successful connection as a significant state change (only once)
          WandererNotifier.Logger.StartupTracker.log_state_change(
            :database_status,
            "Database connection established",
            %{ping_time: ping_time}
          )

          {:halt, :ok}

        {:error, reason} ->
          handle_failed_connection_attempt(attempt, reason, delay)
      end
    end)
  end

  # Handle a failed database connection attempt
  defp handle_failed_connection_attempt(attempt, reason, delay) do
    if attempt < 5 do
      # Track the attempt but don't log every one
      WandererNotifier.Logger.StartupTracker.record_event(
        :database_retry,
        %{attempt: attempt, reason: inspect(reason)}
      )

      # Only log the first attempt at warning level
      if attempt == 1 do
        AppLogger.startup_warn(
          "Database connection not ready, will retry #{5 - attempt} more times"
        )
      end

      # Increase delay for next attempt (exponential backoff)
      {:cont, delay * 2}
    else
      # Log final failure as an error
      WandererNotifier.Logger.StartupTracker.record_error(
        "Failed to establish database connection after 5 attempts",
        %{reason: inspect(reason)}
      )

      {:halt, :error}
    end
  end

  # Check if the database connection is available
  defp check_database_connection do
    WandererNotifier.Repo.health_check()
  end

  # Start development tools if in dev environment
  defp maybe_start_dev_tools(:dev) do
    AppLogger.startup_info("Starting ExSync for hot code reloading")

    case Application.ensure_all_started(:exsync) do
      {:ok, _} ->
        AppLogger.startup_info("ExSync started successfully")

      {:error, _} ->
        AppLogger.startup_warn("ExSync not available, continuing without hot reloading")
    end

    # Start watchers for frontend asset rebuilding in development
    start_watchers()
  end

  defp maybe_start_dev_tools(_other_env), do: :ok

  # Log essential feature statuses
  defp log_feature_status do
    # Begin dependencies phase
    WandererNotifier.Logger.StartupTracker.begin_phase(:dependencies, "Checking feature status")

    # Only log essential feature status directly, others go through tracker
    kill_charts_status = if kill_charts_enabled?(), do: "Enabled", else: "Disabled"

    WandererNotifier.Logger.StartupTracker.log_state_change(
      :feature_status,
      "Kill charts feature: #{kill_charts_status}"
    )

    # Log database requirement
    WandererNotifier.Logger.StartupTracker.log_state_change(
      :database_status,
      "PostgreSQL database: Required and will be connected"
    )

    # Track configuration details but don't log directly
    license_key = Config.license_key()

    if license_key && license_key != "" do
      WandererNotifier.Logger.StartupTracker.record_event(:license, %{status: "configured"})
    else
      WandererNotifier.Logger.StartupTracker.record_event(:license, %{status: "not_configured"})
    end

    # License manager config status (tracked but not logged)
    license_manager_status =
      if Config.license_manager_api_url(), do: "configured", else: "not_configured"

    WandererNotifier.Logger.StartupTracker.record_event(:license_manager, %{
      status: license_manager_status
    })
  end

  # Start supervisor and schedule startup notification
  defp start_supervisor_and_notify do
    # Start web server phase
    if Process.get(:startup_tracker) do
      WandererNotifier.Logger.StartupTracker.begin_phase(:web, "Starting web server")
    end

    # Start the supervisor with all children including Nostrum.Consumer
    result =
      Supervisor.start_link(get_children(),
        strategy: :one_for_one,
        name: WandererNotifier.Supervisor
      )

    # Move to completion phase
    if Process.get(:startup_tracker) do
      WandererNotifier.Logger.StartupTracker.begin_phase(:completion, "Finalizing startup")
    end

    # Send startup notification asynchronously with delay
    Task.start(fn ->
      # Use a slightly longer delay to ensure all services are initialized
      Process.sleep(5000)
      send_startup_message()

      # Run initial maintenance tasks
      run_initial_maintenance_tasks()
    end)

    result
  end

  # Run initial maintenance tasks with consolidated logging
  defp run_initial_maintenance_tasks do
    # Record this activity in the tracker
    if Process.get(:startup_tracker) do
      WandererNotifier.Logger.StartupTracker.record_event(:maintenance, %{
        status: "starting_initial_tasks"
      })
    else
      AppLogger.startup_info("Running initial maintenance tasks")
    end

    # Use maintenance service to update systems and characters
    # Create a basic state map similar to what the Maintenance GenServer uses
    current_time = :os.system_time(:second)

    initial_state = %{
      service_start_time: current_time,
      last_systems_update: current_time,
      last_characters_update: current_time,
      last_status_time: current_time,
      systems_count: 0,
      characters_count: 0
    }

    # Call the do_initial_checks function directly from the Scheduler
    alias WandererNotifier.Services.Maintenance.Scheduler
    Scheduler.do_initial_checks(initial_state)

    # Record completion
    if Process.get(:startup_tracker) do
      WandererNotifier.Logger.StartupTracker.record_event(:maintenance, %{
        status: "initial_tasks_completed"
      })
    else
      AppLogger.startup_info("Initial maintenance tasks completed")
    end
  end

  defp send_startup_message do
    # Only record this activity in the tracker, avoid redundant logs
    if Process.get(:startup_tracker) do
      WandererNotifier.Logger.StartupTracker.record_event(:startup_message, %{
        status: "preparing"
      })
    else
      AppLogger.startup_info("Sending startup message...")
    end

    license_status =
      try do
        License.status()
      rescue
        e ->
          AppLogger.startup_error(
            "Error getting license status for startup message: #{inspect(e)}"
          )

          %{valid: false, error_message: "Error retrieving license status"}
      catch
        type, error ->
          AppLogger.startup_error(
            "Error getting license status: #{inspect(type)}, #{inspect(error)}"
          )

          %{valid: false, error_message: "Error retrieving license status"}
      end

    systems = get_tracked_systems()
    characters = CacheRepo.get("map:characters") || []

    # Ensure systems and characters are lists
    systems_list = if is_list(systems), do: systems, else: []
    characters_list = if is_list(characters), do: characters, else: []

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
        length(systems_list),
        length(characters_list)
      )

    discord_embed =
      WandererNotifier.Notifiers.StructuredFormatter.to_discord_format(generic_notification)

    NotifierFactory.notify(:send_discord_embed, [discord_embed, :general])

    # Record completion of startup message in tracker
    if Process.get(:startup_tracker) do
      WandererNotifier.Logger.StartupTracker.record_event(:startup_message, %{
        status: "completed"
      })
    end
  end

  defp get_tracked_systems do
    CacheHelpers.get_tracked_systems()
  end

  @doc """
  Called when a file is changed and code is reloaded in development.
  This replaces the functionality in DevCallbacks.

  Handles two reload cases:
  - When ExSync reloads modules and passes a list of reloaded modules
  - When ExSync sends a {Module, :reload} tuple message
  """
  @spec reload(list(module()) | {module(), :reload}) :: :ok
  def reload(modules) when is_list(modules) do
    AppLogger.startup_info("Reloaded modules: #{inspect(modules)}")
    :ok
  end

  def reload({_module, :reload}) do
    AppLogger.startup_info("Module reloaded")
    :ok
  end

  defp get_children do
    # Initialize the batch logger
    WandererNotifier.Logger.BatchLogger.init()
    AppLogger.startup_info("Batch logger initialized for high-volume logging")

    base_children = [
      # Basic services that don't directly depend on database
      {WandererNotifier.NoopConsumer, []},
      {WandererNotifier.Core.License, []},
      {WandererNotifier.Core.Stats, []},
      {WandererNotifier.Data.Cache.Repository, []},
      {WandererNotifier.Cache.Monitor, []},
      {WandererNotifier.ChartService.ChartServiceManager, []},
      {WandererNotifier.Helpers.DeduplicationHelper, []},

      # Services that may interact with the database
      {WandererNotifier.Services.Service, []},
      {WandererNotifier.Services.Maintenance, []},
      {WandererNotifier.Web.Server, []},
      {WandererNotifier.Workers.CharacterSyncWorker, []}
    ]

    # Add database repo only if required
    children =
      if database_required?() do
        [{WandererNotifier.Repo, [restart: :permanent]} | base_children]
      else
        base_children
      end

    # Add the scheduler supervisor last to ensure all dependencies are started first
    children ++ [{WandererNotifier.Schedulers.Supervisor, []}]
  end

  # Check if kill charts feature is enabled
  defp kill_charts_enabled? do
    WandererNotifier.Core.Config.kill_charts_enabled?()
  end

  defp start_watchers do
    watchers = Application.get_env(:wanderer_notifier, :watchers, [])

    Enum.each(watchers, fn {cmd, args} ->
      AppLogger.startup_info("Starting watcher: #{cmd} with args: #{inspect(args)}")
      {cmd_args, cd_path} = extract_watcher_args(args)
      cmd_str = to_string(cmd)

      # Use the startup tracker to record this event without direct logging
      if Process.get(:startup_tracker) do
        WandererNotifier.Logger.StartupTracker.record_event(:watcher_command, %{
          command: cmd_str,
          args: cmd_args,
          cd: cd_path
        })
      end

      Task.start(fn ->
        try do
          system_opts = []
          system_opts = if cd_path, do: [cd: cd_path] ++ system_opts, else: system_opts
          system_opts = [into: IO.stream(:stdio, :line)] ++ system_opts

          {_output, status} = System.cmd(cmd_str, cmd_args, system_opts)

          if status == 0 do
            # Only log at debug level for successful completion
            AppLogger.startup_debug("Watcher #{cmd} completed successfully")
          else
            AppLogger.startup_error("Watcher #{cmd} exited with status #{status}")
          end
        rescue
          e ->
            AppLogger.startup_error("Error starting watcher: #{inspect(e)}")
            AppLogger.startup_error(Exception.format_stacktrace())
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

  # Schedule the generation of cached comparison data
  defp schedule_comparison_cache_generation() do
    # Check if database operations are enabled
    if WandererNotifier.Resources.TrackedCharacter.database_enabled?() do
      # Database is enabled, start a task to generate the cache
      schedule_cache_generation_task()
    else
      # Database is disabled, log the information
      log_database_disabled_for_cache()
      :ok
    end
  end

  # Log when database operations are disabled
  defp log_database_disabled_for_cache do
    AppLogger.startup_info(
      "Database operations disabled, skipping kill comparison cache pre-generation"
    )
  end

  # Schedule the actual cache generation as a separate task
  defp schedule_cache_generation_task do
    Task.start(fn ->
      # Add a delay to ensure the DB is ready
      Process.sleep(10_000)

      # Only proceed if database is ready
      if WandererNotifier.Schedulers.Supervisor.database_ready?() do
        generate_cache_for_time_ranges()
      else
        AppLogger.startup_error("Skipping cache pre-generation - database not ready")
      end
    end)
  end

  defp generate_cache_for_time_ranges do
    AppLogger.startup_info("Starting pre-generation of kill comparison cache data")

    # Define the time ranges we want to pre-cache
    time_ranges = ["1h", "4h", "12h", "24h", "7d"]

    # Generate cache for each time range
    Enum.each(time_ranges, fn range ->
      generate_cache_for_range(range)
      # Add a small delay between generations to avoid overloading the system
      Process.sleep(1000)
    end)

    AppLogger.startup_info("Completed pre-generation of kill comparison cache data")
  end

  defp generate_cache_for_range(range) do
    try do
      AppLogger.startup_info("Pre-generating kill comparison data for range: #{range}")

      # Determine time range
      {start_datetime, end_datetime} = get_time_range_for_cache(range)

      # Generate cache using the KillmailComparison service instead of the API controller
      case WandererNotifier.Services.KillmailComparison.generate_and_cache_comparison_data(
             range,
             start_datetime,
             end_datetime
           ) do
        {:ok, data} ->
          AppLogger.startup_info("Successfully pre-generated comparison data",
            range: range,
            character_count: length(data.character_breakdown)
          )

        {:error, reason} ->
          AppLogger.startup_warn("Failed to pre-generate comparison data",
            range: range,
            error: inspect(reason)
          )
      end
    rescue
      e ->
        AppLogger.startup_error("Error pre-generating cache for range #{range}",
          error: Exception.message(e)
        )
    end
  end

  # Get the start and end datetime for a given time range
  defp get_time_range_for_cache(range) do
    case range do
      "1h" -> {DateTime.utc_now() |> DateTime.add(-3600, :second), DateTime.utc_now()}
      "4h" -> {DateTime.utc_now() |> DateTime.add(-14_400, :second), DateTime.utc_now()}
      "12h" -> {DateTime.utc_now() |> DateTime.add(-43_200, :second), DateTime.utc_now()}
      "24h" -> {DateTime.utc_now() |> DateTime.add(-86_400, :second), DateTime.utc_now()}
      "7d" -> {DateTime.utc_now() |> DateTime.add(-604_800, :second), DateTime.utc_now()}
      _ -> {DateTime.utc_now() |> DateTime.add(-3600, :second), DateTime.utc_now()}
    end
  end
end
