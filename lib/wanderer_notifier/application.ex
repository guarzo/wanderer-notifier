defmodule WandererNotifier.NoopConsumer do
  @moduledoc """
  A minimal Discord consumer that ignores all events.
  Used during application startup and testing to satisfy Nostrum requirements.
  """
  use Nostrum.Consumer

  @impl true
  def handle_event(_event), do: :ok
end

defmodule WandererNotifier.Application do
  @moduledoc """
  Application module for WandererNotifier.
  Handles application startup and environment configuration.
  """

  use Application

  alias WandererNotifier.Logger.Logger, as: AppLogger
  alias WandererNotifier.Killmail.Metrics

  @doc """
  Starts the WandererNotifier application.
  """
  def start(_type, _args) do
    AppLogger.startup_info("Starting WandererNotifier")

    # Initialize metric registry (not as a supervised child)
    initialize_metric_registry()

    children = [
      {WandererNotifier.NoopConsumer, []},
      {Cachex, name: :wanderer_cache},
      {Metrics, []},
      {WandererNotifier.Core.Stats, []},
      {WandererNotifier.License.Service, []},
      {WandererNotifier.Core.Application.Service, []}
    ]

    # Only add scheduler supervisor if enabled
    children =
      if Application.get_env(:wanderer_notifier, :scheduler_supervisor_enabled, false) do
        children ++ [WandererNotifier.Schedulers.Supervisor]
      else
        children
      end

    opts = [strategy: :one_for_one, name: WandererNotifier.Supervisor]
    Supervisor.start_link(children, opts)
  end

  defp initialize_metric_registry do
    case WandererNotifier.Killmail.MetricRegistry.initialize() do
      {:ok, atoms} ->
        AppLogger.log_startup_state_change(
          :metric_registry,
          "Metric registry initialized successfully",
          %{metric_count: length(atoms)}
        )

        :ok

      error ->
        AppLogger.startup_error("Failed to initialize metric registry", error: inspect(error))
        error
    end
  end

  @doc """
  Gets the current environment.
  """
  def get_env do
    Application.get_env(:wanderer_notifier, :environment, :dev)
  end

  @doc """
  Gets a configuration value for the given key.
  """
  def get_config(key, default \\ nil) do
    Application.get_env(:wanderer_notifier, key, default)
  end

  @doc """
  Reloads modules.
  """
  def reload(modules) do
    AppLogger.config_info("Reloading modules", modules: inspect(modules))
    Code.compiler_options(ignore_module_conflict: true)

    Enum.each(modules, fn module ->
      :code.purge(module)
      :code.delete(module)
      :code.load_file(module)
    end)

    AppLogger.config_info("Module reload complete")
    {:ok, modules}
  rescue
    error ->
      AppLogger.config_error("Error reloading modules", error: inspect(error))
      {:error, error}
  end
end
