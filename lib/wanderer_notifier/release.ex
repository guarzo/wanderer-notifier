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
    AppLogger.persistence_info("Checking if database exists")

    for repo <- repos() do
      case repo.__adapter__().storage_up(repo.config()) do
        :ok ->
          AppLogger.persistence_info("Database created successfully")

        {:error, :already_up} ->
          AppLogger.persistence_info("Database already exists")

        {:error, error} ->
          AppLogger.persistence_warn("Failed to create database", error: inspect(error))
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
