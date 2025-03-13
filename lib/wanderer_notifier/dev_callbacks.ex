defmodule WandererNotifier.DevCallbacks do
  @moduledoc """
  Development callbacks for hot code reloading.
  """
  require Logger

  @doc """
  Called when a file is changed and code is reloaded.
  """
  def reload(modules) do
    Logger.info("Reloaded modules: #{inspect(modules)}")
    :ok
  end
end
