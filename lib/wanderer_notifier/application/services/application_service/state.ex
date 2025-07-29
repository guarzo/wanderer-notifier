defmodule WandererNotifier.Application.Services.ApplicationService.State do
  @moduledoc """
  State management for the ApplicationService.
  
  Consolidates state from multiple services (Stats, Dependencies, NotificationService)
  into a single, coherent state structure.
  """
  
  
  @type metrics :: %{
    notifications: %{
      total: non_neg_integer(),
      kills: non_neg_integer(),
      systems: non_neg_integer(),
      characters: non_neg_integer()
    },
    processing: %{
      kills_processed: non_neg_integer(),
      kills_notified: non_neg_integer()
    },
    first_notifications: %{
      kill: boolean(),
      character: boolean(),
      system: boolean()
    },
    startup_time: DateTime.t() | nil,
    systems_count: non_neg_integer(),
    characters_count: non_neg_integer(),
    counters: map()
  }
  
  @type dependencies :: %{
    overrides: map(),
    defaults: map()
  }
  
  @type health :: %{
    websocket: map(),
    sse: map(),
    cache: map(),
    discord: map()
  }
  
  @type t :: %__MODULE__{
    metrics: metrics(),
    dependencies: dependencies(),
    health: health(),
    config: keyword()
  }
  
  defstruct metrics: %{
              notifications: %{
                total: 0,
                kills: 0,
                systems: 0,
                characters: 0
              },
              processing: %{
                kills_processed: 0,
                kills_notified: 0
              },
              first_notifications: %{
                kill: true,
                character: true,
                system: true
              },
              startup_time: nil,
              systems_count: 0,
              characters_count: 0,
              counters: %{}
            },
            dependencies: %{
              overrides: %{},
              defaults: %{}
            },
            health: %{
              websocket: %{status: :unknown},
              sse: %{status: :unknown},
              cache: %{status: :unknown},
              discord: %{status: :unknown}
            },
            config: []
  
  @doc """
  Creates a new ApplicationService state.
  """
  @spec new(keyword()) :: t()
  def new(opts \\ []) do
    startup_time = DateTime.utc_now()
    
    %__MODULE__{
      metrics: %{
        notifications: %{total: 0, kills: 0, systems: 0, characters: 0},
        processing: %{kills_processed: 0, kills_notified: 0},
        first_notifications: %{kill: true, character: true, system: true},
        startup_time: startup_time,
        systems_count: 0,
        characters_count: 0,
        counters: %{}
      },
      config: opts
    }
  end
  
  @doc """
  Updates metrics in the state.
  """
  @spec update_metrics(t(), (metrics() -> metrics())) :: t()
  def update_metrics(%__MODULE__{} = state, update_fn) when is_function(update_fn, 1) do
    new_metrics = update_fn.(state.metrics)
    %{state | metrics: new_metrics}
  end
  
  @doc """
  Updates dependencies in the state.
  """
  @spec update_dependencies(t(), (dependencies() -> dependencies())) :: t()
  def update_dependencies(%__MODULE__{} = state, update_fn) when is_function(update_fn, 1) do
    new_dependencies = update_fn.(state.dependencies)
    %{state | dependencies: new_dependencies}
  end
  
  @doc """
  Updates health status in the state.
  """
  @spec update_health(t(), (health() -> health())) :: t()
  def update_health(%__MODULE__{} = state, update_fn) when is_function(update_fn, 1) do
    new_health = update_fn.(state.health)
    %{state | health: new_health}
  end
end