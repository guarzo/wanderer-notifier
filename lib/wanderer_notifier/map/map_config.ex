defmodule WandererNotifier.Map.MapConfig do
  @moduledoc """
  Configuration for a single map.

  Holds all per-map settings: Discord credentials, channel routing,
  feature flags, and tracking settings. Constructed either from the
  notifier config API response or from legacy environment variables.
  """

  alias WandererNotifier.Shared.Config

  @type discord_channels :: %{
          primary: String.t() | nil,
          system_kill: String.t() | nil,
          character_kill: String.t() | nil,
          system: String.t() | nil,
          character: String.t() | nil,
          rally: String.t() | nil
        }

  @type discord_config :: %{
          bot_token: String.t() | nil,
          application_id: String.t() | nil,
          guild_id: String.t() | nil,
          channels: discord_channels(),
          rally_group_ids: [integer()]
        }

  @type features_config :: %{
          notifications_enabled: boolean(),
          kill_notifications_enabled: boolean(),
          system_notifications_enabled: boolean(),
          character_notifications_enabled: boolean(),
          rally_notifications_enabled: boolean(),
          status_messages_enabled: boolean(),
          wormhole_only_kill_notifications: boolean(),
          track_kspace: boolean(),
          priority_systems_only: boolean(),
          notable_items_enabled: boolean(),
          voice_participant_notifications_enabled: boolean()
        }

  @type settings_config :: %{
          corporation_kill_focus: [integer()],
          character_exclude_list: [String.t()],
          system_exclude_list: [String.t()]
        }

  @type t :: %__MODULE__{
          slug: String.t(),
          name: String.t(),
          map_id: String.t(),
          owner: String.t() | nil,
          api_token: String.t() | nil,
          discord: discord_config(),
          features: features_config(),
          settings: settings_config()
        }

  @default_features %{
    notifications_enabled: true,
    kill_notifications_enabled: true,
    system_notifications_enabled: true,
    character_notifications_enabled: true,
    rally_notifications_enabled: true,
    status_messages_enabled: false,
    wormhole_only_kill_notifications: false,
    track_kspace: true,
    priority_systems_only: false,
    notable_items_enabled: false,
    voice_participant_notifications_enabled: false
  }

  @default_channels %{
    primary: nil,
    system_kill: nil,
    character_kill: nil,
    system: nil,
    character: nil,
    rally: nil
  }

  @default_settings %{
    corporation_kill_focus: [],
    character_exclude_list: [],
    system_exclude_list: []
  }

  defstruct [
    :slug,
    :name,
    :map_id,
    :owner,
    :api_token,
    discord: %{
      bot_token: nil,
      application_id: nil,
      guild_id: nil,
      channels: @default_channels,
      rally_group_ids: []
    },
    features: @default_features,
    settings: @default_settings
  ]

  # ============================================================================
  # Constructors
  # ============================================================================

  @doc """
  Builds a MapConfig from API response data.

  Expects a map with string keys as returned by the notifier config API.
  Returns `{:ok, config}` or `{:error, reason}`.
  """
  @spec from_api(map()) :: {:ok, t()} | {:error, term()}
  def from_api(data) when is_map(data) do
    with {:ok, slug} <- require_field(data, "slug"),
         {:ok, name} <- require_field(data, "name"),
         {:ok, map_id} <- require_field(data, "map_id") do
      {:ok, build_from_api(data, slug, name, map_id)}
    end
  end

  def from_api(_), do: {:error, :invalid_data}

  defp build_from_api(data, slug, name, map_id) do
    %__MODULE__{
      slug: slug,
      name: name,
      map_id: to_string(map_id),
      owner: data["owner"],
      api_token: data["api_token"],
      discord: parse_discord(data["discord"] || %{}),
      features: parse_features(data["features"] || %{}),
      settings: parse_settings(data["settings"] || %{})
    }
  end

  @doc """
  Builds a MapConfig from legacy environment variables.

  Used as a backwards-compatible fallback when the notifier config API
  is unavailable. Constructs a single MapConfig mirroring today's
  single-map behavior.
  """
  @spec from_env() :: t()
  def from_env do
    map_name = System.get_env("MAP_NAME", "default")

    %__MODULE__{
      slug: map_name,
      name: map_name,
      map_id: map_name,
      owner: nil,
      api_token: System.get_env("MAP_API_KEY"),
      discord: %{
        bot_token: System.get_env("DISCORD_BOT_TOKEN"),
        application_id: System.get_env("DISCORD_APPLICATION_ID"),
        guild_id: System.get_env("DISCORD_GUILD_ID"),
        channels: %{
          primary: System.get_env("DISCORD_CHANNEL_ID"),
          system_kill: System.get_env("DISCORD_SYSTEM_KILL_CHANNEL_ID"),
          character_kill: System.get_env("DISCORD_CHARACTER_KILL_CHANNEL_ID"),
          system: System.get_env("DISCORD_SYSTEM_CHANNEL_ID"),
          character: System.get_env("DISCORD_CHARACTER_CHANNEL_ID"),
          rally: System.get_env("DISCORD_RALLY_CHANNEL_ID")
        },
        rally_group_ids: Application.get_env(:wanderer_notifier, :discord_rally_group_ids, [])
      },
      features: %{
        notifications_enabled: Config.notifications_enabled?(),
        kill_notifications_enabled: Config.kill_notifications_enabled?(),
        system_notifications_enabled: Config.system_notifications_enabled?(),
        character_notifications_enabled: Config.character_notifications_enabled?(),
        rally_notifications_enabled: Config.rally_notifications_enabled?(),
        status_messages_enabled: Config.status_messages_enabled?(),
        wormhole_only_kill_notifications: Config.wormhole_only_kill_notifications?(),
        track_kspace: Config.track_kspace_enabled?(),
        priority_systems_only: Config.priority_systems_only?(),
        notable_items_enabled: Config.notable_items_enabled?(),
        voice_participant_notifications_enabled: Config.voice_participant_notifications_enabled?()
      },
      settings: %{
        corporation_kill_focus: Config.corporation_kill_focus(),
        character_exclude_list:
          Application.get_env(:wanderer_notifier, :character_exclude_list, []),
        system_exclude_list: Application.get_env(:wanderer_notifier, :system_exclude_list, [])
      }
    }
  end

  # ============================================================================
  # Query Functions
  # ============================================================================

  @doc """
  Checks if a feature flag is enabled for this map.

  ## Examples

      iex> feature_enabled?(map_config, :kill_notifications_enabled)
      true
  """
  @spec feature_enabled?(t(), atom()) :: boolean()
  def feature_enabled?(%__MODULE__{features: features}, feature) when is_atom(feature) do
    Map.get(features, feature, false)
  end

  @doc """
  Gets the Discord channel ID for a notification type.

  Falls back to the primary channel if the specific channel is not configured.

  ## Notification types
  - `:primary` - default channel
  - `:system` - system tracking notifications
  - `:character` - character tracking notifications
  - `:system_kill` - system kill notifications
  - `:character_kill` - character kill notifications
  - `:rally` - rally point notifications
  """
  @spec channel_for(t(), atom()) :: String.t() | nil
  def channel_for(%__MODULE__{discord: discord}, type) when is_atom(type) do
    Map.get(discord.channels, type) || Map.get(discord.channels, :primary)
  end

  @doc """
  Gets the Discord bot token for this map.
  """
  @spec bot_token(t()) :: String.t() | nil
  def bot_token(%__MODULE__{discord: %{bot_token: token}}), do: token

  @doc """
  Gets the Discord rally group IDs for this map.
  """
  @spec rally_group_ids(t()) :: [integer()]
  def rally_group_ids(%__MODULE__{discord: %{rally_group_ids: ids}}), do: ids

  @doc """
  Gets the corporation kill focus list for this map.
  """
  @spec corporation_kill_focus(t()) :: [integer()]
  def corporation_kill_focus(%__MODULE__{settings: %{corporation_kill_focus: corps}}), do: corps

  @doc """
  Checks if corporation kill focus is configured for this map.
  """
  @spec corporation_kill_focus_enabled?(t()) :: boolean()
  def corporation_kill_focus_enabled?(%__MODULE__{} = config) do
    corporation_kill_focus(config) != []
  end

  @doc """
  Checks if notifications are fully enabled for a given type.

  Short-circuits on global ENV flags first (so an API map cannot re-enable
  a feature that is globally disabled), then checks per-map flags.
  """
  @spec notifications_fully_enabled?(t(), atom()) :: boolean()
  def notifications_fully_enabled?(%__MODULE__{} = config, type) when is_atom(type) do
    Config.notifications_enabled?() and
      global_feature_enabled?(type) and
      feature_enabled?(config, :notifications_enabled) and
      feature_enabled?(config, type)
  end

  defp global_feature_enabled?(:kill_notifications_enabled),
    do: Config.kill_notifications_enabled?()

  defp global_feature_enabled?(:system_notifications_enabled),
    do: Config.system_notifications_enabled?()

  defp global_feature_enabled?(:character_notifications_enabled),
    do: Config.character_notifications_enabled?()

  defp global_feature_enabled?(:rally_notifications_enabled),
    do: Config.rally_notifications_enabled?()

  defp global_feature_enabled?(_), do: true

  # ============================================================================
  # Private Helpers
  # ============================================================================

  defp require_field(data, key) do
    case data[key] do
      nil -> {:error, {:missing_field, key}}
      "" -> {:error, {:empty_field, key}}
      value -> {:ok, value}
    end
  end

  defp parse_discord(data) when is_map(data) do
    %{
      bot_token: normalize_bot_token(data["bot_token"]),
      application_id: data["application_id"],
      guild_id: data["guild_id"],
      channels: parse_channels(data["channels"] || %{}),
      rally_group_ids: parse_integer_list(data["rally_group_ids"])
    }
  end

  defp parse_discord(_),
    do: %{
      bot_token: nil,
      application_id: nil,
      guild_id: nil,
      channels: @default_channels,
      rally_group_ids: []
    }

  defp parse_channels(data) when is_map(data) do
    %{
      primary: data["primary"],
      system_kill: data["system_kill"],
      character_kill: data["character_kill"],
      system: data["system"],
      character: data["character"],
      rally: data["rally"]
    }
  end

  defp parse_channels(_), do: @default_channels

  defp parse_features(data) when is_map(data) do
    %{
      notifications_enabled: get_bool(data, "notifications_enabled", true),
      kill_notifications_enabled: get_bool(data, "kill_notifications_enabled", true),
      system_notifications_enabled: get_bool(data, "system_notifications_enabled", true),
      character_notifications_enabled: get_bool(data, "character_notifications_enabled", true),
      rally_notifications_enabled: get_bool(data, "rally_notifications_enabled", true),
      status_messages_enabled: get_bool(data, "status_messages_enabled", false),
      wormhole_only_kill_notifications: get_bool(data, "wormhole_only_kill_notifications", false),
      track_kspace: get_bool(data, "track_kspace", true),
      priority_systems_only: get_bool(data, "priority_systems_only", false),
      notable_items_enabled: get_bool(data, "notable_items_enabled", false),
      voice_participant_notifications_enabled:
        get_bool(data, "voice_participant_notifications_enabled", false)
    }
  end

  defp parse_features(_), do: @default_features

  defp parse_settings(data) when is_map(data) do
    %{
      corporation_kill_focus: parse_integer_list(data["corporation_kill_focus"]),
      character_exclude_list: parse_string_list(data["character_exclude_list"]),
      system_exclude_list: parse_string_list(data["system_exclude_list"])
    }
  end

  defp parse_settings(_), do: @default_settings

  defp get_bool(map, key, default) when is_map(map) and is_binary(key) do
    case Map.get(map, key) do
      nil -> default
      val when is_boolean(val) -> val
      _ -> default
    end
  end

  defp parse_integer_list(nil), do: []

  defp parse_integer_list(list) when is_list(list) do
    list
    |> Enum.flat_map(fn
      val when is_integer(val) ->
        [val]

      val when is_binary(val) ->
        case Integer.parse(val) do
          {int, ""} -> [int]
          _ -> []
        end

      _ ->
        []
    end)
    |> Enum.uniq()
  end

  defp parse_integer_list(_), do: []

  defp parse_string_list(nil), do: []

  defp parse_string_list(list) when is_list(list) do
    list
    |> Enum.filter(&is_binary/1)
    |> Enum.uniq()
  end

  defp parse_string_list(_), do: []

  defp normalize_bot_token(nil), do: nil
  defp normalize_bot_token(""), do: nil
  defp normalize_bot_token(token) when is_binary(token), do: token
  defp normalize_bot_token(_), do: nil
end
