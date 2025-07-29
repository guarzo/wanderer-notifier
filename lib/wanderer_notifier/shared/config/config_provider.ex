defmodule WandererNotifier.Shared.Config.ConfigProvider do
  @moduledoc """
  Config provider for WandererNotifier runtime configuration.

  Implements the standard Elixir Config.Provider behavior for loading
  configuration from environment variables at runtime. This is used
  in production releases to dynamically configure the application.
  """

  @behaviour Config.Provider

  @impl Config.Provider
  def init(config) when is_list(config) do
    config
  end

  @impl Config.Provider
  def load(config, _opts \\ []) when is_list(config) do
    # Load environment-based configuration
    wanderer_config = build_wanderer_config()

    # Merge with existing config
    Config.Reader.merge(config, wanderer_notifier: wanderer_config)
  end

  # Build the configuration from environment variables
  defp build_wanderer_config do
    %{
      port: get_port(),
      features: get_features()
    }
  end

  # Parse PORT environment variable
  defp get_port do
    case System.get_env("PORT") do
      nil ->
        4000

      port_str ->
        case Integer.parse(port_str) do
          {port, ""} when port > 0 -> port
          _ -> 4000
        end
    end
  end

  # Parse feature flags from environment
  defp get_features do
    %{
      notifications_enabled: get_boolean_env("NOTIFICATIONS_ENABLED", true),
      kill_notifications_enabled: get_boolean_env("KILL_NOTIFICATIONS_ENABLED", true),
      system_notifications_enabled: get_boolean_env("SYSTEM_NOTIFICATIONS_ENABLED", true),
      character_notifications_enabled: get_boolean_env("CHARACTER_NOTIFICATIONS_ENABLED", true)
    }
  end

  # Parse boolean environment variables
  defp get_boolean_env(key, default) do
    case System.get_env(key) do
      nil -> default
      value -> parse_boolean(value, default)
    end
  end

  # Parse boolean values from strings
  defp parse_boolean(value, default) when is_binary(value) do
    normalized = value |> String.trim() |> String.downcase()

    case normalized do
      v when v in ["true", "1", "yes", "y", "t", "on"] -> true
      v when v in ["false", "0", "no", "n", "f", "off"] -> false
      # Empty string defaults to true per test expectations
      "" -> default
      # Invalid values default to true per test expectations
      _ -> default
    end
  end

  defp parse_boolean(_, default), do: default
end
