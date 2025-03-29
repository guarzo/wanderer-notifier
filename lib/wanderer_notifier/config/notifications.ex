defmodule WandererNotifier.Config.Notifications do
  @moduledoc """
  Configuration module for notification-related settings.
  Handles Discord configuration and notification channel settings.
  """

  require Logger
  alias WandererNotifier.Logger, as: AppLogger

  @type discord_config :: %{
          bot_token: String.t() | nil,
          channel_id: String.t() | nil
        }

  # Feature channel mapping
  @features %{
    general: %{
      channel_var: "WANDERER_DISCORD_CHANNEL_ID",
      description: "General notifications"
    },
    kill_notifications: %{
      channel_var: "WANDERER_DISCORD_KILL_CHANNEL_ID",
      description: "Kill notifications"
    },
    system_tracking: %{
      channel_var: "WANDERER_DISCORD_SYSTEM_CHANNEL_ID",
      description: "System tracking notifications"
    },
    character_tracking: %{
      channel_var: "WANDERER_DISCORD_CHARACTER_CHANNEL_ID",
      description: "Character tracking notifications"
    },
    map_charts: %{
      channel_var: "WANDERER_DISCORD_CHARTS_CHANNEL_ID",
      description: "Map-based activity charts"
    },
    kill_charts: %{
      channel_var: "WANDERER_DISCORD_CHARTS_CHANNEL_ID",
      description: "Killmail charts and history"
    }
  }

  @doc """
  Gets the Discord configuration settings.
  """
  @spec get_discord_config() :: discord_config()
  def get_discord_config do
    {:ok,
     %{
       bot_token: get_discord_bot_token(),
       channel_id: get_discord_channel_id_for(:general)
     }}
  end

  @doc """
  Gets the Discord bot token.
  """
  def get_discord_bot_token do
    get_env(:discord_bot_token)
  end

  @doc """
  Gets the Discord channel ID for a specific feature.
  """
  @spec get_discord_channel_id_for(atom()) :: String.t()
  def get_discord_channel_id_for(feature) when is_atom(feature) do
    feature_config = Map.get(@features, feature)

    if feature_config do
      channel_var = feature_config.channel_var
      channel_id = System.get_env(channel_var)

      if is_binary(channel_id) && channel_id != "" do
        channel_id
      else
        # Fall back to the main channel ID
        get_env(:discord_channel_id)
      end
    else
      # Unknown feature, use the main channel
      AppLogger.warn("Unknown feature #{feature} when looking up Discord channel ID")
      get_env(:discord_channel_id)
    end
  end

  @doc """
  Gets the environment setting for notifications.
  Defaults to :prod if not set.
  """
  @spec get_env() :: atom()
  def get_env do
    get_env(:env, :prod)
  end

  @doc """
  Gets the list of tracked characters for notifications.
  """
  @spec get_tracked_characters() :: [String.t()]
  def get_tracked_characters do
    get_env(:tracked_characters, [])
  end

  @doc """
  Checks if system notifications are enabled.
  """
  @spec system_notifications_enabled?() :: boolean()
  def system_notifications_enabled? do
    parse_feature_flag(:feature_system_notifications, "FEATURE_SYSTEM_NOTIFICATIONS", true)
  end

  @doc """
  Checks if character notifications are enabled.
  """
  @spec character_notifications_enabled?() :: boolean()
  def character_notifications_enabled? do
    parse_feature_flag(:feature_character_notifications, "FEATURE_CHARACTER_NOTIFICATIONS", true)
  end

  @doc """
  Checks if kill notifications are enabled.
  """
  @spec kill_notifications_enabled?() :: boolean()
  def kill_notifications_enabled? do
    parse_feature_flag(:feature_kill_notifications, "FEATURE_KILL_NOTIFICATIONS", true)
  end

  @doc """
  Get the notifier type (e.g., :discord, :test).
  """
  def get_notifier_type do
    get_env(:notifier_type, :discord)
  end

  # Private helper to get configuration with optional default
  defp get_env(key, default \\ nil) do
    Application.get_env(:wanderer_notifier, key, default)
  end

  # Private helper to parse feature flags
  defp parse_feature_flag(config_key, env_key, default) do
    # First check application config
    case get_env(config_key) do
      nil ->
        # Then check environment variable
        case System.get_env(env_key) do
          nil -> default
          value -> parse_boolean(value)
        end

      value when is_boolean(value) ->
        value

      value when is_binary(value) ->
        parse_boolean(value)
    end
  end

  defp parse_boolean(value) when is_binary(value) do
    case String.downcase(value) do
      "true" -> true
      "1" -> true
      "yes" -> true
      "y" -> true
      _ -> false
    end
  end
end
