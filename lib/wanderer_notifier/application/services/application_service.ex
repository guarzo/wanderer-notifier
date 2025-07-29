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
    GenServer.call(__MODULE__, {:get_dependency, name, default})
  end
  
  # ── Notification Coordination ──
  
  @doc """
  Processes a notification through the appropriate channels.
  """
  @spec process_notification(map(), keyword()) :: service_result()
  def process_notification(notification, opts \\ []) do
    GenServer.call(__MODULE__, {:process_notification, notification, opts})
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
    dependency = DependencyManager.get_dependency(state, name, default)
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
end