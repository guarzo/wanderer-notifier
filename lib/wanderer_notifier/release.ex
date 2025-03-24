defmodule WandererNotifier.Release do
  @moduledoc """
  Release-specific functions for database management.
  Used in production for migrations and database setup.
  """
  require Logger
  alias WandererNotifier.Logger, as: AppLogger

  @app :wanderer_notifier

  @doc """
  Creates the database if it doesn't exist.
  """
  def createdb do
    Logger.info("Checking if database exists")

    for repo <- repos() do
      try do
        case repo.__adapter__().storage_up(repo.config()) do
          :ok ->
            Logger.info("Database created successfully")

          {:error, :already_up} ->
            Logger.info("Database already exists")

          {:error, {:logger, _}} ->
            Logger.info("Database status check completed with logger initialization warning")

          {:error, error} ->
            Logger.warn("Failed to create database: #{inspect(error)}")
        end
      rescue
        e ->
          Logger.error("Exception during database creation: #{inspect(e)}")
      end
    end
  end

  @doc """
  Runs pending migrations.
  """
  def migrate do
    Logger.info("Running migrations")

    for repo <- repos() do
      try do
        case Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :up, all: true)) do
          {:ok, _, _} ->
            Logger.info("Migrations for #{inspect(repo)} completed successfully")

          {:error, {:logger, _}} = error ->
            # Handle logger error but continue with migrations
            Logger.info("Migration completed with logger warning: #{inspect(error)}")

          other ->
            Logger.info("Migration returned: #{inspect(other)}")
        end
      rescue
        e ->
          Logger.error("Exception during migration: #{inspect(e)}")
          # Re-raise to stop the migration process with proper error
          reraise e, __STACKTRACE__
      end
    end

    Logger.info("All migrations completed")
  end

  @doc """
  Rollback migrations.
  """
  def rollback(repo, version) do
    Logger.info("Rolling back migrations to version #{version}")

    try do
      case Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :down, to: version)) do
        {:ok, _, _} ->
          Logger.info("Rollback to version #{version} completed successfully")

        {:error, {:logger, _}} = error ->
          # Handle logger error but continue
          Logger.info("Rollback completed with logger warning: #{inspect(error)}")

        other ->
          Logger.info("Rollback returned: #{inspect(other)}")
      end
    rescue
      e ->
        Logger.error("Exception during rollback: #{inspect(e)}")
        # Re-raise to stop the rollback process with proper error
        reraise e, __STACKTRACE__
    end
  end

  defp repos do
    # First, ensure the application is loaded
    try do
      Application.load(@app)

      # Try to get ecto_repos config, with fallback to avoid crashes
      case Application.fetch_env(@app, :ecto_repos) do
        {:ok, repos} ->
          repos

        :error ->
          Logger.warn("Could not find ecto_repos configuration, using default")
          [WandererNotifier.Repo]
      end
    rescue
      e ->
        Logger.error("Error loading application config: #{inspect(e)}")
        # Default to known repo
        [WandererNotifier.Repo]
    end
  end
end
