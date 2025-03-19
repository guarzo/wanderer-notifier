defmodule WandererNotifier.NotifierFactory do
  @moduledoc """
  Proxy module for WandererNotifier.Notifiers.Factory.
  Delegates calls to the Notifiers.Factory implementation to maintain backward compatibility.
  """
  require Logger

  @doc """
  Returns the appropriate notifier module based on the current environment and configuration.
  Delegates to WandererNotifier.Notifiers.Factory.get_notifier/0
  """
  @spec get_notifier() :: module()
  def get_notifier do
    WandererNotifier.Notifiers.Factory.get_notifier()
  end

  @doc """
  Sends a notification using the configured notifier.
  Delegates to WandererNotifier.Notifiers.Factory.notify/2
  """
  @spec notify(atom(), list()) :: :ok | {:error, any()}
  def notify(function, args) do
    WandererNotifier.Notifiers.Factory.notify(function, args)
  end
end
