defmodule WandererNotifier.Application do
  @moduledoc """
  The WandererNotifier OTP application.
  """
  use Application
  require Logger

  @impl true
  def start(_type, _args) do
    Logger.info("Starting WandererNotifier application...")

    children = [
      {WandererNotifier.Cache.Repository, []},
      {WandererNotifier.Service, []}
    ]

    opts = [strategy: :one_for_one, name: WandererNotifier.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
