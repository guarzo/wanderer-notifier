defmodule ChainKills.Application do
  @moduledoc """
  The ChainKills OTP application.
  """
  use Application
  require Logger

  def start(_type, _args) do
    Logger.info("Starting ChainKills application...")

    children = [
      {ChainKills.Cache.Repository, []},
      {ChainKills.Service, []}
    ]

    opts = [strategy: :one_for_one, name: ChainKills.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
