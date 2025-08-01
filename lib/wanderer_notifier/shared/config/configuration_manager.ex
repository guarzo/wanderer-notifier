defmodule WandererNotifier.Shared.Config.ConfigurationManager do
  @moduledoc """
  Standardized configuration management for all services.

  This module provides a unified interface for service configuration,
  replacing scattered configuration approaches with a single,
  consistent pattern across all services.

  ## Features

  - Environment-aware configuration loading
  - Configuration validation with meaningful error messages
  - Type-safe configuration access with defaults
  - Runtime configuration updates
  - Configuration change notifications
  """

  require Logger

  @type config_key :: atom() | String.t()
  @type config_value :: term()
  @type config_path :: [config_key()]
  @type validation_rule :: {:required} | {:type, atom()} | {:range, Range.t()} | {:enum, [term()]}

  # ──────────────────────────────────────────────────────────────────────────────
  # Service Configuration Schema
  # ──────────────────────────────────────────────────────────────────────────────

  @service_configs %{
    # Core Services
    application_service: %{
      startup_timeout: {:integer, 30_000},
      health_check_interval: {:integer, 60_000},
      metrics_retention: {:integer, 86_400}
    },

    # Discord Integration
    discord: %{
      bot_token: {:string, :required},
      application_id: {:string, :optional},
      channel_id: {:string, :required},
      guild_id: {:string, :optional},
      timeout: {:integer, 5_000},
      retry_count: {:integer, 3}
    },

    # Cache Configuration
    cache: %{
      default_ttl: {:integer, 3_600},
      max_size: {:integer, 100_000},
      stats_enabled: {:boolean, true},
      cleanup_interval: {:integer, 300}
    },

    # HTTP Client Configuration
    http: %{
      timeout: {:integer, 30_000},
      retry_count: {:integer, 3},
      retry_delay: {:integer, 1_000},
      pool_size: {:integer, 10},
      max_connections: {:integer, 50}
    },

    # Killmail Processing
    killmail: %{
      websocket_url: {:string, "ws://host.docker.internal:4004"},
      wanderer_kills_url: {:string, "http://host.docker.internal:4004"},
      processing_timeout: {:integer, 30_000},
      batch_size: {:integer, 50}
    },

    # Map Integration
    map: %{
      url: {:string, :required},
      api_key: {:string, :required},
      name: {:string, :required},
      sse_timeout: {:integer, 45_000},
      sync_interval: {:integer, 300_000}
    },

    # License Management
    license: %{
      validation_url: {:string, "https://lm.wanderer.ltd/validate_bot"},
      api_token: {:string, :required},
      license_key: {:string, :required},
      validation_interval: {:integer, 86_400}
    },

    # Notification Configuration
    notifications: %{
      enabled: {:boolean, true},
      kill_enabled: {:boolean, true},
      system_enabled: {:boolean, true},
      character_enabled: {:boolean, true},
      priority_systems_only: {:boolean, false},
      rate_limit: {:integer, 10}
    },

    # Scheduler Configuration
    schedulers: %{
      enabled: {:boolean, true},
      service_status_interval: {:integer, 300_000}
    }
  }

  # ──────────────────────────────────────────────────────────────────────────────
  # Public API
  # ──────────────────────────────────────────────────────────────────────────────

  @doc """
  Gets configuration for a specific service with validation.
  """
  @spec get_service_config(atom()) :: {:ok, map()} | {:error, term()}
  def get_service_config(service_name) when is_atom(service_name) do
    case Map.get(@service_configs, service_name) do
      nil ->
        {:error, {:unknown_service, service_name}}

      config_schema ->
        case build_service_config(service_name, config_schema) do
          {:ok, config} ->
            Logger.debug("Service configuration loaded",
              service: service_name,
              config_keys: Map.keys(config),
              category: :config
            )

            {:ok, config}

          {:error, reason} = error ->
            Logger.error("Failed to load service configuration",
              service: service_name,
              error: inspect(reason),
              category: :config
            )

            error
        end
    end
  end

  @doc """
  Gets a specific configuration value with type validation.
  """
  @spec get_config(atom(), config_key(), config_value()) :: config_value()
  def get_config(service, key, default \\ nil) do
    case get_service_config(service) do
      {:ok, config} ->
        Map.get(config, key, default)

      {:error, _reason} ->
        Logger.warning("Using default config due to service config error",
          service: service,
          key: key,
          default: default,
          category: :config
        )

        default
    end
  end

  @doc """
  Validates configuration for all services.
  """
  @spec validate_all_configurations() :: {:ok, map()} | {:error, term()}
  def validate_all_configurations do
    Logger.info("Starting configuration validation for all services", category: :config)

    results = validate_all_service_configs()
    process_validation_results(results)
  end

  @doc """
  Updates runtime configuration for a service.
  """
  @spec update_service_config(atom(), map()) :: :ok | {:error, term()}
  def update_service_config(service, updates) when is_atom(service) and is_map(updates) do
    case get_service_config(service) do
      {:ok, current_config} ->
        new_config = Map.merge(current_config, updates)

        # Validate the updated configuration
        case validate_config_values(service, new_config) do
          :ok ->
            # Store the updated configuration
            cache_key = service_config_cache_key(service)
            WandererNotifier.Infrastructure.Cache.put(cache_key, new_config, :timer.hours(1))

            Logger.info("Service configuration updated",
              service: service,
              updated_keys: Map.keys(updates),
              category: :config
            )

            :ok
        end

      error ->
        error
    end
  end

  # ──────────────────────────────────────────────────────────────────────────────
  # Configuration Building
  # ──────────────────────────────────────────────────────────────────────────────

  defp validate_all_service_configs do
    @service_configs
    |> Map.keys()
    |> Enum.map(&validate_service_config/1)
    |> Enum.group_by(&elem(&1, 0))
  end

  defp process_validation_results(results) do
    case Map.get(results, :error, []) do
      [] ->
        handle_validation_success(results)

      errors ->
        handle_validation_errors(errors)
    end
  end

  defp handle_validation_success(results) do
    success_count = length(Map.get(results, :ok, []))

    Logger.info("Configuration validation completed successfully",
      services_validated: success_count,
      category: :config
    )

    success_results = Map.get(results, :ok, [])
    config_map = build_config_map(success_results)

    {:ok, config_map}
  end

  defp handle_validation_errors(errors) do
    error_services = Enum.map(errors, fn {:error, {service, _reason}} -> service end)

    Logger.error("Configuration validation failed",
      failed_services: error_services,
      category: :config
    )

    {:error, {:validation_failed, errors}}
  end

  defp build_config_map(success_results) do
    Map.new(success_results, fn {:ok, {service, config}} -> {service, config} end)
  end

  defp validate_service_config(service) do
    case get_service_config(service) do
      {:ok, config} -> {:ok, {service, config}}
      {:error, reason} -> {:error, {service, reason}}
    end
  end

  defp build_service_config(service_name, config_schema) do
    # Check cache first
    cache_key = service_config_cache_key(service_name)

    case WandererNotifier.Infrastructure.Cache.get(cache_key) do
      {:ok, cached_config} ->
        {:ok, cached_config}

      {:error, :not_found} ->
        case build_config_from_schema(service_name, config_schema) do
          {:ok, config} ->
            # Cache the built configuration
            WandererNotifier.Infrastructure.Cache.put(cache_key, config, :timer.hours(1))
            {:ok, config}

          error ->
            error
        end
    end
  end

  defp build_config_from_schema(service_name, config_schema) do
    try do
      config =
        config_schema
        |> Enum.map(fn {key, {type, default_or_required}} ->
          value = resolve_config_value(service_name, key, type, default_or_required)
          {key, value}
        end)
        |> Map.new()

      case validate_config_values(service_name, config) do
        :ok -> {:ok, config}
      end
    rescue
      error ->
        {:error, {:config_build_failed, error}}
    end
  end

  defp resolve_config_value(service_name, key, type, default_or_required) do
    # Try multiple sources in order of priority
    env_key = build_env_key(service_name, key)

    case System.get_env(env_key) do
      nil ->
        case default_or_required do
          :required ->
            raise "Required configuration #{env_key} not found"

          :optional ->
            nil

          default_value ->
            default_value
        end

      string_value ->
        convert_string_to_type(string_value, type)
    end
  end

  # Service-specific environment key mappings
  @service_env_mappings %{
    discord: "DISCORD",
    map: "MAP",
    license: %{
      default: "LICENSE",
      api_token: "NOTIFIER_API_TOKEN"
    },
    killmail: "WANDERER_KILLS"
  }

  defp build_env_key(service_name, config_key) do
    key_suffix =
      config_key
      |> Atom.to_string()
      |> String.upcase()

    case Map.get(@service_env_mappings, service_name) do
      nil ->
        # Default pattern for unmapped services
        service_prefix =
          service_name
          |> Atom.to_string()
          |> String.upcase()

        "#{service_prefix}_#{key_suffix}"

      %{} = mapping ->
        # Handle services with specific key mappings
        case Map.get(mapping, config_key, Map.get(mapping, :default)) do
          nil -> "#{Atom.to_string(service_name) |> String.upcase()}_#{key_suffix}"
          special_key when is_binary(special_key) -> special_key
          prefix -> "#{prefix}_#{key_suffix}"
        end

      prefix when is_binary(prefix) ->
        # Simple prefix mapping
        "#{prefix}_#{key_suffix}"
    end
  end

  defp convert_string_to_type(value, :string), do: value
  defp convert_string_to_type(value, :integer), do: String.to_integer(value)
  defp convert_string_to_type("true", :boolean), do: true
  defp convert_string_to_type("false", :boolean), do: false
  defp convert_string_to_type("1", :boolean), do: true
  defp convert_string_to_type("0", :boolean), do: false
  defp convert_string_to_type("yes", :boolean), do: true
  defp convert_string_to_type("no", :boolean), do: false

  defp convert_string_to_type(value, :boolean) when is_binary(value) do
    boolean_map = %{
      "true" => true,
      "false" => false,
      "1" => true,
      "0" => false,
      "yes" => true,
      "no" => false,
      "on" => true,
      "off" => false,
      "" => false
    }

    Map.get(boolean_map, String.downcase(value), false)
  end

  defp validate_config_values(service_name, config) do
    case service_name do
      :discord ->
        validate_discord_config(config)

      :esi ->
        validate_esi_config(config)

      :wanderer_kills ->
        validate_wanderer_kills_config(config)

      :license ->
        validate_license_config(config)

      :map ->
        validate_map_config(config)

      _ ->
        :ok
    end
  end

  defp validate_discord_config(config) do
    required_keys = [:bot_token, :application_id, :channel_id]

    case check_required_keys(config, required_keys) do
      :ok -> :ok
      {:error, _} = error -> error
    end
  end

  defp validate_esi_config(_config) do
    # ESI config is mostly optional, validation already ensures it's a map
    :ok
  end

  defp validate_wanderer_kills_config(config) do
    required_keys = [:url]

    case check_required_keys(config, required_keys) do
      :ok -> :ok
      {:error, _} = error -> error
    end
  end

  defp validate_license_config(config) do
    required_keys = [:api_url, :api_token]

    case check_required_keys(config, required_keys) do
      :ok -> :ok
      {:error, _} = error -> error
    end
  end

  defp validate_map_config(config) do
    required_keys = [:url, :name, :api_key]

    case check_required_keys(config, required_keys) do
      :ok -> :ok
      {:error, _} = error -> error
    end
  end

  defp check_required_keys(config, required_keys) do
    missing_keys =
      required_keys
      |> Enum.filter(fn key -> is_nil(Map.get(config, key)) or Map.get(config, key) == "" end)

    case missing_keys do
      [] -> :ok
      keys -> {:error, "Missing required configuration keys: #{inspect(keys)}"}
    end
  end

  defp service_config_cache_key(service_name) do
    "config:service:#{service_name}"
  end
end
