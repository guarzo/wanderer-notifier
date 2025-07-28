defmodule WandererNotifier.Application.Supervisors.ExternalAdaptersSupervisor do
  @moduledoc """
  Supervisor for external service adapters.
  Manages HTTP clients, Discord connections, and other external integrations.
  """
  use Supervisor

  require Logger

  def start_link(init_arg) do
    Supervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  @impl true
  def init(_init_arg) do
    Logger.info("Starting External Adapters Supervisor", category: :startup)

    children = [
      # HTTP client pool supervisor
      {Task.Supervisor, name: WandererNotifier.HttpTaskSupervisor},

      # License service for premium features
      {WandererNotifier.Domains.License.Service, []}
    ]

    # Use rest_for_one strategy so if HTTP supervisor crashes,
    # dependent services also restart
    Supervisor.init(children, strategy: :rest_for_one)
  end
end
