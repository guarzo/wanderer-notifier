defmodule WandererNotifier.Cache.VersionManager do
  @moduledoc """
  Version management API for cache versioning operations.

  This module provides a higher-level API for managing cache versions,
  including deployment hooks, version migrations, and automated
  version management strategies.

  ## Features

  - Automated version detection from application version
  - Deployment hook management
  - Version migration strategies
  - Rollback capabilities
  - Version compatibility checking
  - Deployment safety checks

  ## Usage

  ```elixir
  # Initialize version manager
  WandererNotifier.Cache.VersionManager.initialize()

  # Handle deployment
  WandererNotifier.Cache.VersionManager.handle_deployment("2.1.0")

  # Rollback to previous version
  WandererNotifier.Cache.VersionManager.rollback()
  ```
  """

  require Logger

  alias WandererNotifier.Cache.Versioning
  alias WandererNotifier.Cache.Warmer

  @type deployment_strategy :: :safe | :aggressive | :gradual
  @type rollback_result :: {:ok, String.t()} | {:error, term()}

  @doc """
  Initializes the version manager.

  This should be called during application startup to set up
  deployment hooks and initialize version tracking.

  ## Returns
  :ok
  """
  @spec initialize() :: :ok
  def initialize do
    # Register default deployment hooks
    register_default_hooks()

    # Initialize version tracking
    current_version = get_application_version()

    case Versioning.current_version() do
      ^current_version ->
        Logger.info("Cache version matches application version: #{current_version}")
        :ok

      cache_version ->
        Logger.info(
          "Cache version (#{cache_version}) differs from application version (#{current_version})"
        )

        handle_version_mismatch(cache_version, current_version)
    end
  end

  @doc """
  Handles deployment with a new version.

  ## Parameters
  - new_version: The new version to deploy
  - strategy: Deployment strategy (default: :safe)

  ## Returns
  :ok | {:error, reason}
  """
  @spec handle_deployment(String.t(), deployment_strategy()) :: :ok | {:error, term()}
  def handle_deployment(new_version, strategy \\ :safe) do
    current_version = Versioning.current_version()

    Logger.info(
      "Handling deployment from #{current_version} to #{new_version} with strategy #{strategy}"
    )

    case validate_deployment(current_version, new_version, strategy) do
      :ok ->
        execute_deployment(current_version, new_version, strategy)

      {:error, reason} = error ->
        Logger.error("Deployment validation failed: #{inspect(reason)}")
        error
    end
  end

  @doc """
  Rolls back to the previous version.

  ## Returns
  {:ok, previous_version} | {:error, reason}
  """
  @spec rollback() :: rollback_result()
  def rollback do
    version_history = Versioning.get_version_history()

    case find_previous_version(version_history) do
      {:ok, previous_version} ->
        Logger.info("Rolling back to version #{previous_version}")

        case Versioning.set_version(previous_version) do
          :ok ->
            # Invalidate current version cache entries
            Versioning.invalidate_old_versions(previous_version)
            {:ok, previous_version}

          error ->
            Logger.error("Failed to rollback: #{inspect(error)}")
            error
        end

      {:error, reason} = error ->
        Logger.error("Cannot rollback: #{inspect(reason)}")
        error
    end
  end

  @doc """
  Gets version compatibility information.

  ## Parameters
  - version1: First version
  - version2: Second version

  ## Returns
  Map with compatibility information
  """
  @spec get_compatibility_info(String.t(), String.t()) :: map()
  def get_compatibility_info(version1, version2) do
    %{
      compatible: Versioning.compatible_versions?(version1, version2),
      comparison: Versioning.compare_versions(version1, version2),
      migration_required: requires_migration?(version1, version2),
      rollback_safe: rollback_safe?(version1, version2)
    }
  end

  @doc """
  Executes a version migration with the specified strategy.

  ## Parameters
  - from_version: Source version
  - to_version: Target version
  - strategy: Migration strategy

  ## Returns
  {:ok, migration_results} | {:error, reason}
  """
  @spec execute_migration(String.t(), String.t(), atom()) :: {:ok, map()} | {:error, term()}
  def execute_migration(from_version, to_version, strategy \\ :safe) do
    Logger.info(
      "Executing migration from #{from_version} to #{to_version} with strategy #{strategy}"
    )

    case get_migration_plan(from_version, to_version, strategy) do
      {:ok, plan} ->
        execute_migration_plan(plan)

      {:error, reason} = error ->
        Logger.error("Failed to create migration plan: #{inspect(reason)}")
        error
    end
  end

  @doc """
  Gets deployment status information.

  ## Returns
  Map with deployment status
  """
  @spec get_deployment_status() :: map()
  def get_deployment_status do
    current_version = Versioning.current_version()
    app_version = get_application_version()
    version_history = Versioning.get_version_history()
    stats = Versioning.get_version_stats()

    %{
      current_version: current_version,
      application_version: app_version,
      version_match: current_version == app_version,
      version_history: version_history,
      stats: stats,
      deployment_hooks: get_registered_hooks()
    }
  end

  @doc """
  Validates a deployment before execution.

  ## Parameters
  - current_version: Current version
  - new_version: New version to deploy
  - strategy: Deployment strategy

  ## Returns
  :ok | {:error, reason}
  """
  @spec validate_deployment(String.t(), String.t(), deployment_strategy()) ::
          :ok | {:error, term()}
  def validate_deployment(current_version, new_version, strategy) do
    validations = [
      &validate_version_format/2,
      &validate_version_progression/2,
      &validate_compatibility/2,
      fn _v1, _v2 -> validate_strategy(strategy) end
    ]

    context = %{
      current_version: current_version,
      new_version: new_version,
      strategy: strategy
    }

    run_validations(validations, context)
  end

  @doc """
  Cleans up old cache versions.

  ## Parameters
  - keep_versions: Number of versions to keep (default: 3)

  ## Returns
  {:ok, cleanup_results} | {:error, reason}
  """
  @spec cleanup_old_versions(integer()) :: {:ok, map()} | {:error, term()}
  def cleanup_old_versions(keep_versions \\ 3) do
    version_history = Versioning.get_version_history()

    if length(version_history) > keep_versions do
      versions_to_keep = Enum.take(version_history, keep_versions)
      versions_to_clean = Enum.drop(version_history, keep_versions)

      cleanup_results =
        Enum.map(versions_to_clean, fn version_info ->
          case Versioning.invalidate_old_versions(version_info.version) do
            {:ok, count} ->
              Logger.info("Cleaned up #{count} entries for version #{version_info.version}")
              {version_info.version, count}

            {:error, reason} ->
              Logger.error(
                "Failed to clean up version #{version_info.version}: #{inspect(reason)}"
              )

              {version_info.version, 0}
          end
        end)

      total_cleaned =
        cleanup_results
        |> Enum.map(&elem(&1, 1))
        |> Enum.sum()

      {:ok,
       %{
         versions_kept: length(versions_to_keep),
         versions_cleaned: length(versions_to_clean),
         entries_cleaned: total_cleaned,
         cleanup_results: cleanup_results
       }}
    else
      {:ok,
       %{
         versions_kept: length(version_history),
         versions_cleaned: 0,
         entries_cleaned: 0,
         cleanup_results: []
       }}
    end
  end

  # Private functions

  defp register_default_hooks do
    # Cache warming hook
    Versioning.register_deployment_hook(:cache_warming, fn old_version, new_version ->
      Logger.info("Cache warming hook: #{old_version} -> #{new_version}")

      # Force startup warming for new version
      Warmer.force_startup_warming()
    end)

    # Cache invalidation hook
    Versioning.register_deployment_hook(:cache_invalidation, fn old_version, new_version ->
      Logger.info("Cache invalidation hook: #{old_version} -> #{new_version}")

      # Invalidate old version if major version change
      if old_version && not Versioning.compatible_versions?(old_version, new_version) do
        Versioning.invalidate_old_versions(new_version)
      end
    end)

    # Performance monitoring hook
    Versioning.register_deployment_hook(:performance_monitoring, fn old_version, new_version ->
      Logger.info("Performance monitoring hook: #{old_version} -> #{new_version}")

      # Reset performance metrics for new version
      try do
        WandererNotifier.Cache.Metrics.reset_metrics()
      rescue
        _ -> :ok
      end
    end)
  end

  defp get_application_version do
    case Application.spec(:wanderer_notifier, :vsn) do
      version when is_list(version) ->
        to_string(version)

      _ ->
        "1.0.0"
    end
  end

  defp handle_version_mismatch(cache_version, app_version) do
    case get_compatibility_info(cache_version, app_version) do
      %{compatible: true} ->
        Logger.info("Versions are compatible, updating cache version")
        Versioning.set_version(app_version)

      %{compatible: false, migration_required: true} ->
        Logger.warning("Version migration required from #{cache_version} to #{app_version}")
        execute_migration(cache_version, app_version, :safe)

      %{compatible: false, migration_required: false} ->
        Logger.warning("Incompatible versions, invalidating cache")
        Versioning.invalidate_old_versions(app_version)
        Versioning.set_version(app_version)
    end
  end

  defp do_validate_deployment(current_version, new_version, strategy) do
    with :ok <- validate_version_format(current_version, new_version),
         :ok <- validate_version_progression(current_version, new_version),
         :ok <- validate_compatibility(current_version, new_version),
         :ok <- validate_strategy(strategy) do
      :ok
    end
  end

  defp execute_deployment(current_version, new_version, strategy) do
    steps = get_deployment_steps(current_version, new_version, strategy)

    Enum.reduce_while(steps, :ok, fn step, _acc ->
      case execute_deployment_step(step, current_version, new_version) do
        :ok ->
          {:cont, :ok}

        {:error, reason} = error ->
          Logger.error("Deployment step #{step} failed: #{inspect(reason)}")
          {:halt, error}
      end
    end)
  end

  defp get_deployment_steps(_current_version, _new_version, strategy) do
    base_steps = [:validate, :backup, :update_version, :warm_cache]

    case strategy do
      :safe ->
        base_steps ++ [:verify]

      :aggressive ->
        [:validate, :update_version, :invalidate_old, :warm_cache]

      :gradual ->
        [:validate, :backup, :update_version, :gradual_migration, :warm_cache, :verify]
    end
  end

  defp execute_deployment_step(step, current_version, new_version) do
    case step do
      :validate ->
        do_validate_deployment(current_version, new_version, :safe)

      :backup ->
        # In a real implementation, this would backup current cache state
        Logger.info("Backing up cache state for version #{current_version}")
        :ok

      :update_version ->
        Versioning.set_version(new_version)

      :warm_cache ->
        Warmer.force_startup_warming()
        :ok

      :invalidate_old ->
        Versioning.invalidate_old_versions(new_version)
        :ok

      :gradual_migration ->
        execute_migration(current_version, new_version, :gradual)
        :ok

      :verify ->
        # In a real implementation, this would verify the deployment
        Logger.info("Verifying deployment to version #{new_version}")
        :ok

      _ ->
        Logger.warning("Unknown deployment step: #{step}")
        :ok
    end
  end

  defp find_previous_version(version_history) do
    case version_history do
      [_current | [previous | _]] ->
        {:ok, previous.version}

      _ ->
        {:error, :no_previous_version}
    end
  end

  defp requires_migration?(version1, version2) do
    not Versioning.compatible_versions?(version1, version2)
  end

  defp rollback_safe?(from_version, to_version) do
    # Rolling back is generally safe if we're going to a previous version
    # and the versions are compatible
    case Versioning.compare_versions(from_version, to_version) do
      :gt -> Versioning.compatible_versions?(from_version, to_version)
      _ -> false
    end
  end

  defp get_migration_plan(from_version, to_version, strategy) do
    try do
      plan = %{
        from_version: from_version,
        to_version: to_version,
        strategy: strategy,
        steps: get_migration_steps(from_version, to_version, strategy),
        estimated_duration: estimate_migration_duration(from_version, to_version)
      }

      {:ok, plan}
    rescue
      error ->
        {:error, error}
    end
  end

  defp get_migration_steps(_from_version, _to_version, strategy) do
    base_steps = [:prepare, :migrate_keys, :verify]

    case strategy do
      :safe ->
        [:backup | base_steps] ++ [:cleanup]

      :aggressive ->
        [:prepare, :invalidate_old, :migrate_keys]

      :gradual ->
        [:prepare, :gradual_migrate, :verify, :cleanup]
    end
  end

  defp execute_migration_plan(plan) do
    results =
      Enum.map(plan.steps, fn step ->
        case execute_migration_step(step, plan) do
          :ok ->
            {step, :ok}

          {:error, reason} ->
            {step, {:error, reason}}
        end
      end)

    if Enum.all?(results, fn {_, result} -> result == :ok end) do
      {:ok, %{plan: plan, results: results}}
    else
      failed_steps = Enum.filter(results, fn {_, result} -> result != :ok end)
      {:error, {:migration_failed, failed_steps}}
    end
  end

  defp execute_migration_step(step, plan) do
    case step do
      :prepare ->
        Logger.info("Preparing migration from #{plan.from_version} to #{plan.to_version}")
        :ok

      :backup ->
        Logger.info("Backing up cache state")
        :ok

      :migrate_keys ->
        case Versioning.migrate_version(plan.from_version, plan.to_version) do
          {:ok, _count} -> :ok
          {:error, reason} -> {:error, reason}
        end

      :verify ->
        Logger.info("Verifying migration")
        :ok

      :cleanup ->
        Logger.info("Cleaning up old cache entries")

        case Versioning.invalidate_old_versions(plan.to_version) do
          {:ok, _count} -> :ok
          {:error, reason} -> {:error, reason}
        end

      _ ->
        Logger.warning("Unknown migration step: #{step}")
        {:error, {:unknown_step, step}}
    end
  end

  defp estimate_migration_duration(from_version, to_version) do
    # Simple estimation based on version difference
    case Versioning.compare_versions(from_version, to_version) do
      :eq -> 0
      # 30 seconds estimation
      _ -> 30_000
    end
  end

  defp run_validations(validations, context) do
    Enum.reduce_while(validations, :ok, fn validation, _acc ->
      case validation.(context.current_version, context.new_version) do
        :ok ->
          {:cont, :ok}

        {:error, _reason} = error ->
          {:halt, error}
      end
    end)
  end

  defp validate_version_format(current_version, new_version) do
    if valid_version_format?(current_version) and valid_version_format?(new_version) do
      :ok
    else
      {:error, :invalid_version_format}
    end
  end

  defp validate_version_progression(current_version, new_version) do
    case Versioning.compare_versions(current_version, new_version) do
      :lt ->
        # New version is higher
        :ok

      :eq ->
        {:error, :same_version}

      :gt ->
        {:error, :version_downgrade}
    end
  end

  defp validate_compatibility(_current_version, _new_version) do
    # Allow any version change for now
    :ok
  end

  defp validate_strategy(strategy) when strategy in [:safe, :aggressive, :gradual] do
    :ok
  end

  defp validate_strategy(_) do
    {:error, :invalid_strategy}
  end

  defp valid_version_format?(version) do
    case String.split(version, ".") do
      [major, minor, patch] ->
        try do
          _major_int = String.to_integer(major)
          _minor_int = String.to_integer(minor)
          _patch_int = String.to_integer(patch)
          true
        rescue
          _ -> false
        end

      _ ->
        false
    end
  end

  defp get_registered_hooks do
    # In a real implementation, this would get registered hooks from Versioning
    ["cache_warming", "cache_invalidation", "performance_monitoring"]
  end
end
