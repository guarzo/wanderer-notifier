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

      # If Slack is configured, use the Slack notifier
      slack_configured?() ->
        WandererNotifier.Notifiers.Slack

      # Default to Discord notifier
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
    apply(notifier, function, args)
  end

  # Checks if Slack is configured.
  @spec slack_configured?() :: boolean()
  defp slack_configured? do
    case Application.get_env(:wanderer_notifier, :slack_webhook_url) do
      url when is_binary(url) and url != "" -> true
      _ -> false
    end
  end
end
