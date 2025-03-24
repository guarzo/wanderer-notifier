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
    AppLogger.persistence_info("Running migrations")

    for repo <- repos() do
      {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :up, all: true))
    end

    AppLogger.persistence_info("Migrations completed successfully")
  end

  @doc """
  Rollback migrations.
  """
  def rollback(repo, version) do
    AppLogger.persistence_info("Rolling back migrations", target_version: version)

    {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :down, to: version))

    AppLogger.persistence_info("Rollback completed")
  end

  defp repos do
    Application.load(@app)
    Application.fetch_env!(@app, :ecto_repos)
  end
end
