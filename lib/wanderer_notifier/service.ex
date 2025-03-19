defmodule WandererNotifier.Service do
  @moduledoc """
  Proxy module for WandererNotifier.Services.Service.
  Delegates calls to the Services.Service implementation.
  """

  @doc """
  Stops the service by delegating to WandererNotifier.Services.Service.stop/0
  """
  def stop do
    WandererNotifier.Services.Service.stop()
  end

  @doc """
  Marks a kill as processed by delegating to WandererNotifier.Services.Service.mark_as_processed/1
  """
  def mark_as_processed(kill_id) do
    WandererNotifier.Services.Service.mark_as_processed(kill_id)
  end

  @doc """
  Returns the child_spec for this service
  """
  def child_spec(opts) do
    %{
      id: __MODULE__,
      start: {WandererNotifier.Services.Service, :start_link, [opts]},
      type: :worker,
      restart: :permanent,
      shutdown: 500
    }
  end

  # Forward all function calls to the implementation
  defdelegate handle_call(request, from, state), to: WandererNotifier.Services.Service
  defdelegate handle_cast(request, state), to: WandererNotifier.Services.Service
  defdelegate handle_info(info, state), to: WandererNotifier.Services.Service
  defdelegate init(args), to: WandererNotifier.Services.Service
  defdelegate terminate(reason, state), to: WandererNotifier.Services.Service
end
