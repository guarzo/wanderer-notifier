defmodule WandererNotifier.ApplicationV2 do
  @moduledoc """
  Reorganized application module with explicit contexts and cleaner supervision tree.
  This demonstrates the new structure - to be merged with the main Application module.
  """

  use Application

  alias WandererNotifier.Logger.Logger, as: AppLogger

  @doc """
  Starts the WandererNotifier application with reorganized supervision tree.
  """
  def start(_type, _args) do
    # Ensure critical configuration exists
    ensure_critical_configuration()

    AppLogger.startup_info("Starting WandererNotifier with reorganized supervision tree")

    # Log environment for debugging
    log_environment_variables()

    # Build supervision tree with explicit contexts
    children = build_supervision_tree()

    AppLogger.startup_info("Starting supervision tree with children: #{inspect(children)}")

    opts = [strategy: :one_for_one, name: WandererNotifier.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Builds the supervision tree with clear separation of concerns
  defp build_supervision_tree do
    [
      # Core Infrastructure - started first
      core_infrastructure(),

      # External Adapters - HTTP clients, Discord, etc.
      external_adapters(),

      # Domain Contexts - Business logic supervisors
      domain_contexts(),

      # Web Interface - API endpoints
      web_interface(),

      # Background Jobs - Schedulers and workers
      background_jobs()
    ]
    |> List.flatten()
    |> Enum.filter(& &1)
  end

  defp core_infrastructure do
    [
      # Cache (Cachex or ETS)
      create_cache_child_spec(),

      # Telemetry and metrics
      {WandererNotifier.Telemetry, []},

      # Core stats tracking
      {WandererNotifier.Core.Stats, []},

      # Main task supervisor for ad-hoc tasks
      {Task.Supervisor, name: WandererNotifier.TaskSupervisor}
    ]
  end

  defp external_adapters do
    [
      {WandererNotifier.Supervisors.ExternalAdaptersSupervisor, []}
    ]
  end

  defp domain_contexts do
    children = [
      # Core application service
      {WandererNotifier.Core.Application.Service, []}
    ]

    # Add killmail processing if enabled
    killmail_children =
      if WandererNotifier.Config.redisq_enabled?() do
        [{WandererNotifier.Supervisors.KillmailSupervisor, []}]
      else
        []
      end

    children ++ killmail_children
  end

  defp web_interface do
    [
      {WandererNotifier.Web.Server, []}
    ]
  end

  defp background_jobs do
    if Application.get_env(:wanderer_notifier, :schedulers_enabled, true) do
      [{WandererNotifier.Schedulers.Supervisor, []}]
    else
      []
    end
  end

  # Creates the appropriate cache child spec based on configuration
  defp create_cache_child_spec do
    cache_name = WandererNotifier.Cache.Config.cache_name()
    cache_adapter = Application.get_env(:wanderer_notifier, :cache_adapter, Cachex)

    case cache_adapter do
      Cachex ->
        {Cachex, name: cache_name}

      WandererNotifier.Cache.ETSCache ->
        {WandererNotifier.Cache.ETSCache, name: cache_name}

      other ->
        raise "Unknown cache adapter: #{inspect(other)}"
    end
  end

  # Ensures critical configuration exists to prevent startup failures
  defp ensure_critical_configuration do
    defaults = [
      config_module: WandererNotifier.Config,
      features: [],
      cache_name: WandererNotifier.Cache.Config.default_cache_name(),
      schedulers_enabled: true
    ]

    for {key, default} <- defaults do
      if Application.get_env(:wanderer_notifier, key) == nil do
        Application.put_env(:wanderer_notifier, key, default)
      end
    end
  end

  defp log_environment_variables do
    AppLogger.startup_info("Environment variables at startup:")

    sensitive_keys = ~w(
      DISCORD_BOT_TOKEN
      MAP_API_KEY
      NOTIFIER_API_TOKEN
      LICENSE_KEY
    )

    for {key, value} <- System.get_env() |> Enum.sort_by(fn {k, _} -> k end) do
      # Redact sensitive values
      safe_value = if key in sensitive_keys, do: "[REDACTED]", else: value
      AppLogger.startup_info("  #{key}: #{safe_value}")
    end
  end
end
