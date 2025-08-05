defmodule WandererNotifier.Shared.Config do
  @moduledoc """
  Application configuration interface using environment variables and application config.

  Provides a clean, direct interface for configuration without the overhead
  of complex validation, schemas, or configuration managers.
  """

  # ──────────────────────────────────────────────────────────────────────────────
  # Discord Configuration
  # ──────────────────────────────────────────────────────────────────────────────

  @doc "Get Discord bot token (required)"
  def discord_bot_token, do: get_required_env("DISCORD_BOT_TOKEN")

  @doc "Get Discord channel ID (required)"
  def discord_channel_id, do: get_required_env("DISCORD_CHANNEL_ID")

  @doc "Get Discord application ID (optional)"
  def discord_application_id do
    case Application.get_env(:wanderer_notifier, :discord_application_id) do
      nil -> get_env_private("DISCORD_APPLICATION_ID")
      value -> value
    end
  end

  @doc "Get Discord guild ID (optional)"
  def discord_guild_id, do: get_env_private("DISCORD_GUILD_ID")

  @doc "Get Discord rally channel ID (optional)"
  def discord_rally_channel_id, do: get_env_private("DISCORD_RALLY_CHANNEL_ID")

  @doc "Get Discord system channel ID (optional)"
  def discord_system_channel_id, do: get_env_private("DISCORD_SYSTEM_CHANNEL_ID")

  @doc "Get Discord character channel ID (optional)"
  def discord_character_channel_id, do: get_env_private("DISCORD_CHARACTER_CHANNEL_ID")

  @doc "Get Discord character kill channel ID (optional)"
  def discord_character_kill_channel_id, do: get_env_private("DISCORD_CHARACTER_KILL_CHANNEL_ID")

  @doc "Get Discord system kill channel ID (optional)"
  def discord_system_kill_channel_id, do: get_env_private("DISCORD_SYSTEM_KILL_CHANNEL_ID")

  @doc "Get Discord rally group ID (optional)"
  def discord_rally_group_id, do: get_env_private("DISCORD_RALLY_GROUP_ID")

  # ──────────────────────────────────────────────────────────────────────────────
  # Feature Flags
  # ──────────────────────────────────────────────────────────────────────────────

  @doc "Check if notifications are enabled globally"
  def notifications_enabled?, do: get_boolean("NOTIFICATIONS_ENABLED", true)

  @doc "Check if kill notifications are enabled"
  def kill_notifications_enabled?, do: get_boolean("KILL_NOTIFICATIONS_ENABLED", true)

  @doc "Check if system notifications are enabled"
  def system_notifications_enabled?, do: get_boolean("SYSTEM_NOTIFICATIONS_ENABLED", true)

  @doc "Check if character notifications are enabled"
  def character_notifications_enabled?, do: get_boolean("CHARACTER_NOTIFICATIONS_ENABLED", true)

  @doc "Check if rally notifications are enabled"
  def rally_notifications_enabled?, do: get_boolean("RALLY_NOTIFICATIONS_ENABLED", true)

  @doc "Check if status messages are enabled"
  def enable_status_messages?, do: get_boolean("ENABLE_STATUS_MESSAGES", false)

  @doc "Check if K-space tracking is enabled"
  def track_kspace_enabled?, do: get_boolean("TRACK_KSPACE_ENABLED", true)

  @doc "Check if only priority systems should be notified"
  def priority_systems_only?, do: get_boolean("PRIORITY_SYSTEMS_ONLY", false)

  # ──────────────────────────────────────────────────────────────────────────────
  # Notable Items Configuration
  # ──────────────────────────────────────────────────────────────────────────────

  @doc "Get notable items ISK threshold (default: 50M ISK)"
  def notable_items_threshold_isk, do: get_integer("NOTABLE_ITEMS_THRESHOLD_ISK", 50_000_000)

  @doc "Get notable items limit (default: 5 items)"
  def notable_items_limit, do: get_integer("NOTABLE_ITEMS_LIMIT", 5)

  # ──────────────────────────────────────────────────────────────────────────────
  # Service URLs
  # ──────────────────────────────────────────────────────────────────────────────

  @doc "Get WebSocket URL for killmail streaming"
  def websocket_url, do: get_env_private("WEBSOCKET_URL", "ws://host.docker.internal:4004")

  @doc "Get WandererKills API URL"
  def wanderer_kills_url,
    do: get_env_private("WANDERER_KILLS_URL", "http://host.docker.internal:4004")

  @doc "Get map API URL (required)"
  def map_url, do: get_required_env("MAP_URL")

  @doc "Get map name (required)"
  def map_name, do: get_required_env("MAP_NAME")

  @doc "Get map API key (required)"
  def map_api_key, do: get_required_env("MAP_API_KEY")

  # ──────────────────────────────────────────────────────────────────────────────
  # License Configuration
  # ──────────────────────────────────────────────────────────────────────────────

  @doc "Get license key (required)"
  def license_key, do: get_required_env("LICENSE_KEY")

  @doc "Get license validation URL"
  def license_validation_url,
    do: get_env_private("LICENSE_VALIDATION_URL", "https://lm.wanderer.ltd/validate_bot")

  @doc "Get license manager API key (required)"
  def license_manager_api_key, do: get_required_env("LICENSE_MANAGER_API_KEY")

  @doc "Get license manager API URL"
  def license_manager_api_url,
    do: get_env_private("LICENSE_MANAGER_API_URL", "https://lm.wanderer.ltd")

  @doc "Get notifier API token (required)"
  def notifier_api_token, do: get_required_env("NOTIFIER_API_TOKEN")

  # ──────────────────────────────────────────────────────────────────────────────
  # Application Settings
  # ──────────────────────────────────────────────────────────────────────────────

  @doc "Get application environment"
  def environment, do: Application.get_env(:wanderer_notifier, :env, :prod)

  @doc "Check if running in production"
  def production?, do: environment() == :prod

  @doc "Check if running in test"
  def test?, do: environment() == :test

  @doc "Get application version"
  def version, do: Application.spec(:wanderer_notifier, :vsn) |> to_string()

  # ──────────────────────────────────────────────────────────────────────────────
  # Notification Settings
  # ──────────────────────────────────────────────────────────────────────────────

  @doc "Get startup suppression duration in seconds"
  def startup_suppression_seconds, do: get_integer("STARTUP_SUPPRESSION_SECONDS", 30)

  @doc "Get deduplication TTL in seconds"
  def deduplication_ttl_seconds, do: get_integer("DEDUPLICATION_TTL_SECONDS", 1800)

  @doc "Check if notable items are enabled"
  def notable_items_enabled?, do: get_boolean("NOTABLE_ITEMS_ENABLED", false)

  @doc "Get Janice API token for item pricing"
  def janice_api_token, do: get_env_private("JANICE_API_TOKEN")

  # ──────────────────────────────────────────────────────────────────────────────
  # Additional Configuration Methods
  # ──────────────────────────────────────────────────────────────────────────────

  @doc "Get map API token"
  def map_token, do: map_api_key()

  @doc "Get API token for general use"
  def api_token, do: get_env_private("API_TOKEN")

  @doc "Get telemetry logging enabled flag"
  def telemetry_logging_enabled?, do: get_boolean("TELEMETRY_LOGGING_ENABLED", false)

  @doc "Get status messages enabled flag"
  def status_messages_enabled?, do: enable_status_messages?()

  @doc "Get schedulers enabled flag"
  def schedulers_enabled?, do: get_boolean("SCHEDULERS_ENABLED", true)

  @doc "Get host configuration"
  def host, do: get_env_private("HOST", "0.0.0.0")

  @doc "Get port configuration"
  def port, do: get_integer("PORT", 4000)

  @doc "Get voice participant notifications enabled flag"
  def voice_participant_notifications_enabled?,
    do: get_boolean("VOICE_PARTICIPANT_NOTIFICATIONS_ENABLED", false)

  @doc "Get license refresh interval in milliseconds"
  def license_refresh_interval, do: get_integer("LICENSE_REFRESH_INTERVAL", 3_600_000)

  @doc "Get discord kill channel ID (fallback method)"
  def discord_kill_channel_id, do: discord_channel_id()

  @doc "Check if feature is enabled"
  def feature_enabled?(feature) when is_atom(feature) do
    feature_key = feature |> Atom.to_string() |> String.upcase()
    get_boolean(feature_key, false)
  end

  @doc "Get features map"
  def features do
    %{
      discord_components: feature_enabled?(:discord_components),
      rich_embeds: feature_enabled?(:rich_embeds),
      system_tracking: feature_enabled?(:system_tracking_enabled),
      voice_notifications: voice_participant_notifications_enabled?()
    }
  end

  @doc "Get environment variable (legacy compatibility)"
  def get_env(key) when is_atom(key), do: get_env(Atom.to_string(key))
  def get_env(key) when is_binary(key), do: System.get_env(key)

  @doc "Get configuration with default (legacy compatibility)"
  def get(key, default) when is_atom(key) do
    case key do
      :map_url ->
        map_url()

      :map_name ->
        map_name()

      :map_api_key ->
        map_api_key()

      :janice_api_token ->
        janice_api_token()

      :discord_debug_logging ->
        get_boolean("DISCORD_DEBUG_LOGGING", default)

      :feature_flags ->
        get_boolean("FEATURE_FLAGS_ENABLED", default)

      _ ->
        key
        |> Atom.to_string()
        |> String.upcase()
        |> System.get_env(default)
    end
  end

  def get(key) when is_atom(key), do: get(key, nil)

  # ──────────────────────────────────────────────────────────────────────────────
  # Helper Functions (private implementations)
  # ──────────────────────────────────────────────────────────────────────────────

  defp get_env_private(key, default \\ nil) do
    System.get_env(key, default)
  end

  defp get_required_env(key) do
    case System.get_env(key) do
      nil -> raise "Missing required environment variable: #{key}"
      "" -> raise "Empty required environment variable: #{key}"
      value -> value
    end
  end

  defp get_boolean(key, default) do
    case System.get_env(key) do
      nil -> default
      "true" -> true
      "false" -> false
      "1" -> true
      "0" -> false
      _ -> default
    end
  end

  defp get_integer(key, default) do
    case System.get_env(key) do
      nil ->
        default

      value ->
        case Integer.parse(value) do
          {int, ""} -> int
          _ -> default
        end
    end
  end
end
