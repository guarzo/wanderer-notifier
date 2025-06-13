defmodule WandererNotifier.Notifications.Formatters.Status do
  @moduledoc """
  Status message formatting utilities for Discord notifications.
  Provides rich formatting for service status and startup events.
  """

  alias WandererNotifier.Utils.TimeUtils

  @info_color 0x3498DB

  @doc """
  Creates a rich formatted status/startup message with enhanced visual elements.

  ## Parameters
    - title: The title for the message (e.g., "WandererNotifier Started" or "Service Status Report")
    - description: Brief description of the message purpose
    - stats: The stats map containing notification counts and websocket info
    - uptime: Optional uptime in seconds (for status messages, nil for startup)
    - features_status: Map of feature statuses
    - license_status: Map with license information
    - systems_count: Number of tracked systems
    - characters_count: Number of tracked characters

  ## Returns
    - A generic structured map that can be converted to platform-specific format
  """
  def format_system_status_message(
        title,
        description,
        stats,
        uptime \\ nil,
        features_status,
        license_status,
        systems_count,
        characters_count
      ) do
    uptime_str = format_uptime(uptime)
    license_icon = get_license_icon(license_status)
    redisq_icon = get_redisq_status_icon(stats)
    notification_info = get_notification_info(stats)
    formatted_features = format_feature_statuses(features_status)
    killmails_received = Map.get(stats, :killmails_received, 0)

    notification_data = %{
      title: title,
      description: description,
      uptime_str: uptime_str,
      license_icon: license_icon,
      redisq_icon: redisq_icon,
      systems_count: systems_count,
      characters_count: characters_count,
      killmails_received: killmails_received,
      notification_info: notification_info,
      formatted_features: formatted_features
    }

    build_status_notification(notification_data)
  end

  defp format_uptime(nil), do: "🚀 Just started"

  defp format_uptime(uptime) do
    days = div(uptime, 86_400)
    hours = div(rem(uptime, 86_400), 3600)
    minutes = div(rem(uptime, 3600), 60)
    seconds = rem(uptime, 60)
    "⏱️ #{days}d #{hours}h #{minutes}m #{seconds}s"
  end

  defp get_license_icon(license_status) do
    if Map.get(license_status, :valid, false), do: "✅", else: "❌"
  end

  defp get_notification_info(stats) do
    if Map.has_key?(stats, :notifications) do
      format_notification_counts(stats.notifications)
    else
      "No notifications sent yet"
    end
  end

  defp format_feature_statuses(features_status) do
    primary_features = %{
      kill_notifications: Map.get(features_status, :kill_notifications_enabled, true),
      tracked_systems_notifications: Map.get(features_status, :system_tracking_enabled, true),
      tracked_characters_notifications:
        Map.get(features_status, :character_tracking_enabled, true)
    }

    [
      format_feature_item("Kill Notifications", primary_features.kill_notifications),
      format_feature_item("System Notifications", primary_features.tracked_systems_notifications),
      format_feature_item(
        "Character Notifications",
        primary_features.tracked_characters_notifications
      )
    ]
    |> Enum.join("\n")
  end

  defp build_status_notification(data) do
    %{
      type: :status_notification,
      title: data.title,
      description: "#{data.description}\n\n**System Status Overview:**",
      color: @info_color,
      timestamp: TimeUtils.log_timestamp(),
      thumbnail: %{
        url: "https://images.evetech.net/corporations/1_000_001/logo?size=128"
      },
      footer: %{
        text: "Wanderer Notifier v#{get_app_version()}"
      },
      fields: [
        %{name: "Uptime", value: data.uptime_str, inline: true},
        %{name: "License", value: data.license_icon, inline: true},
        %{name: "Zkill", value: data.redisq_icon, inline: true},
        %{name: "Systems", value: "🗺️ #{data.systems_count}", inline: true},
        %{name: "Characters", value: "👤 #{data.characters_count}", inline: true},
        %{name: "Killmails", value: "🗄️ #{data.killmails_received}", inline: true},
        %{name: "📊 Notifications", value: data.notification_info, inline: false},
        %{name: "⚙️ Primary Features", value: data.formatted_features, inline: false}
      ]
    }
  end

  defp format_feature_item(name, enabled) do
    if enabled, do: "✅ #{name}", else: "❌ #{name}"
  end

  defp format_notification_counts(%{} = notifications) do
    total = Map.get(notifications, :total, 0)
    kills = Map.get(notifications, :kills, 0)
    systems = Map.get(notifications, :systems, 0)
    characters = Map.get(notifications, :characters, 0)

    "Total: **#{total}** (Kills: **#{kills}**, Systems: **#{systems}**, Characters: **#{characters}**)"
  end

  defp get_redisq_status_icon(stats) do
    if Map.has_key?(stats, :redisq) do
      redisq_status = stats.redisq
      get_icon_by_connection_state(redisq_status)
    else
      "❓"
    end
  end

  defp get_icon_by_connection_state(%{connected: false}), do: "🔴"
  defp get_icon_by_connection_state(%{connected: true, last_message: nil}), do: "🟡"
  defp get_icon_by_connection_state(%{connected: true}), do: "🟢"
  defp get_icon_by_connection_state(_), do: "❓"

  defp get_app_version do
    WandererNotifier.Config.Version.version()
  end
end

defmodule WandererNotifier.Notifiers.StatusNotifier do
  @moduledoc """
  Sends rich status notifications by gathering all relevant state and using the Status formatter.
  """
  alias WandererNotifier.Notifications.Formatters.Status, as: StatusFormatter
  alias WandererNotifier.Notifications.Formatters.Common, as: CommonFormatter
  alias WandererNotifier.Core.Stats
  alias WandererNotifier.Config
  alias WandererNotifier.License.Service, as: LicenseService

  @doc """
  Gathers all relevant state and sends a status message to the main notification channel.
  """
  def send_status_message(title, description) do
    stats = Stats.get_stats()
    features_status = Config.features()

    # Convert features_status (always a list) to a map for the formatter
    features_map = Enum.into(features_status, %{})

    systems_count = Map.get(stats, :systems_count, 0)
    characters_count = Map.get(stats, :characters_count, 0)

    # Use LicenseService.status/0 for license status
    license_status = LicenseService.status()

    notification =
      StatusFormatter.format_system_status_message(
        title,
        description,
        stats,
        stats.uptime_seconds,
        features_map,
        license_status,
        systems_count,
        characters_count
      )

    # Convert to discord format
    embed = CommonFormatter.to_discord_format(notification)

    # Try to send the notification - if it fails, log but don't crash
    try do
      WandererNotifier.Notifications.Dispatcher.send_discord_embed(embed)
    rescue
      e ->
        # Log but don't crash the process
        require Logger
        Logger.error("Failed to send status notification: #{Exception.message(e)}")
        {:error, "Failed to send notification: #{Exception.message(e)}"}
    end
  end
end
