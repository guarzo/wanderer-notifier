defmodule WandererNotifier.Repo do
  use Ecto.Repo,
    otp_app: :wanderer_notifier,
    adapter: Ecto.Adapters.Postgres

  require Logger

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
            Logger.error("Database health check failed: #{inspect(error)}")
            {:error, error}
        end
      rescue
        e ->
          Logger.error("Database health check exception: #{Exception.message(e)}")
          {:error, e}
      end
    else
      Logger.error("Database health check failed: Repo not started")
      {:error, "Repo not started"}
    end
  end
end
