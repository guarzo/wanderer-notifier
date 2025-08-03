defmodule WandererNotifier.Domains.Notifications.NotificationService do
  @moduledoc """
  Clean notification service with pattern matching and no backwards compatibility.
  """

  require Logger
  alias WandererNotifier.Domains.Notifications.Notification
  alias WandererNotifier.Shared.Config
  alias WandererNotifier.Application.Services.ApplicationService
  alias WandererNotifier.Domains.Notifications.Notifiers.Discord.Notifier, as: DiscordNotifier
  alias WandererNotifier.Domains.Notifications.Determiner
  alias WandererNotifier.Domains.Notifications.Formatters.NotificationFormatter
  alias WandererNotifier.Domains.Tracking.Entities.System
  alias WandererNotifier.Shared.Utils.Startup

  # ═══════════════════════════════════════════════════════════════════════════════
  # Public API
  # ═══════════════════════════════════════════════════════════════════════════════

  @doc """
  Sends a notification based on its type.
  """
  def send(%Notification{type: :kill_notification} = notification) do
    if Config.notifications_enabled?() and Config.kill_notifications_enabled?() do
      send_kill_notification(notification)
    else
      {:ok, :notifications_disabled}
    end
  end

  def send(%Notification{type: :system_notification} = notification) do
    if Config.notifications_enabled?() and Config.system_notifications_enabled?() do
      send_system_notification(notification)
    else
      {:ok, :notifications_disabled}
    end
  end

  def send(%Notification{type: :character_notification} = notification) do
    if Config.notifications_enabled?() and Config.character_notifications_enabled?() do
      send_character_notification(notification)
    else
      {:ok, :notifications_disabled}
    end
  end

  def send(%Notification{type: :status_notification} = notification) do
    if Config.notifications_enabled?() do
      send_status_notification(notification)
    else
      {:ok, :notifications_disabled}
    end
  end

  def send(_), do: {:error, :invalid_notification}

  # ═══════════════════════════════════════════════════════════════════════════════
  # Kill Notifications
  # ═══════════════════════════════════════════════════════════════════════════════

  defp send_kill_notification(%Notification{data: %{killmail: killmail}} = notification) do
    # Check if we're in the startup suppression period
    if Startup.in_suppression_period?() do
      Logger.info("Skipping kill notification during startup suppression period",
        killmail_id: killmail.killmail_id,
        category: :notification
      )

      {:ok, :skipped_startup_suppression}
    else
      with {:ok, channel_id} <- determine_kill_channel(killmail),
           {:ok, _} <- validate_kill_data(killmail),
           :ok <- DiscordNotifier.send_kill_notification_to_channel(killmail, channel_id) do
        Logger.info("Successfully sent kill notification",
          type: :kill_notification,
          category: :notification
        )

        {:ok, notification}
      else
        {:error, reason} = error ->
          Logger.error("Failed to send kill notification",
            reason: inspect(reason),
            category: :notification
          )

          error
      end
    end
  end

  defp send_kill_notification(%Notification{}) do
    {:error, :invalid_kill_data}
  end

  defp determine_kill_channel(killmail) do
    case check_testing_override() do
      {:ok, nil} ->
        determine_normal_channel(killmail)

      {:ok, override_type} ->
        handle_testing_override(override_type)
    end
  end

  defp handle_testing_override(:character) do
    Logger.info("[TEST] Kill override: routing to character channel")
    channel_id = Config.discord_character_kill_channel_id() || Config.discord_channel_id()
    {:ok, channel_id}
  end

  defp handle_testing_override(:system) do
    Logger.info("[TEST] Kill override: routing to system channel")
    channel_id = Config.discord_system_kill_channel_id() || Config.discord_channel_id()
    {:ok, channel_id}
  end

  defp determine_normal_channel(killmail) do
    system_id = Map.get(killmail, :system_id)
    has_tracked_system = Determiner.tracked_system_for_killmail?(system_id)
    has_tracked_character = Determiner.has_tracked_character?(killmail)

    Logger.debug(
      "[Kill Channel Debug] Determining channel for killmail - system_id: #{system_id}, has_tracked_system: #{has_tracked_system}, has_tracked_character: #{has_tracked_character}"
    )

    # Validate that at least one entity is tracked
    if not has_tracked_character and not has_tracked_system do
      Logger.error(
        "[Kill Channel Error] Killmail has no tracked entities but reached notification service - system_id: #{system_id}, killmail_id: #{Map.get(killmail, :killmail_id)}"
      )

      {:error, :no_tracked_entities}
    else
      channel_id = select_channel_by_priority(has_tracked_character, has_tracked_system)

      Logger.debug(
        "[Kill Channel Debug] Selected channel: #{channel_id}, fallback: #{Config.discord_channel_id()}"
      )

      {:ok, channel_id || Config.discord_channel_id()}
    end
  end

  defp select_channel_by_priority(has_tracked_character, has_tracked_system) do
    Logger.debug(
      "[Channel Priority Debug] has_tracked_character: #{has_tracked_character}, has_tracked_system: #{has_tracked_system}, char_channel: #{Config.discord_character_kill_channel_id()}, sys_channel: #{Config.discord_system_kill_channel_id()}"
    )

    # Priority: Character kills take precedence over system kills
    if has_tracked_character do
      Config.discord_character_kill_channel_id()
    else
      # has_tracked_system must be true if we got here
      Config.discord_system_kill_channel_id()
    end
  end

  defp check_testing_override do
    try do
      WandererNotifier.Testing.NotificationTester.check_kill_override()
    rescue
      _e ->
        {:ok, nil}
    end
  end

  defp validate_kill_data(killmail) do
    if Map.get(killmail, :killmail_id) do
      {:ok, killmail}
    else
      {:error, :missing_killmail_id}
    end
  end

  # ═══════════════════════════════════════════════════════════════════════════════
  # System Notifications
  # ═══════════════════════════════════════════════════════════════════════════════

  defp send_system_notification(%Notification{data: system_data} = notification) do
    # Check if this is the first notification
    if ApplicationService.first_notification?(:system) do
      ApplicationService.mark_notification_sent(:system)
      {:ok, :skipped_first_run}
    else
      with {:ok, formatted} <- format_notification(system_data, notification),
           :ok <- send_to_system_channel(formatted) do
        Logger.info("Successfully sent system notification",
          type: :system_notification,
          category: :notification
        )

        {:ok, notification}
      else
        {:error, reason} = error ->
          Logger.error("Failed to send system notification",
            reason: inspect(reason),
            category: :notification
          )

          error
      end
    end
  end

  defp format_notification(system_data, _notification) do
    try do
      # Check if it's already a System struct or needs conversion
      system_struct =
        case system_data do
          %System{} = system ->
            Logger.debug(
              "[NotificationService] Using existing System struct - type: #{system.system_type}, statics: #{inspect(system.statics)}"
            )

            system

          _ ->
            Logger.debug(
              "[NotificationService] Converting map to System struct from data: #{inspect(Map.keys(system_data))}"
            )

            System.from_api_data(system_data)
        end

      # Format using NotificationFormatter
      formatted = NotificationFormatter.format_notification(system_struct)

      # Add priority styling if needed
      # Priority is only present in the map data, not in the struct
      is_priority =
        case system_data do
          %System{} -> false
          %{priority: priority} -> priority || false
          _ -> false
        end

      embed =
        if is_priority do
          formatted
          |> Map.put(:title, "🚨 Priority System: #{system_struct.name}")
          # Red color
          |> Map.put(:color, 15_548_997)
        else
          formatted
        end

      {:ok, embed}
    rescue
      e ->
        Logger.error("Failed to format system notification",
          error: inspect(e),
          category: :notification
        )

        {:error, {:format_error, e}}
    end
  end

  defp send_to_system_channel(embed) do
    channel_id = Config.discord_system_channel_id() || Config.discord_channel_id()
    DiscordNotifier.send_notification(:send_discord_embed_to_channel, [channel_id, embed])
    :ok
  end

  # ═══════════════════════════════════════════════════════════════════════════════
  # Character Notifications
  # ═══════════════════════════════════════════════════════════════════════════════

  defp send_character_notification(%Notification{data: character_data} = notification) do
    # Check if this is the first notification
    if ApplicationService.first_notification?(:character) do
      ApplicationService.mark_notification_sent(:character)
      {:ok, :skipped_first_run}
    else
      with {:ok, formatted} <- format_notification(character_data),
           :ok <- send_to_character_channel(formatted) do
        Logger.info("Successfully sent character notification",
          type: :character_notification,
          category: :notification
        )

        {:ok, notification}
      else
        {:error, reason} = error ->
          Logger.error("Failed to send character notification",
            reason: inspect(reason),
            category: :notification
          )

          error
      end
    end
  end

  defp format_notification(character_data) do
    try do
      formatted = NotificationFormatter.format_notification(character_data)
      {:ok, formatted}
    rescue
      e ->
        Logger.error("Failed to format character notification",
          error: inspect(e),
          category: :notification
        )

        {:error, {:format_error, e}}
    end
  end

  defp send_to_character_channel(embed) do
    channel_id = Config.discord_character_channel_id() || Config.discord_channel_id()
    DiscordNotifier.send_notification(:send_discord_embed_to_channel, [channel_id, embed])
    :ok
  end

  # ═══════════════════════════════════════════════════════════════════════════════
  # Status Notifications
  # ═══════════════════════════════════════════════════════════════════════════════

  defp send_status_notification(%Notification{data: status_data} = notification) do
    Logger.info("Sending status notification",
      title: Map.get(status_data, :title, "Status"),
      category: :system
    )

    case DiscordNotifier.send_notification(:send_discord_embed, [status_data]) do
      {:ok, :sent} ->
        {:ok, notification}

      {:error, reason} = error ->
        Logger.error("Failed to send status notification",
          reason: inspect(reason),
          category: :notification
        )

        error
    end
  end

  # ═══════════════════════════════════════════════════════════════════════════════
  # Private Helpers
  # ═══════════════════════════════════════════════════════════════════════════════
end
