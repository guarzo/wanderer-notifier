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
    Logger.info("Reloading modules: #{inspect(modules)}")
    Code.compiler_options(ignore_module_conflict: true)

    try do
      Enum.each(modules, fn module ->
        :code.purge(module)
        :code.delete(module)
        :code.load_file(module)
      end)

      Logger.info("Module reloaded")
      {:ok, modules}
    rescue
      error ->
        Logger.error("Error reloading modules: #{inspect(error)}")
        {:error, error}
    end
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

    case Supervisor.start_link(children, opts) do
      {:ok, pid} ->
        Logger.info("Application started successfully")
        {:ok, pid}

      error ->
        Logger.error("Failed to start application: #{inspect(error)}")
        error
    end
  end

  defp get_children do
    [
      {WandererNotifier.NoopConsumer, []},
      {WandererNotifier.Data.Cache.Repository, []},
      {WandererNotifier.Repo, []},
      {WandererNotifier.Web.Server, []},
      {WandererNotifier.Schedulers.ActivityChartScheduler, []},
      {WandererNotifier.Schedulers.SystemUpdateScheduler, []}
    ]
  end
end
