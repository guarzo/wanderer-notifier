defmodule WandererNotifier.Application.Services.ApplicationService.DependencyManager do
  @moduledoc """
  Manages dependency injection for the ApplicationService.

  Provides a centralized way to resolve dependencies with support for:
  - Default implementations
  - Test overrides via application config
  - Runtime dependency swapping
  """

  alias WandererNotifier.Application.Services.ApplicationService.State

  @doc """
  Initializes the dependency manager with default mappings.
  """
  @spec initialize(State.t()) :: {:ok, State.t()}
  def initialize(state) do
    defaults = %{
      esi_service: WandererNotifier.Infrastructure.Adapters.ESI.Service,
      esi_client: WandererNotifier.Infrastructure.Adapters.ESI.Client,
      http_client: WandererNotifier.Infrastructure.Http,
      killmail_pipeline: WandererNotifier.Domains.Killmail.Pipeline,
      logger_module: WandererNotifier.Shared.Logger.Logger,
      cache_name: :wanderer_cache
    }

    # Load any configured overrides
    overrides = load_dependency_overrides()

    new_state =
      State.update_dependencies(state, fn deps ->
        %{deps | defaults: defaults, overrides: overrides}
      end)

    {:ok, new_state}
  end

  @doc """
  Gets a dependency by name, with fallback to default.
  """
  @spec get_dependency(State.t(), atom(), module()) :: module()
  def get_dependency(state, name, fallback_default) do
    # Check overrides first (for testing)
    case Map.get(state.dependencies.overrides, name) do
      nil ->
        # Then check defaults
        case Map.get(state.dependencies.defaults, name) do
          nil -> fallback_default
          default -> default
        end

      override ->
        override
    end
  end

  @doc """
  Updates a dependency override (useful for testing).
  """
  @spec set_dependency_override(State.t(), atom(), module()) :: State.t()
  def set_dependency_override(state, name, module) do
    State.update_dependencies(state, fn deps ->
      overrides = Map.put(deps.overrides, name, module)
      %{deps | overrides: overrides}
    end)
  end

  @doc """
  Clears all dependency overrides.
  """
  @spec clear_dependency_overrides(State.t()) :: State.t()
  def clear_dependency_overrides(state) do
    State.update_dependencies(state, fn deps ->
      %{deps | overrides: %{}}
    end)
  end

  # ──────────────────────────────────────────────────────────────────────────────
  # Private Helpers
  # ──────────────────────────────────────────────────────────────────────────────

  defp load_dependency_overrides do
    # Load dependency overrides from application config
    # This allows tests to swap out dependencies by setting config
    Application.get_env(:wanderer_notifier, :dependency_overrides, %{})
  end
end
