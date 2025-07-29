defmodule WandererNotifier.Application.Services.DependencyRegistry do
  @moduledoc """
  Simplified dependency injection registry for WandererNotifier.

  This module provides a lightweight dependency injection system that:
  - Registers service implementations by interface
  - Supports runtime dependency substitution (useful for testing)
  - Provides clear dependency resolution with fallbacks
  - Maintains service relationship mapping for health monitoring

  ## Usage

      # Register an implementation
      DependencyRegistry.register(:cache, WandererNotifier.Infrastructure.Cache)
      
      # Resolve a dependency
      cache_module = DependencyRegistry.resolve(:cache)
      
      # Use in tests
      DependencyRegistry.register(:cache, MockCache)
  """

  use GenServer
  require Logger

  @type dependency_key :: atom()
  @type implementation :: module()
  @type dependency_config :: %{
          implementation: implementation(),
          started_at: DateTime.t(),
          health_check: (-> boolean()) | nil,
          description: String.t()
        }

  # ──────────────────────────────────────────────────────────────────────────────
  # Public API
  # ──────────────────────────────────────────────────────────────────────────────

  @doc """
  Starts the dependency registry.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Registers a dependency implementation.
  """
  @spec register(dependency_key(), implementation(), keyword()) :: :ok
  def register(key, implementation, opts \\ []) do
    GenServer.call(__MODULE__, {:register, key, implementation, opts})
  end

  @doc """
  Resolves a dependency, returning the registered implementation or default.
  """
  @spec resolve(dependency_key(), implementation() | nil) :: implementation() | nil
  def resolve(key, default \\ nil) do
    GenServer.call(__MODULE__, {:resolve, key, default})
  end

  @doc """
  Lists all registered dependencies.
  """
  @spec list_dependencies() :: [{dependency_key(), dependency_config()}]
  def list_dependencies do
    GenServer.call(__MODULE__, :list_dependencies)
  end

  @doc """
  Checks the health of all registered dependencies.
  """
  @spec health_check() :: %{dependency_key() => boolean()}
  def health_check do
    GenServer.call(__MODULE__, :health_check)
  end

  @doc """
  Unregisters a dependency (useful for testing).
  """
  @spec unregister(dependency_key()) :: :ok
  def unregister(key) do
    GenServer.call(__MODULE__, {:unregister, key})
  end

  @doc """
  Clears all dependencies (useful for testing).
  """
  @spec clear() :: :ok
  def clear do
    GenServer.call(__MODULE__, :clear)
  end

  # ──────────────────────────────────────────────────────────────────────────────
  # GenServer Implementation
  # ──────────────────────────────────────────────────────────────────────────────

  @impl true
  def init(_opts) do
    Logger.debug("Starting dependency registry", category: :startup)

    # Register default dependencies
    state = %{}
    state = register_default_dependencies(state)

    Logger.info("Dependency registry initialized",
      dependencies_count: map_size(state),
      category: :startup
    )

    {:ok, state}
  end

  @impl true
  def handle_call({:register, key, implementation, opts}, _from, state) do
    description = Keyword.get(opts, :description, "#{implementation}")
    health_check = Keyword.get(opts, :health_check)

    config = %{
      implementation: implementation,
      started_at: DateTime.utc_now(),
      health_check: health_check,
      description: description
    }

    new_state = Map.put(state, key, config)

    Logger.debug("Dependency registered",
      key: key,
      implementation: implementation,
      category: :dependency
    )

    {:reply, :ok, new_state}
  end

  @impl true
  def handle_call({:resolve, key, default}, _from, state) do
    result =
      case Map.get(state, key) do
        nil ->
          if default do
            Logger.debug("Using default implementation for dependency",
              key: key,
              default: default,
              category: :dependency
            )

            default
          else
            Logger.warning("Dependency not found and no default provided",
              key: key,
              category: :dependency
            )

            nil
          end

        %{implementation: implementation} ->
          implementation
      end

    {:reply, result, state}
  end

  @impl true
  def handle_call(:list_dependencies, _from, state) do
    deps = Enum.map(state, fn {key, config} -> {key, config} end)
    {:reply, deps, state}
  end

  @impl true
  def handle_call(:health_check, _from, state) do
    health_results =
      state
      |> Enum.map(fn {key, config} -> {key, check_dependency_health(config)} end)
      |> Map.new()

    {:reply, health_results, state}
  end

  @impl true
  def handle_call({:unregister, key}, _from, state) do
    new_state = Map.delete(state, key)

    Logger.debug("Dependency unregistered",
      key: key,
      category: :dependency
    )

    {:reply, :ok, new_state}
  end

  @impl true
  def handle_call(:clear, _from, _state) do
    Logger.debug("All dependencies cleared", category: :dependency)
    {:reply, :ok, %{}}
  end

  # ──────────────────────────────────────────────────────────────────────────────
  # Default Dependencies Registration
  # ──────────────────────────────────────────────────────────────────────────────

  defp register_default_dependencies(state) do
    default_deps = [
      # Infrastructure
      {:cache, WandererNotifier.Infrastructure.Cache, "Application cache system"},
      {:http, WandererNotifier.Infrastructure.Http, "HTTP client for external services"},

      # Core Services
      {:config, WandererNotifier.Shared.Config, "Application configuration"},
      {:logger, Logger, "Application logging"},

      # Business Logic
      {:api_context, WandererNotifier.Contexts.ApiContext, "External API integration context"},
      {:notification_context, WandererNotifier.Contexts.NotificationContext,
       "Notification handling context"},
      {:processing_context, WandererNotifier.Contexts.ProcessingContext,
       "Data processing context"},

      # External Integrations  
      {:discord, WandererNotifier.Domains.Notifications.Notifiers.Discord.Notifier,
       "Discord integration"},
      {:esi, WandererNotifier.Infrastructure.Adapters.ESI.Service, "EVE Swagger Interface"},

      # Specialized Services
      {:deduplication, WandererNotifier.Domains.Notifications.Deduplication,
       "Notification deduplication"},
      {:license, WandererNotifier.Domains.License.LicenseService, "License validation service"}
    ]

    Enum.reduce(default_deps, state, fn {key, impl, desc}, acc ->
      config = %{
        implementation: impl,
        started_at: DateTime.utc_now(),
        health_check: build_default_health_check(impl),
        description: desc
      }

      Map.put(acc, key, config)
    end)
  end

  defp build_default_health_check(module) do
    fn ->
      # Basic health check: module is loaded and has expected functions
      case Code.ensure_loaded(module) do
        {:module, ^module} -> true
        _ -> false
      end
    end
  end

  defp check_dependency_health(%{health_check: nil}), do: true

  defp check_dependency_health(%{health_check: health_check}) when is_function(health_check) do
    try do
      health_check.()
    rescue
      _ -> false
    end
  end

  defp check_dependency_health(_), do: true
end
