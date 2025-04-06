defmodule WandererNotifier.Config.Notifications do
  @moduledoc """
  Configuration module for notification settings.

  This module centralizes all notification configuration access,
  providing a standardized interface for retrieving notification settings
  and validating configuration values. It handles:

  - Discord notification channels
  - Notification formatting
  - Notification limits and thresholds
  """

  require Logger

  # Add the Features module alias
  alias WandererNotifier.Config.Features

  # Types for notification settings
  @type channel_id :: String.t()
  @type channel_config :: %{
          enabled: boolean(),
          id: channel_id() | nil,
          name: String.t(),
          type: atom()
        }

  @doc """
  Returns the complete notifications configuration map.
  """
  @spec config() :: map()
  def config do
    %{
      channels: %{
        main: get_channel_config(:discord_channel_id, "main", :general),
        system_kill:
          get_channel_config(:discord_system_kill_channel_id, "system_kill", :system_kill),
        character_kill:
          get_channel_config(
            :discord_character_kill_channel_id,
            "character_kill",
            :character_kill
          ),
        system: get_channel_config(:discord_system_channel_id, "system", :system),
        character: get_channel_config(:discord_character_channel_id, "character", :character),
        charts: get_channel_config(:discord_charts_channel_id, "charts", :charts)
      },
      enabled: Features.notifications_enabled?(),
      features: %{
        kill_notifications: Features.kill_notifications_enabled?(),
        system_notifications: Features.system_notifications_enabled?(),
        character_notifications: Features.character_notifications_enabled?(),
        tracked_systems_notifications: Features.tracked_systems_notifications_enabled?(),
        tracked_characters_notifications: Features.tracked_characters_notifications_enabled?()
      },
      formatting: %{
        embed_color: get_env(:notification_embed_color, 0x3498DB),
        use_markdown: get_env(:notification_use_markdown, true),
        max_fields: get_env(:notification_max_fields, 25)
      },
      thresholds: %{
        min_kill_value: get_env(:min_kill_value, 0),
        max_notifications_per_minute: get_env(:max_notifications_per_minute, 10)
      }
    }
  end

  @doc """
  Returns the Discord channel ID for a specific notification type.

  ## Parameters
    - channel_type: The type of channel (:main, :kill, :system, :character, :charts)

  ## Returns
    - The Discord channel ID or nil if not configured
  """
  @spec channel_id(atom()) :: channel_id() | nil
  def channel_id(channel_type) do
    get_channel_id_with_fallback(channel_type)
  end

  # Private helper to get a channel ID with fallback to main channel
  defp get_channel_id_with_fallback(channel_type) do
    primary_channel = get_primary_channel_id(channel_type)
    fallback_channel = get_env(:discord_channel_id)

    primary_channel || fallback_channel
  end

  # Private helper to get the primary channel ID based on channel type
  defp get_primary_channel_id(:main), do: get_env(:discord_channel_id)
  defp get_primary_channel_id(:system_kill), do: get_env(:discord_system_kill_channel_id)
  defp get_primary_channel_id(:character_kill), do: get_env(:discord_character_kill_channel_id)
  defp get_primary_channel_id(:system), do: get_env(:discord_system_channel_id)
  defp get_primary_channel_id(:character), do: get_env(:discord_character_channel_id)
  defp get_primary_channel_id(:charts), do: get_env(:discord_charts_channel_id)
  defp get_primary_channel_id(_), do: nil

  @doc """
  Returns the Discord bot token.
  """
  @spec discord_token() :: String.t() | nil
  def discord_token do
    get_env(:discord_bot_token)
  end

  @doc """
  Returns the minimum ISK value for a kill to be considered for notification.
  """
  @spec min_kill_value() :: number()
  def min_kill_value do
    get_env(:min_kill_value, 0)
  end

  @doc """
  Returns the maximum number of notifications allowed per minute.
  """
  @spec max_notifications_per_minute() :: integer()
  def max_notifications_per_minute do
    get_env(:max_notifications_per_minute, 10)
  end

  @doc """
  Returns the channel configuration for a specific channel type.

  ## Parameters
    - env_key: The environment variable key for this channel ID
    - name: The name of the channel
    - type: The type of the channel

  ## Returns
    - A map containing the channel configuration
  """
  @spec get_channel_config(atom(), String.t(), atom()) :: channel_config()
  def get_channel_config(env_key, name, type) do
    channel_id = get_env(env_key)

    %{
      enabled: not is_nil(channel_id) and channel_id != "",
      id: channel_id,
      name: name,
      type: type
    }
  end

  @doc """
  Validates that all required notification configuration values are valid.

  Returns :ok if the configuration is valid, or a list of errors if not.
  """
  @spec validate() :: :ok | {:error, [String.t()]}
  def validate do
    errors = []

    # Validate Discord token
    token = discord_token()

    errors =
      if is_nil(token) or token == "" do
        ["Discord bot token is not configured or is empty" | errors]
      else
        errors
      end

    # Validate that at least one channel is configured
    all_channels = [
      channel_id(:main),
      channel_id(:system_kill),
      channel_id(:character_kill),
      channel_id(:system),
      channel_id(:character),
      channel_id(:charts)
    ]

    errors =
      if Enum.all?(all_channels, fn id -> is_nil(id) or id == "" end) do
        ["No Discord channels are configured" | errors]
      else
        errors
      end

    # Validate threshold values
    max_per_minute = max_notifications_per_minute()

    errors =
      if is_integer(max_per_minute) and max_per_minute > 0 do
        errors
      else
        ["max_notifications_per_minute must be a positive integer" | errors]
      end

    if Enum.empty?(errors) do
      :ok
    else
      {:error, errors}
    end
  end

  # Private helper to get environment variables
  defp get_env(key, default \\ nil) do
    Application.get_env(:wanderer_notifier, key, default)
  end

  @doc """
  Returns the Discord channel ID for a specific channel key.
  Used by older modules that rely on specific channel key naming.

  ## Parameters
    - channel_key: The key of the channel (:general, :activity_charts, etc.)

  ## Returns
    - The Discord channel ID or nil if not configured
  """
  @spec get_discord_channel_id_for(atom()) :: channel_id() | nil
  def get_discord_channel_id_for(channel_key) do
    case channel_key do
      :general -> channel_id(:main)
      :activity_charts -> channel_id(:charts)
      :kill -> channel_id(:system_kill)
      :system_kill -> channel_id(:system_kill)
      :character_kill -> channel_id(:character_kill)
      :system -> channel_id(:system)
      :character -> channel_id(:character)
      _ -> channel_id(:main)
    end
  end

  @doc """
  Returns the Discord bot token.
  Alias for discord_token/0 for backward compatibility.
  """
  @spec get_discord_bot_token() :: String.t() | nil
  def get_discord_bot_token do
    discord_token()
  end

  @doc """
  Returns the Discord configuration map for backward compatibility.
  """
  @spec get_discord_config() :: map()
  def get_discord_config do
    %{
      token: discord_token(),
      main_channel: channel_id(:main),
      kill_channel: channel_id(:system_kill),
      system_kill_channel: channel_id(:system_kill),
      character_kill_channel: channel_id(:character_kill),
      system_channel: channel_id(:system),
      character_channel: channel_id(:character),
      charts_channel: channel_id(:charts)
    }
  end

  @doc """
  Returns the environment configuration.
  For backward compatibility with older modules.
  """
  @spec get_env() :: map()
  def get_env do
    %{
      discord: get_discord_config(),
      min_kill_value: min_kill_value(),
      max_notifications_per_minute: max_notifications_per_minute()
    }
  end

  @doc """
  Returns whether kill charts are enabled.
  """
  @spec kill_charts_enabled?() :: boolean()
  def kill_charts_enabled? do
    Features.kill_charts_enabled?()
  end

  @doc """
  Returns the Discord channel ID for a specific feature.
  """
  @spec discord_channel_id_for(atom()) :: String.t() | nil
  def discord_channel_id_for(:kill_charts), do: channel_id(:charts)
  def discord_channel_id_for(_), do: nil
end
