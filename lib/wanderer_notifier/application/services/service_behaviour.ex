defmodule WandererNotifier.Application.Services.ServiceBehaviour do
  @moduledoc """
  Standardized behavior for all application services.

  This behaviour defines a consistent interface that all services should implement,
  ensuring uniform service lifecycle management, health monitoring, and configuration.

  ## Service Lifecycle

  1. **Initialization**: `init/1` - Set up service state and dependencies
  2. **Configuration**: `configure/1` - Apply configuration updates
  3. **Health Checks**: `health_check/0` - Report service health status
  4. **Graceful Shutdown**: `terminate/2` - Clean up resources

  ## Service Information

  Services should provide metadata about their purpose, dependencies,
  and operational characteristics for monitoring and debugging.
  """

  @type service_config :: map()
  @type health_status :: :healthy | :degraded | :unhealthy
  @type service_info :: %{
          name: atom(),
          description: String.t(),
          version: String.t(),
          dependencies: [atom()],
          optional_dependencies: [atom()],
          startup_timeout: pos_integer(),
          shutdown_timeout: pos_integer()
        }
  @type health_report :: %{
          status: health_status(),
          details: map(),
          last_check: DateTime.t(),
          uptime_seconds: non_neg_integer()
        }

  # ──────────────────────────────────────────────────────────────────────────────
  # Required Callbacks
  # ──────────────────────────────────────────────────────────────────────────────

  @doc """
  Returns service information and metadata.
  """
  @callback service_info() :: service_info()

  @doc """
  Performs a health check and returns current status.

  Health checks should be fast (< 1 second) and non-intrusive.
  They should check critical functionality without impacting normal operations.
  """
  @callback health_check() :: health_report()

  @doc """
  Applies configuration updates to the running service.

  This allows for runtime configuration changes without service restart.
  Services should validate the configuration and return an error if invalid.
  """
  @callback configure(service_config()) :: :ok | {:error, term()}

  # ──────────────────────────────────────────────────────────────────────────────
  # Optional Callbacks
  # ──────────────────────────────────────────────────────────────────────────────

  @doc """
  Validates service configuration before applying it.

  This is called before `configure/1` to ensure configuration is valid.
  """
  @callback validate_config(service_config()) :: :ok | {:error, term()}

  @doc """
  Returns service metrics for monitoring and observability.
  """
  @callback get_metrics() :: map()

  @doc """
  Performs service-specific diagnostics for troubleshooting.
  """
  @callback diagnostics() :: map()

  @doc """
  Returns the current service configuration.
  """
  @callback get_config() :: service_config()

  # ──────────────────────────────────────────────────────────────────────────────
  # Default Implementations
  # ──────────────────────────────────────────────────────────────────────────────

  @optional_callbacks [
    validate_config: 1,
    get_metrics: 0,
    diagnostics: 0,
    get_config: 0
  ]

  # ──────────────────────────────────────────────────────────────────────────────
  # Helper Macros
  # ──────────────────────────────────────────────────────────────────────────────

  @doc """
  Provides default implementations for common service patterns.
  """
  defmacro __using__(opts) do
    service_name = Keyword.get(opts, :name, __CALLER__.module)
    description = Keyword.get(opts, :description, "Application service")
    version = Keyword.get(opts, :version, "1.0.0")

    quote do
      @behaviour WandererNotifier.Application.Services.ServiceBehaviour

      require Logger

      @service_name unquote(service_name)
      @service_description unquote(description)
      @service_version unquote(version)

      # Default service info implementation
      @impl true
      def service_info do
        %{
          name: @service_name,
          description: @service_description,
          version: @service_version,
          dependencies: service_dependencies(),
          optional_dependencies: optional_service_dependencies(),
          startup_timeout: startup_timeout(),
          shutdown_timeout: shutdown_timeout()
        }
      end

      # Default health check implementation
      @impl true
      def health_check do
        %{
          status: check_health_status(),
          details: health_check_details(),
          last_check: DateTime.utc_now(),
          uptime_seconds: calculate_uptime()
        }
      end

      # Default configuration implementation
      @impl true
      def configure(config) do
        case validate_config(config) do
          :ok ->
            apply_configuration(config)

          {:error, reason} = error ->
            Logger.error("Configuration validation failed for #{@service_name}",
              reason: inspect(reason),
              service: @service_name
            )

            error
        end
      end

      # Default configuration validation
      def validate_config(_config), do: :ok

      # Default metrics implementation
      def get_metrics, do: %{}

      # Default diagnostics implementation
      def diagnostics do
        %{
          service_info: service_info(),
          health: health_check(),
          config: get_config_safe(),
          metrics: get_metrics()
        }
      end

      # Default configuration getter
      def get_config do
        WandererNotifier.Shared.Config.ConfigurationManager.get_service_config(@service_name)
        |> case do
          {:ok, config} -> config
          {:error, _} -> %{}
        end
      end

      # ────────────────────────────────────────────────────────────────────────
      # Overridable Helper Functions
      # ────────────────────────────────────────────────────────────────────────

      defp service_dependencies, do: []
      defp optional_service_dependencies, do: []
      defp startup_timeout, do: 30_000
      defp shutdown_timeout, do: 5_000

      defp check_health_status do
        case Process.whereis(__MODULE__) do
          nil -> :unhealthy
          _pid -> :healthy
        end
      end

      defp health_check_details, do: %{}

      defp calculate_uptime do
        case Application.get_env(:wanderer_notifier, :start_time) do
          nil -> 0
          start_time -> System.monotonic_time(:second) - start_time
        end
      end

      defp apply_configuration(_config), do: :ok

      defp get_config_safe do
        try do
          get_config()
        rescue
          _ -> %{error: "Failed to retrieve configuration"}
        end
      end

      # Allow overriding of helper functions
      defoverridable service_dependencies: 0,
                     optional_service_dependencies: 0,
                     startup_timeout: 0,
                     shutdown_timeout: 0,
                     check_health_status: 0,
                     health_check_details: 0,
                     calculate_uptime: 0,
                     apply_configuration: 1,
                     validate_config: 1,
                     configure: 1,
                     get_metrics: 0,
                     diagnostics: 0,
                     get_config: 0
    end
  end
end
