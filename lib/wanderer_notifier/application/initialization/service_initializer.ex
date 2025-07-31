defmodule WandererNotifier.Application.Initialization.ServiceInitializer do
  @moduledoc """
  Unified service initialization coordinator.

  This module manages the startup sequence of all application services,
  ensuring proper dependency ordering and error handling during initialization.

  ## Initialization Phases

  1. **Infrastructure Phase**: Core infrastructure (cache, registries, PubSub)
  2. **Foundation Phase**: Basic services (ApplicationService, LicenseService)
  3. **Integration Phase**: External integrations (Discord, HTTP clients)
  4. **Processing Phase**: Business logic services (Killmail, SSE, Schedulers)
  5. **Finalization Phase**: Post-startup initialization (SSE clients, metrics)
  """

  require Logger

  @type initialization_phase ::
          :infrastructure | :foundation | :integration | :processing | :finalization
  @type service_spec :: Supervisor.child_spec() | {module(), term()}
  @type service_config :: %{
          phase: initialization_phase(),
          dependencies: [atom()],
          required: boolean(),
          timeout: pos_integer(),
          async_init: boolean()
        }

  # ──────────────────────────────────────────────────────────────────────────────
  # Public API
  # ──────────────────────────────────────────────────────────────────────────────

  @doc """
  Initializes all application services in the correct order.
  """
  @spec initialize_services() :: {:ok, [Supervisor.child_spec()]} | {:error, term()}
  def initialize_services do
    start_time = System.monotonic_time(:millisecond)
    Logger.info("Starting service initialization", category: :startup)

    try do
      case build_service_tree() do
        {:ok, services} ->
          duration = System.monotonic_time(:millisecond) - start_time

          Logger.info("Service initialization completed successfully in #{duration}ms",
            services_count: length(services),
            category: :startup
          )

          {:ok, services}
      end
    rescue
      error ->
        reason = {:service_tree_build_failed, error}

        Logger.error("Service initialization failed",
          error: inspect(reason),
          category: :startup
        )

        {:error, reason}
    end
  end

  @doc """
  Performs post-startup initialization tasks asynchronously.
  """
  @spec post_startup_initialization() :: :ok
  def post_startup_initialization do
    Logger.info("Starting post-startup initialization (async)", category: :startup)

    # Start finalization phase in a supervised task
    Task.Supervisor.start_child(WandererNotifier.TaskSupervisor, fn ->
      finalization_phase()
    end)

    :ok
  end

  # ──────────────────────────────────────────────────────────────────────────────
  # Service Tree Building
  # ──────────────────────────────────────────────────────────────────────────────

  defp build_service_tree do
    # Let any exceptions bubble up naturally - they'll be caught by the caller
    services =
      infrastructure_phase() ++
        foundation_phase() ++
        integration_phase() ++
        processing_phase()

    {:ok, services}
  end

  # ──────────────────────────────────────────────────────────────────────────────
  # Initialization Phases
  # ──────────────────────────────────────────────────────────────────────────────

  defp infrastructure_phase do
    Logger.debug("Initializing infrastructure phase", category: :startup)

    [
      # Task supervisor must be first for async initialization
      {Task.Supervisor, name: WandererNotifier.TaskSupervisor},

      # Dependency injection registry
      {WandererNotifier.Application.Services.DependencyRegistry, []},

      # Registry for process naming
      {Registry, keys: :unique, name: WandererNotifier.Registry},

      # Cache system
      create_cache_child_spec(),

      # Rate limiting for external services
      {WandererNotifier.RateLimiter, []},

      # Phoenix PubSub for internal communication
      {Phoenix.PubSub, name: WandererNotifier.PubSub}
    ]
  end

  defp foundation_phase do
    Logger.debug("Initializing foundation phase", category: :startup)

    [
      # Persistent storage
      {WandererNotifier.PersistentValues, []},
      {WandererNotifier.CommandLog, []},

      # Validation and monitoring
      {WandererNotifier.Shared.Utils.ValidationManager, []},

      # Core application service
      {WandererNotifier.Application.Services.ApplicationService, []},

      # License management
      {WandererNotifier.Domains.License.LicenseService, []}
    ]
  end

  defp integration_phase do
    Logger.debug("Initializing integration phase", category: :startup)

    base_integrations = [
      # Discord integration
      {WandererNotifier.Infrastructure.Adapters.Discord.Consumer, []},

      # Phoenix web endpoint
      {WandererNotifierWeb.Endpoint, []}
    ]

    # Add real-time integration if not in test environment
    if Application.get_env(:wanderer_notifier, :env) != :test do
      base_integrations ++
        [
          {WandererNotifier.Infrastructure.ConnectionHealthService, []}
        ]
    else
      base_integrations
    end
  end

  defp processing_phase do
    Logger.debug("Initializing processing phase", category: :startup)

    [
      # Killmail processing pipeline
      {WandererNotifier.Domains.Killmail.Supervisor, []},

      # SSE clients for map tracking
      {WandererNotifier.Map.SSESupervisor, []},

      # Background schedulers
      {WandererNotifier.Application.Supervisors.Schedulers.Supervisor, []}
    ]
  end

  defp finalization_phase do
    start_time = System.monotonic_time(:millisecond)
    Logger.debug("Starting finalization phase", category: :startup)

    # Wait for core services to be ready
    wait_for_service_readiness()

    # Initialize cache monitoring
    initialize_cache_monitoring()

    # Initialize SSE clients if not in test mode
    if Application.get_env(:wanderer_notifier, :env) != :test do
      initialize_sse_clients()
    end

    duration = System.monotonic_time(:millisecond) - start_time
    Logger.info("Finalization phase completed in #{duration}ms", category: :startup)
  end

  # ──────────────────────────────────────────────────────────────────────────────
  # Service Readiness and Health Checks
  # ──────────────────────────────────────────────────────────────────────────────

  defp wait_for_service_readiness do
    critical_services = [
      WandererNotifier.Application.Services.ApplicationService,
      WandererNotifier.Map.SSESupervisor
    ]

    Enum.each(critical_services, &wait_for_service/1)
  end

  # Maximum wait time is approximately 50 seconds based on max_attempts (50) and backoff duration
  # Backoff starts at 10ms and exponentially increases up to 1000ms per attempt
  defp wait_for_service(service_module, attempts \\ 0, max_attempts \\ 50) do
    if attempts >= max_attempts do
      raise "Service #{service_module} failed to start after #{max_attempts} attempts"
    end

    case Process.whereis(service_module) do
      nil ->
        attempts
        |> calculate_backoff_ms()
        |> Process.sleep()

        wait_for_service(service_module, attempts + 1, max_attempts)

      pid when is_pid(pid) ->
        # Service is running
        :ok
    end
  end

  defp calculate_backoff_ms(attempt) do
    # Exponential backoff: 10ms, 20ms, 40ms, ..., max 1000ms
    base_ms = 10
    max_ms = 1000

    backoff = base_ms * :math.pow(2, attempt)
    min(trunc(backoff), max_ms)
  end

  # ──────────────────────────────────────────────────────────────────────────────
  # Specific Initialization Tasks
  # ──────────────────────────────────────────────────────────────────────────────

  defp initialize_cache_monitoring do
    Logger.debug("Initializing cache monitoring", category: :startup)
    # Cache monitoring has been simplified - no action needed
    :ok
  end

  defp initialize_sse_clients do
    Logger.debug("Initializing SSE clients", category: :startup)

    try do
      WandererNotifier.Map.SSESupervisor.initialize_sse_clients()
      Logger.info("SSE clients initialized successfully", category: :startup)
    rescue
      error ->
        Logger.error("Failed to initialize SSE clients",
          error: Exception.message(error),
          category: :startup
        )
    end
  end

  # ──────────────────────────────────────────────────────────────────────────────
  # Helper Functions
  # ──────────────────────────────────────────────────────────────────────────────

  defp create_cache_child_spec do
    cache_name = WandererNotifier.Infrastructure.Cache.cache_name()
    cache_opts = [stats: true]
    {Cachex, [name: cache_name] ++ cache_opts}
  end
end
