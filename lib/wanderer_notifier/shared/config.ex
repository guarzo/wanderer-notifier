defmodule WandererNotifier.Shared.Config do
  @moduledoc """
  Application configuration interface using environment variables and application config.

  Provides a clean, direct interface for configuration without the overhead
  of complex validation, schemas, or configuration managers.
  """

  alias WandererNotifier.Shared.Env

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

  @doc "Get Discord rally group IDs (optional) - returns a list of numeric group IDs"
  def discord_rally_group_ids do
    Application.get_env(:wanderer_notifier, :discord_rally_group_ids, [])
  end

  @doc "Get all Discord channel configuration in a single call"
  def discord_channels do
    %{
      primary: discord_channel_id(),
      rally: discord_rally_channel_id(),
      system: discord_system_channel_id(),
      character: discord_character_channel_id(),
      character_kill: discord_character_kill_channel_id(),
      system_kill: discord_system_kill_channel_id()
    }
  end

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
  def status_messages_enabled?, do: get_boolean("STATUS_MESSAGES_ENABLED", false)

  @doc "Check if K-space tracking is enabled"
  def track_kspace_enabled?, do: get_boolean("TRACK_KSPACE_ENABLED", true)

  @doc "Check if only priority systems should be notified"
  def priority_systems_only?, do: get_boolean("PRIORITY_SYSTEMS_ONLY", false)

  @doc "Check if kill notifications should only be sent for wormhole systems"
  def wormhole_only_kill_notifications? do
    case Application.get_env(:wanderer_notifier, :wormhole_only_kill_notifications) do
      nil -> get_boolean("WORMHOLE_ONLY_KILL_NOTIFICATIONS", false)
      value -> value
    end
  end

  @doc "Check if kill notifications are fully enabled (both global and kill-specific flags)"
  def kill_notifications_fully_enabled? do
    notifications_enabled?() and kill_notifications_enabled?()
  end

  @doc "Check if system notifications are fully enabled (both global and system-specific flags)"
  def system_notifications_fully_enabled? do
    notifications_enabled?() and system_notifications_enabled?()
  end

  @doc "Check if character notifications are fully enabled (both global and character-specific flags)"
  def character_notifications_fully_enabled? do
    notifications_enabled?() and character_notifications_enabled?()
  end

  # ──────────────────────────────────────────────────────────────────────────────
  # Exclusion Lists
  # ──────────────────────────────────────────────────────────────────────────────

  @doc "Get list of corporation IDs to exclude from kill notifications"
  def corporation_exclude_list do
    Application.get_env(:wanderer_notifier, :corporation_exclude_list, [])
  end

  @doc "Check if corporation exclusion is configured (has at least one ID)"
  def corporation_exclusion_enabled? do
    corporation_exclude_list() != []
  end

  @doc "Get list of corporation IDs allowed for character kill notifications"
  def character_tracking_corporation_ids do
    Application.get_env(:wanderer_notifier, :character_tracking_corporation_ids, [])
  end

  @doc "Check if character corporation filtering is enabled for kill notifications"
  def character_tracking_corporation_filter_enabled? do
    character_tracking_corporation_ids() != []
  end

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

  # ──────────────────────────────────────────────────────────────────────────────
  # SSE Configuration
  # ──────────────────────────────────────────────────────────────────────────────

  @doc "Get SSE receive timeout in milliseconds (default: :infinity)"
  def sse_recv_timeout do
    case get_env_private("SSE_RECV_TIMEOUT") do
      nil -> :infinity
      "infinity" -> :infinity
      value when is_binary(value) -> String.to_integer(value)
    end
  end

  @doc "Get SSE connection timeout in milliseconds (default: 30000)"
  def sse_connect_timeout, do: get_integer("SSE_CONNECT_TIMEOUT", 30_000)

  @doc "Get SSE keepalive interval in seconds (default: 30)"
  def sse_keepalive_interval, do: get_integer("SSE_KEEPALIVE_INTERVAL", 30)

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
    do:
      Application.get_env(
        :wanderer_notifier,
        :license_manager_api_url,
        "https://lm.wanderer.ltd/api"
      )

  @doc "Get notifier API token (required)"
  def notifier_api_token, do: Application.get_env(:wanderer_notifier, :api_token)

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

  @doc "Get maximum killmail age for notifications in seconds"
  def max_killmail_age_seconds, do: get_integer("MAX_KILLMAIL_AGE_SECONDS", 3600)

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

  # ──────────────────────────────────────────────────────────────────────────────
  # Safe Retrieval Functions (return tuples instead of raising)
  # ──────────────────────────────────────────────────────────────────────────────

  @doc """
  Safely get map URL, returning {:ok, value} or {:error, :not_found}
  """
  def map_url_safe do
    try do
      {:ok, map_url()}
    rescue
      _ -> {:error, :not_found}
    end
  end

  @doc """
  Safely get license key, returning {:ok, value} or {:error, :not_found}
  """
  def license_key_safe do
    try do
      {:ok, license_key()}
    rescue
      _ -> {:error, :not_found}
    end
  end

  @doc """
  Safely get Discord bot token, returning {:ok, value} or {:error, :not_found}
  """
  def discord_bot_token_safe do
    try do
      {:ok, discord_bot_token()}
    rescue
      _ -> {:error, :not_found}
    end
  end

  # ──────────────────────────────────────────────────────────────────────────────
  # Helper Functions (private implementations)
  # ──────────────────────────────────────────────────────────────────────────────

  defp get_env_private(key, default \\ nil), do: Env.get(key, default)
  defp get_required_env(key), do: Env.get_required(key)
  defp get_boolean(key, default), do: Env.get_boolean(key, default)
  defp get_integer(key, default), do: Env.get_integer(key, default)
end
