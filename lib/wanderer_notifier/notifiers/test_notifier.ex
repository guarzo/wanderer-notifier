defmodule WandererNotifier.Notifiers.TestNotifier do
  @moduledoc """
  Test Notifier implementation for WandererNotifier.
  Used for testing notification delivery in development and test environments.
  Implements the Notification behaviour.
  """

  @behaviour WandererNotifier.Notifications.Notification

  @doc """
  Stub implementation for determine/1 for test notifier.
  """
  def determine(_context), do: {:ok, %{test: true}}

  @doc """
  Stub implementation for format/1 for test notifier.
  """
  def format(notification_data), do: {:ok, notification_data}

  @doc """
  Delivers a test notification. This function simulates notification delivery.
  """
  @spec deliver(map()) :: :ok | {:error, term()}
  def deliver(notification) when is_map(notification) do
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
    {:ok, :sent}
  end

  @doc """
  Simulates sending a test character notification.
  """
  @spec send_test_character_notification() :: {:ok, :sent}
  def send_test_character_notification do
    {:ok, :sent}
  end

  @doc """
  Simulates sending a test system notification.
  """
  @spec send_test_system_notification() :: {:ok, :sent}
  def send_test_system_notification do
    {:ok, :sent}
  end
end
