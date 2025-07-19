defmodule WandererNotifier.Application.Supervisors.Schedulers.Scheduler do
  @moduledoc """
  Behaviour for all background jobs.

  Each scheduler implements:
    - `config/0` returning %{type: :cron | :interval, spec: String.t()}
    - `run/0` which executes the job.
  """

  @type config :: %{type: :cron, spec: String.t()} | %{type: :interval, spec: integer()}

  @callback config() :: config()
  @callback run() :: :ok | {:error, term()}
end
