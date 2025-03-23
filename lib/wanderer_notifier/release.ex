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
    Logger.info("Checking if database exists...")

    for repo <- repos() do
      with {:error, error} <- repo.__adapter__().storage_up(repo.config()) do
        Logger.warning("Failed to create database: #{inspect(error)}")
      else
        :ok -> Logger.info("Database created successfully")
        {:error, :already_up} -> Logger.info("Database already exists")
      end
    end
  end

  @doc """
  Runs pending migrations.
  """
  def migrate do
    Logger.info("Running migrations...")

    for repo <- repos() do
      {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :up, all: true))
    end

    Logger.info("Migrations completed successfully")
  end

  @doc """
  Rollback migrations.
  """
  def rollback(repo, version) do
    Logger.info("Rolling back to version #{version}...")

    {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :down, to: version))

    Logger.info("Rollback completed")
  end

  defp repos do
    Application.load(@app)
    Application.fetch_env!(@app, :ecto_repos)
  end
end
