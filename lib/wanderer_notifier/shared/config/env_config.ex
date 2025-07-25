defmodule WandererNotifier.Shared.Config.EnvConfig do
  @moduledoc """
  Centralized environment variable configuration.

  This module consolidates all environment variable parsing into a single place,
  reducing duplication and providing a consistent interface for accessing
  environment-based configuration.
  """

  alias WandererNotifier.Shared.Config.Utils

  # ══════════════════════════════════════════════════════════════════════════════
  # Environment Variable Definitions (Single Source of Truth)
  # ══════════════════════════════════════════════════════════════════════════════

  @env_vars %{
    # Discord Configuration
    discord_bot_token: {"DISCORD_BOT_TOKEN", :string, :required},
    discord_application_id: {"DISCORD_APPLICATION_ID", :string, nil},
    discord_channel_id: {"DISCORD_CHANNEL_ID", :string, ""},
    discord_system_kill_channel_id: {"DISCORD_SYSTEM_KILL_CHANNEL_ID", :string, nil},
    discord_character_kill_channel_id: {"DISCORD_CHARACTER_KILL_CHANNEL_ID", :string, nil},
    discord_system_channel_id: {"DISCORD_SYSTEM_CHANNEL_ID", :string, nil},
    discord_character_channel_id: {"DISCORD_CHARACTER_CHANNEL_ID", :string, nil},

    # Map Configuration
    map_api_key: {"MAP_API_KEY", :string, :required},
    map_url: {"MAP_URL", :string, :required},
    map_name: {"MAP_NAME", :string, :required},

    # License Configuration
    license_key: {"LICENSE_KEY", :string, :required},
    license_manager_url: {"LICENSE_MANAGER_URL", :string, "https://lm.wanderer.ltd"},

    # Server Configuration
    port: {"PORT", :integer, 4000},
    host: {"HOST", :string, "localhost"},
    scheme: {"SCHEME", :string, "http"},
    public_url: {"PUBLIC_URL", :string, nil},
    secret_key_base:
      {"SECRET_KEY_BASE", :string,
       "wanderer_notifier_secret_key_base_default_for_development_only"},
    live_view_signing_salt: {"LIVE_VIEW_SIGNING_SALT", :string, "wanderer_liveview_salt"},

    # WebSocket & API Configuration
    websocket_url: {"WEBSOCKET_URL", :string, "ws://host.docker.internal:4004"},
    wanderer_kills_url: {"WANDERER_KILLS_URL", :string, "http://host.docker.internal:4004"},

    # Cache Configuration
    cache_dir: {"CACHE_DIR", :string, "/app/data/cache"},

    # Feature Flags
    notifications_enabled: {"NOTIFICATIONS_ENABLED", :boolean, true},
    kill_notifications_enabled: {"KILL_NOTIFICATIONS_ENABLED", :boolean, true},
    system_notifications_enabled: {"SYSTEM_NOTIFICATIONS_ENABLED", :boolean, true},
    character_notifications_enabled: {"CHARACTER_NOTIFICATIONS_ENABLED", :boolean, true},
    status_messages_enabled: {"ENABLE_STATUS_MESSAGES", :boolean, false},
    priority_systems_only: {"PRIORITY_SYSTEMS_ONLY", :boolean, false},

    # Lists
    character_exclude_list: {"CHARACTER_EXCLUDE_LIST", :comma_list, []},
    system_exclude_list: {"SYSTEM_EXCLUDE_LIST", :comma_list, []}
  }

  # ══════════════════════════════════════════════════════════════════════════════
  # Public Interface
  # ══════════════════════════════════════════════════════════════════════════════

  @doc """
  Gets all environment variables as a parsed configuration map.
  This replaces the scattered env var parsing in runtime.exs.
  """
  def get_all_config do
    @env_vars
    |> Enum.map(fn {key, spec} -> {key, get_env_value(spec)} end)
    |> Enum.into(%{})
  end

  @doc """
  Gets a specific environment variable value by key.
  """
  def get(key) when is_atom(key) do
    case Map.get(@env_vars, key) do
      nil -> {:error, :unknown_env_var}
      spec -> {:ok, get_env_value(spec)}
    end
  end

  @doc """
  Gets environment variables for a specific category.
  """
  def get_discord_config do
    filter_config([
      :discord_bot_token,
      :discord_application_id,
      :discord_channel_id,
      :discord_system_kill_channel_id,
      :discord_character_kill_channel_id,
      :discord_system_channel_id,
      :discord_character_channel_id
    ])
  end

  def get_map_config do
    filter_config([:map_api_key, :map_url, :map_name])
  end

  def get_server_config do
    filter_config([:port, :host, :scheme, :public_url, :secret_key_base, :live_view_signing_salt])
  end

  def get_feature_flags do
    filter_config([
      :notifications_enabled,
      :kill_notifications_enabled,
      :system_notifications_enabled,
      :character_notifications_enabled,
      :status_messages_enabled,
      :priority_systems_only
    ])
  end

  @doc """
  Validates required environment variables and returns errors for missing ones.
  """
  def validate_required do
    @env_vars
    |> Enum.filter(fn {_key, {_env_name, _type, default}} -> default == :required end)
    |> Enum.map(fn {key, {env_name, _type, _default}} ->
      case System.get_env(env_name) do
        nil -> {:error, key, env_name}
        "" -> {:error, key, env_name}
        _value -> {:ok, key}
      end
    end)
    |> Enum.filter(&match?({:error, _, _}, &1))
  end

  # ══════════════════════════════════════════════════════════════════════════════
  # Private Implementation
  # ══════════════════════════════════════════════════════════════════════════════

  defp get_env_value({env_name, type, default}) do
    env_value = System.get_env(env_name)
    parse_env_value(env_value, type, default)
  end

  defp parse_env_value(nil, _type, :required) do
    raise ArgumentError, "Required environment variable is not set"
  end

  defp parse_env_value(nil, _type, default), do: default

  defp parse_env_value("", _type, :required) do
    raise ArgumentError, "Required environment variable is empty"
  end

  defp parse_env_value("", _type, default), do: default

  defp parse_env_value(value, :string, _default), do: value
  defp parse_env_value(value, :integer, default), do: Utils.parse_int(value, default)
  defp parse_env_value(value, :boolean, default), do: Utils.parse_bool(value, default)
  defp parse_env_value(value, :comma_list, _default), do: Utils.parse_comma_list(value)

  defp filter_config(keys) do
    keys
    |> Enum.map(fn key -> {key, get_env_value(@env_vars[key])} end)
    |> Enum.into(%{})
  end

  # ══════════════════════════════════════════════════════════════════════════════
  # Legacy Support Functions (for gradual migration)
  # ══════════════════════════════════════════════════════════════════════════════

  @doc """
  Legacy function for direct environment variable access.
  Use get/1 instead for new code.
  """
  def fetch_env(key, default \\ nil) do
    System.get_env(key, default)
  end

  def fetch_env_int(key, default) do
    case System.get_env(key) do
      nil -> default
      "" -> default
      value -> Utils.parse_int(value, default)
    end
  end

  def fetch_env_bool(key, default) do
    case System.get_env(key) do
      nil -> default
      "" -> default
      value -> Utils.parse_bool(value, default)
    end
  end
end
