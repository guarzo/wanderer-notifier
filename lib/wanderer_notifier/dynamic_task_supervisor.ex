defmodule WandererNotifier.DynamicTaskSupervisor do
  @moduledoc """
  A DynamicSupervisor to manage transient tasks.
  """
  use DynamicSupervisor

  @doc """
  Starts the DynamicTaskSupervisor.
  """
  def start_link(init_arg \\ []) do
    DynamicSupervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  @impl true
  def init(_init_arg) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end

  @doc """
  Starts a new task as a child process.
  """
  @spec start_task((() -> any())) :: DynamicSupervisor.on_start_child()
  def start_task(fun) when is_function(fun, 0) do
    spec = %{
      id: make_ref(),
      start: {Task, :start_link, [fun]},
      restart: :temporary
    }

    DynamicSupervisor.start_child(__MODULE__, spec)
  end
end 