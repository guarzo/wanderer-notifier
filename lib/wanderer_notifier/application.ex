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
  """

  use Application
  require Logger
  alias WandererNotifier.Logger, as: AppLogger

  @doc """
  Starts the application.
  """
  def start(_type, _args) do
    minimal_test = Application.get_env(:wanderer_notifier, :minimal_test, false)

    if minimal_test do
      start_minimal_application()
    else
      start_main_application()
    end
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

  # Private functions

  defp start_minimal_application do
    children = [
      {WandererNotifier.NoopConsumer, []}
    ]

    opts = [strategy: :one_for_one, name: WandererNotifier.Supervisor]
    Supervisor.start_link(children, opts)
  end

  defp start_main_application do
    children = get_children()
    opts = [strategy: :one_for_one, name: WandererNotifier.Supervisor]

    AppLogger.startup_info("Starting supervisor", child_count: length(children))

    case Supervisor.start_link(children, opts) do
      {:ok, pid} ->
        AppLogger.startup_info("Application started successfully")
        {:ok, pid}

      {:error, {:already_started, pid}} ->
        AppLogger.startup_warn("Supervisor already started", pid: inspect(pid))
        {:ok, pid}

      {:error, reason} = error ->
        AppLogger.startup_error("Failed to start application", error: inspect(reason))
        error
    end
  end

  defp get_children do
    [
      # Core services
      {WandererNotifier.NoopConsumer, []},
      {WandererNotifier.Core.License, []},
      {WandererNotifier.Core.Stats, []},
      {WandererNotifier.Helpers.DeduplicationHelper, []},
      {WandererNotifier.Services.Service, []},
      {WandererNotifier.Data.Cache.Repository, []},
      {WandererNotifier.Repo, []},
      {WandererNotifier.Web.Server, []},
      {WandererNotifier.Schedulers.ActivityChartScheduler, []},
      {WandererNotifier.Services.Maintenance, []}
    ]
  end
end
