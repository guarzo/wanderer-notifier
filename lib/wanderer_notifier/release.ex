defmodule WandererNotifier.Release do
  @moduledoc """
  Release-specific functions for database management.
  Used in production for migrations and database setup.
  """
  require Logger

  @app :wanderer_notifier

  @doc """
  Creates the database if it doesn't exist.
  """
  def createdb do
    Logger.info("Checking if database exists")

    try do
      Enum.each(repos(), fn repo ->
        case repo.__adapter__().storage_up(repo.config()) do
          :ok ->
            Logger.info("Database created successfully")

          {:error, :already_up} ->
            Logger.info("Database already exists")

          {:error, {:logger, _}} ->
            Logger.info("Database status check completed with logger initialization warning")

          {:error, error} ->
            Logger.warning("Failed to create database: #{inspect(error)}")
        end
      end)
    rescue
      e ->
        Logger.error("Exception during database creation: #{inspect(e)}")
    end
  end

  @doc """
  Runs pending migrations.
  """
  def migrate do
    Logger.info("Running migrations")

    try do
      Enum.each(repos(), fn repo ->
        case Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :up, all: true)) do
          {:ok, _, _} ->
            Logger.info("Migrations for #{inspect(repo)} completed successfully")

          {:error, {:logger, _}} = error ->
            # Handle logger error but continue with migrations
            Logger.info("Migration completed with logger warning: #{inspect(error)}")

          other ->
            Logger.info("Migration returned: #{inspect(other)}")
        end
      end)

      Logger.info("All migrations completed")
    rescue
      e ->
        Logger.error("Exception during migration: #{inspect(e)}")
        # Re-raise to stop the migration process with proper error
        reraise e, __STACKTRACE__
    end
  end

  @doc """
  Rollback migrations.
  """
  def rollback(repo, version) do
    Logger.info("Rolling back migrations to version #{version}")

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

  defp repos do
    # First, ensure the application is loaded
    Application.load(@app)

    # Try to get ecto_repos config, with fallback to avoid crashes
    case Application.fetch_env(@app, :ecto_repos) do
      {:ok, repos} ->
        repos

      :error ->
        Logger.warning("Could not find ecto_repos configuration, using default")
        [WandererNotifier.Data.Repo]
    end
  rescue
    e ->
      Logger.error("Error loading application config: #{inspect(e)}")
      # Default to known repo
      [WandererNotifier.Data.Repo]
  end
end
