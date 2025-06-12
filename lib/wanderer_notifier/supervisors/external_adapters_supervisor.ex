defmodule WandererNotifier.Supervisors.ExternalAdaptersSupervisor do
  @moduledoc """
  Supervisor for external service adapters.
  Manages HTTP clients, Discord connections, and other external integrations.
  """
  use Supervisor

  alias WandererNotifier.Logger.Logger, as: AppLogger

  def start_link(init_arg) do
    Supervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  @impl true
  def init(_init_arg) do
    AppLogger.startup_info("Starting External Adapters Supervisor")

    children = [
      # HTTP client pool supervisor
      {Task.Supervisor, name: WandererNotifier.HttpTaskSupervisor},

      # Discord consumer (required by Nostrum)
      {WandererNotifier.NoopConsumer, []},

      # License service for premium features
      {WandererNotifier.License.Service, []}
    ]

    # Use rest_for_one strategy so if HTTP supervisor crashes,
    # dependent services also restart
    Supervisor.init(children, strategy: :rest_for_one)
  end
end
