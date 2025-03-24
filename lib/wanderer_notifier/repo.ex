defmodule WandererNotifier.Repo do
  use Ecto.Repo,
    otp_app: :wanderer_notifier,
    adapter: Ecto.Adapters.Postgres

  alias WandererNotifier.Logger, as: AppLogger

  @doc """
  Required by Ash framework for transaction handling.
  Returns whether atomic actions should be disabled.
  For now, we're disabling atomic actions since we don't need them.
  """
  def disable_atomic_actions?, do: true

  @doc """
  Required by Ash framework for transaction handling.
  Determines whether or not transactions should be preferred.
  """
  def prefer_transaction?, do: true

  @doc """
  Called by Ash.Postgres when a transaction begins.
  """
  def on_transaction_begin(_opts), do: :ok

  @doc """
  Called by Ash.Postgres when a transaction rolls back.
  """
  def on_transaction_rollback(_opts, _err), do: :ok

  @doc """
  Called by Ash.Postgres when a transaction commits.
  """
  def on_transaction_commit(_opts), do: :ok

  @doc """
  Required by Ash.Postgres for constraint handling.
  Returns the default constraint match type for a given constraint type.
  """
  def default_constraint_match_type(_constraint_type, _name), do: :exact

  @doc """
  Performs a health check on the database connection.
  Returns {:ok, ping_time_ms} if successful or {:error, reason} if not.
  """
  def health_check do
    start_time = System.monotonic_time(:millisecond)

    # First check if the repo is started
    if Process.whereis(__MODULE__) do
      try do
        # Execute a simple query to check connectivity
        case Ecto.Adapters.SQL.query(__MODULE__, "SELECT 1") do
          {:ok, _} ->
            end_time = System.monotonic_time(:millisecond)
            ping_time = end_time - start_time
            {:ok, ping_time}

          {:error, error} ->
            AppLogger.persistence_error("Database health check failed", error: inspect(error))
            {:error, error}
        end
      rescue
        e ->
          AppLogger.persistence_error("Database health check exception",
            error: Exception.message(e)
          )

          {:error, e}
      end
    else
      AppLogger.persistence_error("Database health check failed", reason: "Repo not started")
      {:error, "Repo not started"}
    end
  end
end
