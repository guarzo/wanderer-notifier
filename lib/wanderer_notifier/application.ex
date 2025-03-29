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
    # Log each child to help debug startup issues
    IO.puts(">>> SUPERVISOR CHILDREN:")

    Enum.each(children, fn child ->
      child_id =
        case child do
          {module, _opts} -> module
          %{id: id} -> id
          other -> inspect(other)
        end

      IO.puts(">>>   - #{inspect(child_id)}")
    end)

    opts = [strategy: :one_for_one, name: WandererNotifier.Supervisor]

    Logger.info(
      "About to start WandererNotifier.Supervisor with #{length(children)} top-level children"
    )

    try do
      case Supervisor.start_link(children, opts) do
        {:ok, pid} ->
          Logger.info("Application started successfully")
          IO.puts(">>> SUPERVISOR STARTED with pid #{inspect(pid)}")
          {:ok, pid}

        {:error, {:already_started, pid}} ->
          Logger.warn("Supervisor already started with pid: #{inspect(pid)}")
          {:ok, pid}

        {:error, reason} = error ->
          Logger.error("Failed to start application: #{inspect(reason)}")
          IO.puts(">>> CRITICAL ERROR starting supervisor: #{inspect(reason)}")
          error
      end
    rescue
      e ->
        error_msg = "Exception starting application: #{Exception.message(e)}"
        Logger.error(error_msg)
        Logger.error("#{Exception.format_stacktrace(__STACKTRACE__)}")
        IO.puts(">>> CRITICAL EXCEPTION in supervisor: #{error_msg}")
        {:error, e}
    end
  end

  defp get_children do
    # Define all services as direct children of the main supervisor
    [
      # Core services
      {WandererNotifier.NoopConsumer, []},
      {WandererNotifier.Core.License, []},
      {WandererNotifier.Core.Stats, []},

      # Move Service earlier in the list to diagnose startup order issues
      {WandererNotifier.Services.Service, []},

      # Remaining services
      {WandererNotifier.Data.Cache.Repository, []},
      {WandererNotifier.Repo, []},
      {WandererNotifier.Web.Server, []},
      {WandererNotifier.Schedulers.ActivityChartScheduler, []},
      {WandererNotifier.Schedulers.SystemUpdateScheduler, []},
      {WandererNotifier.Services.Maintenance, []}
    ]
  end
end
