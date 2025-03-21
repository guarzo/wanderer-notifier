defmodule WandererNotifier.Notifiers.Factory do
  @moduledoc """
  Factory module for creating notifier instances.
  Provides a unified way to get the appropriate notifier based on configuration.
  """
  require Logger

  @doc """
  Returns the appropriate notifier module based on the current environment and configuration.
  """
  @spec get_notifier() :: module()
  def get_notifier do
    env = Application.get_env(:wanderer_notifier, :env, :prod)

    cond do
      # If a specific notifier is configured, use it (useful for testing)
      Application.get_env(:wanderer_notifier, :notifier) != nil ->
        Application.get_env(:wanderer_notifier, :notifier)

      # In test environment, use the test notifier
      env == :test ->
        WandererNotifier.Notifiers.Discord.Test

      # Discord is the default and only supported notifier
      true ->
        WandererNotifier.Notifiers.Discord
    end
  end

  @doc """
  Sends a notification using the configured notifier.
  """
  @spec notify(atom(), list()) :: :ok | {:error, any()}
  def notify(function, args) do
    notifier = get_notifier()

    # Add debug logging for character notifications
    if function == :send_new_tracked_character_notification do
      Logger.debug("Sending character notification with: #{inspect(args)}")
    end

    apply(notifier, function, args)
  end
end
