defmodule WandererNotifier.Repo do
  use Ecto.Repo,
    otp_app: :wanderer_notifier,
    adapter: Ecto.Adapters.Postgres

  alias Ecto.Adapters.SQL
  alias WandererNotifier.Config.Database
  alias WandererNotifier.Logger, as: AppLogger

  @doc """
  Custom init function to dynamically configure the repo using
  our standardized Database configuration module.
  """
  def init(_type, config) do
    # Get the configuration from our Database module
    # This approach allows us to standardize database connection settings
    # and move away from direct environment variable access
    db_config = Database.config()

    # Merge the standard configuration with any extras from the application config
    config =
      config
      |> Keyword.merge(
        username: db_config.username,
        password: db_config.password,
        hostname: db_config.hostname,
        database: db_config.database,
        port: db_config.port,
        pool_size: db_config.pool_size
      )

    {:ok, config}
  end

  @doc """
  Returns a list of PostgreSQL extensions that have already been installed.
  This is used by AshPostgres.MigrationGenerator for code generation.
  """
  def installed_extensions do
    case SQL.query(__MODULE__, "SELECT extname FROM pg_extension") do
      {:ok, result} ->
        Enum.map(result.rows, fn [ext] -> ext end)

      _ ->
        []
    end
  rescue
    _ -> []
  end

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

    try do
      # First check if the repo is started
      if Process.whereis(__MODULE__) do
        # Execute a simple query to check connectivity
        case SQL.query(__MODULE__, "SELECT 1") do
          {:ok, _} ->
            end_time = System.monotonic_time(:millisecond)
            ping_time = end_time - start_time
            {:ok, ping_time}

          {:error, error} ->
            AppLogger.persistence_error("Database health check failed", error: inspect(error))
            {:error, error}
        end
      else
        AppLogger.persistence_error("Database health check failed", reason: "Repo not started")
        {:error, "Repo not started"}
      end
    rescue
      e ->
        AppLogger.persistence_error("Database health check exception",
          error: Exception.message(e)
        )

        {:error, e}
    end
  end
end
