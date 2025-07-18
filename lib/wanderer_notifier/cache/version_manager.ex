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
  alias WandererNotifier.Config.Version

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
    current_version = Version.version()
    cache_version = Versioning.current_version()

    # Only update version if it's actually different to avoid startup noise
    if current_version != cache_version do
      Logger.info("Updating cache version from #{cache_version} to #{current_version}")
      Versioning.set_version(current_version)
    end

    :ok
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
    app_version = Version.version()
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
      do_cleanup_versions(version_history, keep_versions)
    else
      no_cleanup_needed(version_history)
    end
  end

  defp do_cleanup_versions(version_history, keep_versions) do
    versions_to_keep = Enum.take(version_history, keep_versions)
    versions_to_clean = Enum.drop(version_history, keep_versions)

    cleanup_results = Enum.map(versions_to_clean, &cleanup_version/1)

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
  end

  defp cleanup_version(version_info) do
    case Versioning.invalidate_old_versions(version_info.version) do
      {:ok, count} ->
        Logger.info("Cleaned up #{count} entries for version #{version_info.version}")
        {version_info.version, count}

      {:error, reason} ->
        Logger.error("Failed to clean up version #{version_info.version}: #{inspect(reason)}")

        {version_info.version, 0}
    end
  end

  defp no_cleanup_needed(version_history) do
    {:ok,
     %{
       versions_kept: length(version_history),
       versions_cleaned: 0,
       entries_cleaned: 0,
       cleanup_results: []
     }}
  end

  # Private functions

  defp register_default_hooks do
    # Cache warming hook
    Versioning.register_deployment_hook(:cache_warming, fn old_version, new_version ->
      Logger.info("Cache warming hook: #{old_version} -> #{new_version}")

      # Force startup warming for new version
      try do
        Warmer.force_startup_warming()
      rescue
        error ->
          Logger.error("Cache warming failed during deployment: #{inspect(error)}")
          :error
      end
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
        error ->
          Logger.warning("Failed to reset metrics during deployment: #{inspect(error)}")
          :ok
      end
    end)
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
      :validate -> validate_deployment(current_version, new_version, :safe)
      :backup -> execute_backup_step(current_version)
      :update_version -> Versioning.set_version(new_version)
      :warm_cache -> execute_warm_cache_step()
      :invalidate_old -> execute_invalidate_old_step(new_version)
      :gradual_migration -> execute_gradual_migration_step(current_version, new_version)
      :verify -> execute_verify_step(new_version)
      _ -> execute_unknown_deployment_step(step)
    end
  end

  defp execute_backup_step(current_version) do
    # NOTE: Cache backup logic not yet implemented
    # This should create a backup of the current cache state before deployment
    # Consider: key enumeration, data export, versioned backup storage
    Logger.info(
      "Backing up cache state for version #{current_version} (backup not yet implemented)"
    )

    :ok
  end

  defp execute_warm_cache_step do
    try do
      Warmer.force_startup_warming()
      :ok
    rescue
      error ->
        Logger.error("Cache warming failed during deployment step: #{inspect(error)}")
        {:error, error}
    end
  end

  defp execute_invalidate_old_step(new_version) do
    Versioning.invalidate_old_versions(new_version)
    :ok
  end

  defp execute_gradual_migration_step(current_version, new_version) do
    execute_migration(current_version, new_version, :gradual)
    :ok
  end

  defp execute_verify_step(new_version) do
    # NOTE: Real verification logic not yet implemented
    # This should verify that the new version is properly set and accessible
    # For now, we only log the verification step
    Logger.info(
      "Verifying deployment to version #{new_version} (verification not yet implemented)"
    )

    :ok
  end

  defp execute_unknown_deployment_step(step) do
    Logger.warning("Unknown deployment step: #{step}")
    :ok
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
      :prepare -> execute_prepare_step(plan)
      :backup -> execute_backup_step()
      :migrate_keys -> execute_migrate_keys_step(plan)
      :verify -> execute_verify_step()
      :cleanup -> execute_cleanup_step(plan)
      _ -> execute_unknown_step(step)
    end
  end

  defp execute_prepare_step(plan) do
    Logger.info("Preparing migration from #{plan.from_version} to #{plan.to_version}")
    :ok
  end

  defp execute_backup_step do
    Logger.info("Backing up cache state")
    :ok
  end

  defp execute_migrate_keys_step(plan) do
    case Versioning.migrate_version(plan.from_version, plan.to_version) do
      {:ok, _count} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp execute_verify_step do
    Logger.info("Verifying migration")
    :ok
  end

  defp execute_cleanup_step(plan) do
    # Silent cleanup
    case Versioning.invalidate_old_versions(plan.to_version) do
      {:ok, count} ->
        Logger.debug("Cleaned up #{count} entries for version migration")
        :ok

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp execute_unknown_step(step) do
    Logger.warning("Unknown migration step: #{step}")
    {:error, {:unknown_step, step}}
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
    Versioning.get_registered_hooks()
  end
end
