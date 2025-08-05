defmodule WandererNotifier.Shared.SimpleConfig do
  @moduledoc """
  Simplified configuration access using environment variables and application config.

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
  def discord_application_id, do: get_env("DISCORD_APPLICATION_ID")

  @doc "Get Discord guild ID (optional)"
  def discord_guild_id, do: get_env("DISCORD_GUILD_ID")

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

  @doc "Check if status messages are enabled"
  def enable_status_messages?, do: get_boolean("ENABLE_STATUS_MESSAGES", false)

  @doc "Check if K-space tracking is enabled"
  def track_kspace_enabled?, do: get_boolean("TRACK_KSPACE_ENABLED", true)

  @doc "Check if only priority systems should be notified"
  def priority_systems_only?, do: get_boolean("PRIORITY_SYSTEMS_ONLY", false)

  # ──────────────────────────────────────────────────────────────────────────────
  # Service URLs
  # ──────────────────────────────────────────────────────────────────────────────

  @doc "Get WebSocket URL for killmail streaming"
  def websocket_url, do: get_env("WEBSOCKET_URL", "ws://host.docker.internal:4004")

  @doc "Get WandererKills API URL"
  def wanderer_kills_url, do: get_env("WANDERER_KILLS_URL", "http://host.docker.internal:4004")

  @doc "Get map API URL (required)"
  def map_url, do: get_required_env("MAP_URL")

  @doc "Get map name (required)"
  def map_name, do: get_required_env("MAP_NAME")

  @doc "Get map API key (required)"
  def map_api_key, do: get_required_env("MAP_API_KEY")

  # ──────────────────────────────────────────────────────────────────────────────
  # License Configuration
  # ──────────────────────────────────────────────────────────────────────────────

  @doc "Get license API token (required)"
  def license_api_token, do: get_required_env("LICENSE_API_TOKEN")

  @doc "Get license key (required)"
  def license_key, do: get_required_env("LICENSE_KEY")

  @doc "Get license validation URL"
  def license_validation_url,
    do: get_env("LICENSE_VALIDATION_URL", "https://lm.wanderer.ltd/validate_bot")

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
  def janice_api_token, do: get_env("JANICE_API_TOKEN")

  # ──────────────────────────────────────────────────────────────────────────────
  # Helper Functions
  # ──────────────────────────────────────────────────────────────────────────────

  defp get_env(key, default \\ nil) do
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
