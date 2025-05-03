defmodule WandererNotifier.Notifiers.TestNotifier do
  @moduledoc """
  Test Notifier implementation for WandererNotifier.
  Used for testing notification delivery in development and test environments.
  Implements the Notifier behaviour.
  """

  @behaviour WandererNotifier.Notifiers.Behaviour

  @doc """
  Delivers a test notification. This function simulates notification delivery.
  """
  @spec deliver(map()) :: :ok | {:error, term()}
  def deliver(notification) when is_map(notification) do
    IO.inspect({:test_notification, notification}, label: "[TestNotifier] Delivering notification")
    :ok
  end

  @doc """
  Required by Notifier behaviour. Delegates to deliver/1 for test notifications.
  """
  @spec notify(map()) :: :ok | {:error, term()}
  def notify(notification), do: deliver(notification)

  # Utility: ensure_list/1 (if needed elsewhere, move to a shared helper)
  @doc false
  def ensure_list(nil), do: []
  def ensure_list(list) when is_list(list), do: list
  def ensure_list(item), do: [item]

  @doc """
  Simulates sending a test kill notification.
  """
  @spec send_test_kill_notification() :: {:ok, :sent}
  def send_test_kill_notification do
    IO.puts("[TestNotifier] Sending test kill notification")
    {:ok, :sent}
  end

  @doc """
  Simulates sending a test character notification.
  """
  @spec send_test_character_notification() :: {:ok, :sent}
  def send_test_character_notification do
    IO.puts("[TestNotifier] Sending test character notification")
    {:ok, :sent}
  end

  @doc """
  Simulates sending a test system notification.
  """
  @spec send_test_system_notification() :: {:ok, :sent}
  def send_test_system_notification do
    IO.puts("[TestNotifier] Sending test system notification")
    {:ok, :sent}
  end
end
