defmodule WandererNotifier.Application.Testing.ServiceValidator do
  @moduledoc """
  Service validation and testing utilities for the refactored architecture.

  This module provides comprehensive validation of the new service architecture,
  ensuring all components work together correctly and follow the established patterns.

  ## Validation Areas

  - Service initialization order and dependencies
  - Configuration management and loading
  - Health check functionality across all services
  - Dependency injection resolution
  - Context layer integration
  - Error handling and recovery
  """

  require Logger

  @type validation_result :: {:ok, String.t()} | {:error, String.t(), term()}
  @type validation_report :: %{
          total_checks: non_neg_integer(),
          passed: non_neg_integer(),
          failed: non_neg_integer(),
          results: [validation_result()],
          summary: String.t()
        }

  # ──────────────────────────────────────────────────────────────────────────────
  # Public API
  # ──────────────────────────────────────────────────────────────────────────────

  @doc """
  Runs a comprehensive validation of the entire service architecture.
  """
  @spec validate_architecture() :: validation_report()
  def validate_architecture do
    Logger.info("Starting architecture validation", category: :validation)

    checks = get_validation_checks()
    results = execute_validation_checks(checks)
    generate_validation_report(results)
  end

  @doc """
  Validates that all services implement the required interfaces correctly.
  """
  @spec validate_service_interfaces() :: validation_result()
  def validate_service_interfaces do
    services_to_check = [
      WandererNotifier.Application.Services.ApplicationService
    ]

    case check_service_interfaces(services_to_check) do
      [] ->
        {:ok, "All services implement required interfaces correctly"}

      errors ->
        {:error, "Service interface validation failed", errors}
    end
  end

  @doc """
  Validates the dependency injection system works correctly.
  """
  @spec validate_dependency_registry() :: validation_result()
  def validate_dependency_registry do
    try do
      # Check if registry is running
      case Process.whereis(WandererNotifier.Application.Services.DependencyRegistry) do
        nil ->
          {:error, "Dependency registry not running", :not_started}

        _pid ->
          # Test basic dependency resolution
          cache_impl = WandererNotifier.Application.Services.DependencyRegistry.resolve(:cache)

          if cache_impl do
            deps = WandererNotifier.Application.Services.DependencyRegistry.list_dependencies()
            {:ok, "Dependency registry operational with #{length(deps)} dependencies"}
          else
            {:error, "Dependency resolution failed", :resolution_failed}
          end
      end
    rescue
      error ->
        {:error, "Dependency registry validation failed", error}
    end
  end

  # ──────────────────────────────────────────────────────────────────────────────
  # Validation Check Management
  # ──────────────────────────────────────────────────────────────────────────────

  defp get_validation_checks do
    [
      # Core Infrastructure
      {"Service Initialization", &validate_service_initialization/0},
      {"Dependency Registry", &validate_dependency_registry/0},
      {"Configuration Management", &validate_configuration_management/0},

      # Context Layers
      {"API Context Integration", &validate_api_context/0},
      {"Notification Context Integration", &validate_notification_context/0},
      {"Processing Context Integration", &validate_processing_context/0},

      # Service Architecture
      {"Application Service Health", &validate_application_service/0},
      {"Service Interface Compliance", &validate_service_interfaces/0},

      # Integration Testing
      {"End-to-End Workflow", &validate_end_to_end_workflow/0}
    ]
  end

  defp execute_validation_checks(checks) do
    Enum.map(checks, fn {name, check_fn} ->
      case run_validation_check(name, check_fn) do
        {:ok, _} = success -> success
        {:error, reason} -> {:error, name, reason}
      end
    end)
  end

  # ──────────────────────────────────────────────────────────────────────────────
  # Individual Validation Functions
  # ──────────────────────────────────────────────────────────────────────────────

  defp validate_service_initialization do
    # Check that key services are running
    critical_services = [
      WandererNotifier.Application.Services.ApplicationService,
      WandererNotifier.Application.Services.DependencyRegistry,
      WandererNotifier.Infrastructure.Cache
    ]

    case check_services_running(critical_services) do
      [] ->
        {:ok, "All critical services initialized successfully"}

      failed_services ->
        {:error, "Service initialization incomplete", failed_services}
    end
  end

  defp validate_configuration_management do
    try do
      # Test configuration loading for a service
      case WandererNotifier.Shared.Config.ConfigurationManager.get_service_config(:notifications) do
        {:ok, config} when is_map(config) ->
          {:ok, "Configuration management operational"}

        {:error, reason} ->
          {:error, "Configuration loading failed", reason}
      end
    rescue
      error ->
        {:error, "Configuration management validation failed", error}
    end
  end

  defp validate_api_context do
    try do
      # Test that ApiContext module exists and has expected functions
      functions = WandererNotifier.Contexts.ApiContext.__info__(:functions)
      required_functions = [:get_tracked_systems, :get_tracked_characters]

      missing = required_functions -- Keyword.keys(functions)

      case missing do
        [] ->
          {:ok, "API Context integration complete"}

        missing_functions ->
          {:error, "API Context missing functions", missing_functions}
      end
    rescue
      error ->
        {:error, "API Context validation failed", error}
    end
  end

  defp validate_notification_context do
    try do
      # Test that DiscordNotifier has required notification functions
      functions = WandererNotifier.DiscordNotifier.__info__(:functions)

      required_functions = [
        :send_kill_async,
        :send_system_async,
        :send_character_async,
        :send_rally_point_async
      ]

      missing = required_functions -- Keyword.keys(functions)

      case missing do
        [] ->
          {:ok, "Discord Notifier integration complete"}

        missing_functions ->
          {:error, "Discord Notifier missing functions", missing_functions}
      end
    rescue
      error ->
        {:error, "Discord Notifier validation failed", error}
    end
  end

  defp validate_processing_context do
    try do
      # Test that ProcessingContext exists and has required functions
      functions = WandererNotifier.Contexts.ProcessingContext.__info__(:functions)
      required_functions = [:process_killmail]

      missing = required_functions -- Keyword.keys(functions)

      case missing do
        [] ->
          {:ok, "Processing Context integration complete"}

        missing_functions ->
          {:error, "Processing Context missing functions", missing_functions}
      end
    rescue
      error ->
        {:error, "Processing Context validation failed", error}
    end
  end

  defp validate_application_service do
    try do
      case Process.whereis(WandererNotifier.Application.Services.ApplicationService) do
        nil ->
          {:error, "Application Service not running", :not_started}

        _pid ->
          # Test basic functionality - verify the service responds with proper structure
          stats = WandererNotifier.Application.Services.ApplicationService.get_stats()

          # Validate stats structure
          if validate_stats_structure(stats) do
            {:ok, "Application Service operational"}
          else
            {:error, "Application Service stats structure invalid", stats}
          end
      end
    rescue
      error ->
        {:error, "Application Service validation failed", error}
    end
  end

  defp validate_end_to_end_workflow do
    try do
      # Test a simple end-to-end workflow using the new architecture
      # This simulates the flow: Configuration -> Dependency -> Context -> Service

      # 1. Configuration loading
      {:ok, _config} =
        WandererNotifier.Shared.Config.ConfigurationManager.get_service_config(:notifications)

      # 2. Dependency resolution
      notification_impl =
        WandererNotifier.Application.Services.DependencyRegistry.resolve(:notification_context)

      if notification_impl do
        {:ok, "End-to-end workflow validation passed"}
      else
        {:error, "End-to-end workflow failed", :dependency_resolution}
      end
    rescue
      error ->
        {:error, "End-to-end workflow validation failed", error}
    end
  end

  # ──────────────────────────────────────────────────────────────────────────────
  # Helper Functions
  # ──────────────────────────────────────────────────────────────────────────────

  defp run_validation_check(name, check_fn) do
    Logger.debug("Running validation check: #{name}", category: :validation)

    start_time = System.monotonic_time(:millisecond)

    result =
      try do
        check_fn.()
      rescue
        error ->
          {:error, "Validation check crashed: #{Exception.message(error)}"}
      end

    duration_ms = System.monotonic_time(:millisecond) - start_time

    case result do
      {:ok, message} ->
        Logger.debug("✅ #{name}: #{message} (#{duration_ms}ms)", category: :validation)
        {:ok, "#{name}: #{message}"}

      {:error, reason} ->
        Logger.warning("❌ #{name}: #{inspect(reason)} (#{duration_ms}ms)", category: :validation)
        {:error, reason}
    end
  end

  defp check_services_running(services) do
    Enum.filter(services, fn service ->
      case Process.whereis(service) do
        nil -> true
        _pid -> false
      end
    end)
  end

  defp check_service_interfaces(services) do
    Enum.flat_map(services, fn service ->
      case check_single_service_interface(service) do
        :ok -> []
        {:error, reason} -> [{service, reason}]
      end
    end)
  end

  defp check_single_service_interface(service) do
    try do
      # Check if service implements ServiceBehaviour
      behaviours =
        service.__info__(:attributes)
        |> Keyword.get(:behaviour, [])

      if WandererNotifier.Application.Services.ServiceBehaviour in behaviours do
        # Check required functions exist
        functions = service.__info__(:functions)
        required = [:service_info, :health_check, :configure]

        missing = required -- Keyword.keys(functions)

        if missing == [] do
          :ok
        else
          {:error, {:missing_functions, missing}}
        end
      else
        {:error, :missing_behaviour}
      end
    rescue
      error ->
        {:error, {:interface_check_failed, error}}
    end
  end

  defp validate_stats_structure(stats) do
    required_keys = [:uptime, :metrics, :dependencies]

    # Check if all required keys are present
    has_required_keys = Enum.all?(required_keys, &Map.has_key?(stats, &1))

    # Check if metrics has expected structure
    has_valid_metrics =
      is_map(stats[:metrics]) and
        Map.has_key?(stats[:metrics], :killmails) and
        Map.has_key?(stats[:metrics], :notifications)

    # Check if dependencies is a list
    has_valid_dependencies = is_list(stats[:dependencies])

    has_required_keys and has_valid_metrics and has_valid_dependencies
  end

  defp generate_validation_report(results) do
    total = length(results)
    passed = Enum.count(results, &match?({:ok, _}, &1))
    failed = total - passed

    summary =
      if failed == 0 do
        "🎉 All validation checks passed! Architecture is healthy."
      else
        "⚠️  #{failed} validation check(s) failed. Review and address issues."
      end

    report = %{
      total_checks: total,
      passed: passed,
      failed: failed,
      results: results,
      summary: summary
    }

    Logger.info("Architecture validation completed",
      total: total,
      passed: passed,
      failed: failed,
      category: :validation
    )

    report
  end
end
