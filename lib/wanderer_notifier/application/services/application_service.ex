defmodule WandererNotifier.Application.Services.ApplicationService do
  @moduledoc """
  Main application service that coordinates all application functionality.

  This service consolidates the responsibilities of multiple smaller services into
  a single, cohesive application layer that:

  - Manages application state and metrics (from Stats)
  - Provides dependency injection (from Dependencies)
  - Coordinates notification processing (from NotificationService)
  - Handles service lifecycle and health monitoring

  This follows the Single Responsibility Principle at the application level,
  where the responsibility is "coordinate the entire application's behavior."
  """

  use GenServer

  use WandererNotifier.Application.Services.ServiceBehaviour,
    name: :application_service,
    description: "Core application coordination service",
    version: "2.0.0"

  require Logger

  alias WandererNotifier.Shared.Types.CommonTypes
  alias WandererNotifier.Shared.Utils.TimeUtils

  alias WandererNotifier.Application.Services.ApplicationService.{
    State,
    DependencyManager,
    MetricsTracker,
    NotificationCoordinator
  }

  @type service_result :: CommonTypes.result(term())

  # ──────────────────────────────────────────────────────────────────────────────
  # Client API
  # ──────────────────────────────────────────────────────────────────────────────

  @doc """
  Starts the ApplicationService GenServer.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    Logger.debug("Starting ApplicationService...", category: :startup)
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  # ── Metrics & Stats ──

  @doc """
  Increments a metric counter.
  """
  @spec increment_metric(atom()) :: :ok
  def increment_metric(type) do
    GenServer.cast(__MODULE__, {:increment_metric, type})
  end

  @doc """
  Gets current application statistics.
  """
  @spec get_stats() :: map()
  def get_stats do
    GenServer.call(__MODULE__, :get_stats)
  end

  @doc """
  Checks if this is the first notification of a specific type.
  """
  @spec first_notification?(atom()) :: boolean()
  def first_notification?(type) when type in [:kill, :character, :system] do
    GenServer.call(__MODULE__, {:first_notification, type})
  end

  @doc """
  Marks that a notification of the given type has been sent.
  """
  @spec mark_notification_sent(atom()) :: :ok
  def mark_notification_sent(type) when type in [:kill, :character, :system] do
    GenServer.cast(__MODULE__, {:mark_notification_sent, type})
  end

  # ── Dependencies ──

  @doc """
  Gets a dependency by name with fallback to default implementation.
  """
  @spec get_dependency(atom(), module()) :: module()
  def get_dependency(name, default) do
    # Use the new dependency registry directly
    WandererNotifier.Application.Services.DependencyRegistry.resolve(name, default)
  end

  # ── Notification Coordination ──

  @doc """
  Processes a notification through the appropriate channels.
  """
  @spec process_notification(map(), keyword()) :: service_result()
  def process_notification(notification, opts \\ []) do
    GenServer.call(__MODULE__, {:process_notification, notification, opts}, 30_000)
  end

  @doc """
  Sends a kill notification.
  """
  @spec notify_kill(map()) :: service_result()
  def notify_kill(notification) do
    GenServer.call(__MODULE__, {:notify_kill, notification})
  end

  # ── Health & Status ──

  @doc """
  Gets the current health status of the application.
  """
  @spec health_status() :: map()
  def health_status do
    GenServer.call(__MODULE__, :health_status)
  end

  @doc """
  Updates service health metrics.
  """
  @spec update_health(atom(), map()) :: :ok
  def update_health(service, status) do
    GenServer.cast(__MODULE__, {:update_health, service, status})
  end

  @doc """
  Sets the tracked count for systems or characters.
  """
  @spec set_tracked_count(atom(), non_neg_integer()) :: :ok
  def set_tracked_count(type, count) when type in [:systems, :characters] and is_integer(count) do
    GenServer.cast(__MODULE__, {:set_tracked_count, type, count})
  end

  # ──────────────────────────────────────────────────────────────────────────────
  # GenServer Implementation
  # ──────────────────────────────────────────────────────────────────────────────

  @impl true
  def init(opts) do
    Logger.debug("Initializing ApplicationService...", category: :startup)

    state = State.new(opts)

    # Initialize subsystems
    {:ok, state} = DependencyManager.initialize(state)
    {:ok, state} = MetricsTracker.initialize(state)
    {:ok, state} = NotificationCoordinator.initialize(state)

    Logger.info("ApplicationService initialized successfully", category: :startup)
    {:ok, state}
  end

  @impl true
  def handle_call(:get_stats, _from, state) do
    stats = MetricsTracker.get_stats(state)
    {:reply, stats, state}
  end

  @impl true
  def handle_call({:first_notification, type}, _from, state) do
    result = MetricsTracker.first_notification?(state, type)
    {:reply, result, state}
  end

  @impl true
  def handle_call({:get_dependency, name, default}, _from, state) do
    # Delegate to the dependency registry
    dependency = WandererNotifier.Application.Services.DependencyRegistry.resolve(name, default)
    {:reply, dependency, state}
  end

  @impl true
  def handle_call({:process_notification, notification, opts}, _from, state) do
    case NotificationCoordinator.process_notification(state, notification, opts) do
      {:ok, result, new_state} -> {:reply, {:ok, result}, new_state}
      {:error, reason, new_state} -> {:reply, {:error, reason}, new_state}
    end
  end

  @impl true
  def handle_call({:notify_kill, notification}, _from, state) do
    case NotificationCoordinator.notify_kill(state, notification) do
      {:ok, result, new_state} -> {:reply, {:ok, result}, new_state}
      {:error, reason, new_state} -> {:reply, {:error, reason}, new_state}
    end
  end

  @impl true
  def handle_call(:health_status, _from, state) do
    health = build_health_status(state)
    {:reply, health, state}
  end

  @impl true
  def handle_cast({:increment_metric, type}, state) do
    {:ok, new_state} = MetricsTracker.increment_metric(state, type)
    {:noreply, new_state}
  end

  @impl true
  def handle_cast({:mark_notification_sent, type}, state) do
    {:ok, new_state} = MetricsTracker.mark_notification_sent(state, type)
    {:noreply, new_state}
  end

  @impl true
  def handle_cast({:update_health, service, status}, state) do
    new_state = update_service_health(state, service, status)
    {:noreply, new_state}
  end

  @impl true
  def handle_cast({:set_tracked_count, type, count}, state) do
    {:ok, new_state} = MetricsTracker.set_tracked_count(state, type, count)
    {:noreply, new_state}
  end

  # ──────────────────────────────────────────────────────────────────────────────
  # Private Helpers
  # ──────────────────────────────────────────────────────────────────────────────

  defp build_health_status(state) do
    uptime_seconds =
      case state.metrics.startup_time do
        nil -> 0
        startup_time -> TimeUtils.elapsed_seconds(startup_time)
      end

    %{
      status: :healthy,
      uptime: TimeUtils.format_uptime(uptime_seconds),
      uptime_seconds: uptime_seconds,
      services: state.health,
      metrics: %{
        notifications: state.metrics.notifications,
        processing: state.metrics.processing,
        systems_count: state.metrics.systems_count,
        characters_count: state.metrics.characters_count
      }
    }
  end

  defp update_service_health(state, service, status) do
    health = Map.put(state.health, service, status)
    %{state | health: health}
  end

  # ──────────────────────────────────────────────────────────────────────────────
  # ServiceBehaviour Implementation
  # ──────────────────────────────────────────────────────────────────────────────

  # Override helper functions from ServiceBehaviour
  defp service_dependencies do
    [
      :cache,
      :persistent_values,
      :discord
    ]
  end

  defp optional_service_dependencies do
    [
      :license_service,
      :schedulers
    ]
  end

  defp check_health_status do
    case Process.whereis(__MODULE__) do
      nil ->
        :unhealthy

      pid when is_pid(pid) ->
        try do
          # Quick health check by calling get_stats with short timeout
          case GenServer.call(__MODULE__, :get_stats, 1000) do
            %{} -> :healthy
            _ -> :degraded
          end
        catch
          :exit, _ -> :degraded
        end
    end
  end

  defp health_check_details do
    try do
      stats = get_stats()

      %{
        services: Map.keys(stats.health || %{}),
        metrics: %{
          notifications_sent: get_in(stats, [:notifications, :total]) || 0,
          processing_active: get_in(stats, [:processing, :active]) || false,
          uptime: stats.uptime || "unknown"
        },
        memory_mb:
          case Process.info(self(), :memory) do
            {_, memory_bytes} -> div(memory_bytes, 1024 * 1024)
            nil -> 0
          end
      }
    catch
      _ ->
        %{error: "Unable to retrieve health details"}
    end
  end

  @impl true
  def get_metrics do
    try do
      stats = get_stats()

      %{
        notifications: stats.notifications || %{},
        processing: stats.processing || %{},
        health: stats.health || %{},
        uptime_seconds: calculate_uptime()
      }
    catch
      _ ->
        %{error: "Unable to retrieve metrics"}
    end
  end

  @impl true
  def validate_config(_config) do
    # ApplicationService doesn't require specific config validation for now
    :ok
  end

  @impl true
  def configure(config) do
    apply_configuration(config)
  end

  @impl true
  def diagnostics do
    %{
      service_info: service_info(),
      health: health_check(),
      config: get_config_safe(),
      metrics: get_metrics(),
      dependencies: %{
        required: service_dependencies(),
        optional: optional_service_dependencies()
      }
    }
  end

  @impl true
  def get_config do
    WandererNotifier.Shared.Config.ConfigurationManager.get_service_config(:application_service)
    |> case do
      {:ok, config} -> config
      {:error, _} -> %{}
    end
  end

  defp apply_configuration(config) do
    Logger.info("Applying configuration to ApplicationService",
      config_keys: Map.keys(config),
      category: :config
    )

    # For now, configuration changes don't require runtime updates
    # This could be extended to support dynamic configuration changes
    :ok
  end
end
