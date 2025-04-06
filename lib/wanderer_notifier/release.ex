defmodule WandererNotifier.Release do
  @moduledoc """
  Release-specific functions for database management.
  Used in production for migrations and database setup.
  """
  alias WandererNotifier.Logger.Logger, as: AppLogger

  @app :wanderer_notifier

  @doc """
  Creates the database if it doesn't exist.
  """
  def createdb do
    AppLogger.startup_info("Checking if database exists")

    try do
      Enum.each(repos(), fn repo ->
        case repo.__adapter__().storage_up(repo.config()) do
          :ok ->
            AppLogger.startup_info("Database created successfully")

          {:error, :already_up} ->
            AppLogger.startup_info("Database already exists")

          {:error, {:logger, _}} ->
            AppLogger.startup_info(
              "Database status check completed with logger initialization warning"
            )

          {:error, error} ->
            AppLogger.startup_warn("Failed to create database", error: inspect(error))
        end
      end)
    rescue
      e ->
        AppLogger.startup_error("Exception during database creation", error: Exception.message(e))
    end
  end

  @doc """
  Runs pending migrations.
  """
  def migrate do
    AppLogger.startup_info("Running migrations")

    try do
      Enum.each(repos(), fn repo ->
        case Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :up, all: true)) do
          {:ok, _, _} ->
            AppLogger.startup_info("Migrations completed successfully", repo: inspect(repo))

          {:error, {:logger, _}} = error ->
            # Handle logger error but continue with migrations
            AppLogger.startup_info("Migration completed with logger warning",
              error: inspect(error)
            )

          other ->
            AppLogger.startup_info("Migration completed", result: inspect(other))
        end
      end)

      AppLogger.startup_info("All migrations completed")
    rescue
      e ->
        AppLogger.startup_error("Exception during migration",
          error: Exception.message(e),
          stacktrace: Exception.format_stacktrace(__STACKTRACE__)
        )

        # Re-raise to stop the migration process with proper error
        reraise e, __STACKTRACE__
    end
  end

  @doc """
  Rollback migrations.
  """
  def rollback(repo, version) do
    AppLogger.startup_info("Rolling back migrations", version: version)

    case Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :down, to: version)) do
      {:ok, _, _} ->
        AppLogger.startup_info("Rollback completed successfully", version: version)

      {:error, {:logger, _}} = error ->
        # Handle logger error but continue
        AppLogger.startup_info("Rollback completed with logger warning", error: inspect(error))

      other ->
        AppLogger.startup_info("Rollback completed", result: inspect(other))
    end
  rescue
    e ->
      AppLogger.startup_error("Exception during rollback",
        error: Exception.message(e),
        stacktrace: Exception.format_stacktrace(__STACKTRACE__)
      )

      # Re-raise to stop the rollback process with proper error
      reraise e, __STACKTRACE__
  end

  defp repos do
    # First, ensure the application is loaded
    Application.load(@app)

    # Try to get ecto_repos config, with fallback to avoid crashes
    case Application.fetch_env(@app, :ecto_repos) do
      {:ok, repos} ->
        repos

      :error ->
        AppLogger.startup_warn("Could not find ecto_repos configuration, using default")
        [WandererNotifier.Data.Repo]
    end
  rescue
    e ->
      AppLogger.startup_error("Error loading application config", error: Exception.message(e))
      # Default to known repo
      [WandererNotifier.Data.Repo]
  end
end
