defmodule WandererNotifier.Domains.Notifications.Notifiers.Discord.Notifier do
  @moduledoc """
  Discord notification service - thin orchestrator for sending notifications.

  This module coordinates notification sending by delegating to:
  - `LicenseLimiter` for license-based throttling
  - `NotificationFormatter` for embed/text formatting
  - `NeoClient` for Discord API calls
  - `EnrichmentHelper` for data enrichment
  - `ChannelResolver` for channel routing
  """

  require Logger
  alias WandererNotifier.Domains.Killmail.Killmail

  alias WandererNotifier.Domains.Notifications.Notifiers.Discord.{
    ComponentBuilder,
    FeatureFlags,
    NeoClient
  }

  alias WandererNotifier.Domains.Notifications.Discord.{
    ChannelResolver,
    EnrichmentHelper
  }

  alias WandererNotifier.Domains.Notifications.Formatters.{
    NotificationFormatter,
    NotificationUtils
  }

  alias WandererNotifier.Domains.Notifications.LicenseLimiter
  alias WandererNotifier.Shared.Config
  alias WandererNotifier.Shared.Utils.ErrorHandler

  # Default embed colors
  @default_embed_color 0x3498DB

  # ═══════════════════════════════════════════════════════════════════════════════
  # Public API
  # ═══════════════════════════════════════════════════════════════════════════════

  @doc """
  Send a message to Discord.
  """
  def send_message(message) when is_binary(message) do
    NeoClient.send_message(message)
  end

  def send_message(embed) when is_map(embed) do
    NeoClient.send_embed(embed)
  end

  def send_message(message, channel_id) when is_binary(message) do
    NeoClient.send_message(message, channel_id)
  end

  def send_message(embed, channel_id) when is_map(embed) do
    NeoClient.send_embed(embed, channel_id)
  end

  @doc """
  Send an embed to Discord.
  """
  def send_embed(title, description, url \\ nil, color \\ @default_embed_color)

  def send_embed(title, description, url, color) do
    embed = %{
      "title" => title,
      "description" => description,
      "color" => color
    }

    embed = if url, do: Map.put(embed, "url", url), else: embed

    NeoClient.send_embed(embed)
  end

  @doc """
  Send a file to Discord.
  """
  def send_file(filename, file_data, title \\ nil, description \\ nil) do
    NeoClient.send_file(filename, file_data, title, description)
  end

  @doc """
  Send an image embed to Discord.
  """
  def send_image_embed(title, description, image_url, color \\ @default_embed_color) do
    embed = %{
      "title" => title,
      "description" => description,
      "color" => color,
      "image" => %{"url" => image_url}
    }

    NeoClient.send_embed(embed)
  end

  def send_image_embed(title, description, image_url, channel_id, color) do
    embed = %{
      "title" => title,
      "description" => description,
      "color" => color,
      "image" => %{"url" => image_url}
    }

    NeoClient.send_embed(embed, channel_id)
  end

  # ═══════════════════════════════════════════════════════════════════════════════
  # Kill Notifications
  # ═══════════════════════════════════════════════════════════════════════════════

  @doc """
  Send a kill notification.
  """
  def send_kill_notification(kill_data) do
    ErrorHandler.safe_execute(
      fn ->
        if LicenseLimiter.should_send_rich?(:killmail) do
          killmail = ensure_killmail_struct(kill_data)
          send_rich_kill_notification(killmail)
          LicenseLimiter.increment(:killmail)
        else
          channel_id = Config.discord_channel_id()
          send_simple_kill_notification(kill_data, channel_id)
        end
      end,
      context: %{operation: :send_kill_notification, category: :processor}
    )
  end

  # ═══════════════════════════════════════════════════════════════════════════════
  # Character Notifications
  # ═══════════════════════════════════════════════════════════════════════════════

  @doc """
  Send a character tracking notification.
  """
  def send_new_tracked_character_notification(character) do
    ErrorHandler.safe_execute(
      fn ->
        send_character_notification_impl(character)

        WandererNotifier.Shared.Metrics.increment(:characters)

        Logger.info("Character #{character.name} (#{character.character_id}) notified",
          category: :processor
        )

        {:ok, :sent}
      end,
      context: %{
        operation: :send_new_tracked_character_notification,
        character_id: character.character_id,
        category: :processor
      }
    )
  end

  defp send_character_notification_impl(character) do
    rich? = LicenseLimiter.should_send_rich?(:character)
    send_character_notification_impl(character, rich?)
  end

  defp send_character_notification_impl(character, true) do
    send_rich_character_notification(character)
  end

  defp send_character_notification_impl(character, false) do
    message = NotificationFormatter.format_plain_text(character)
    NeoClient.send_message(message)
  end

  defp send_rich_character_notification(character) do
    case NotificationFormatter.format_notification(character) do
      {:ok, notification} ->
        channel_id = ChannelResolver.resolve_channel(:character)

        case NeoClient.send_embed(notification, channel_id) do
          {:ok, _} = success ->
            LicenseLimiter.increment(:character)
            success

          {:error, reason} = error ->
            Logger.error("Failed to send character notification to Discord: #{inspect(reason)}")
            error
        end

      {:error, reason} ->
        Logger.error("Failed to format character notification: #{inspect(reason)}")
        {:error, reason}
    end
  end

  # ═══════════════════════════════════════════════════════════════════════════════
  # System Notifications
  # ═══════════════════════════════════════════════════════════════════════════════

  @doc """
  Send a system tracking notification.
  """
  def send_new_system_notification(system) do
    ErrorHandler.safe_execute(
      fn ->
        send_system_notification_impl(system)

        WandererNotifier.Shared.Metrics.increment(:systems)

        Logger.info("System #{system.name} (#{system.solar_system_id}) notified",
          category: :processor
        )

        {:ok, :sent}
      end,
      context: %{
        operation: :send_new_system_notification,
        system_id: system.solar_system_id,
        category: :processor
      }
    )
  end

  defp send_system_notification_impl(system) do
    rich? = LicenseLimiter.should_send_rich?(:system)
    send_system_notification_impl(system, rich?)
  end

  defp send_system_notification_impl(system, true) do
    send_rich_system_notification(system)
  end

  defp send_system_notification_impl(system, false) do
    message = NotificationFormatter.format_plain_text(system)
    NeoClient.send_message(message)
  end

  defp send_rich_system_notification(system) do
    case NotificationFormatter.format_notification(system) do
      {:ok, notification} ->
        channel_id = ChannelResolver.resolve_channel(:system)

        case NeoClient.send_embed(notification, channel_id) do
          {:ok, _} = success ->
            LicenseLimiter.increment(:system)
            success

          {:error, reason} = error ->
            Logger.error("Failed to send system notification to Discord: #{inspect(reason)}")
            error
        end

      {:error, reason} ->
        Logger.error("Failed to format system notification: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Send a rally point notification.
  """
  def send_rally_point_notification(rally_point) do
    rally_id = rally_point[:id]

    ErrorHandler.safe_execute(
      fn -> do_send_rally_notification(rally_point, rally_id) end,
      fallback: fn error ->
        Logger.error("Exception in rally notification",
          rally_id: rally_id,
          error: Exception.message(error),
          category: :rally
        )

        {:error, error}
      end
    )
  end

  defp do_send_rally_notification(rally_point, rally_id) do
    Logger.debug("Starting rally point notification", rally_id: rally_id, category: :rally)

    enriched_rally_point = EnrichmentHelper.enrich_rally_with_system_name(rally_point)

    with {:ok, notification} <- NotificationFormatter.format_notification(enriched_rally_point),
         {:ok, :sent} <- send_rally_embed(notification) do
      log_rally_success(enriched_rally_point, rally_id)
      {:ok, :sent}
    else
      {:error, reason} ->
        Logger.error("Failed to send rally notification",
          rally_id: rally_id,
          reason: inspect(reason),
          category: :rally
        )

        {:error, reason}
    end
  end

  defp send_rally_embed(notification) do
    notification
    |> add_rally_mentions()
    |> NeoClient.send_embed(Config.discord_rally_channel_id())
  end

  defp add_rally_mentions(notification) do
    content =
      case NotificationUtils.rally_mentions() do
        "" -> "Rally point created!"
        mentions -> "#{mentions} Rally point created!"
      end

    Map.put(notification, :content, content)
  end

  defp log_rally_success(rally_point, rally_id) do
    Logger.info("Rally notification sent",
      rally_id: rally_id,
      system: rally_point[:system_name],
      character: rally_point[:character_name],
      category: :rally
    )
  end

  # ═══════════════════════════════════════════════════════════════════════════════
  # Generic Notification Handler
  # ═══════════════════════════════════════════════════════════════════════════════

  @doc """
  Send a notification based on type and data.
  """
  def send_notification(:send_discord_embed, [embed]) do
    NeoClient.send_embed(embed, nil)
    {:ok, :sent}
  end

  def send_notification(:send_discord_embed_to_channel, [channel_id, embed]) do
    NeoClient.send_embed(embed, channel_id)
    {:ok, :sent}
  end

  def send_notification(:send_message, [message]) do
    send_message(message)
    {:ok, :sent}
  end

  def send_notification(:send_new_tracked_character_notification, [character]) do
    send_new_tracked_character_notification(character)
  end

  def send_notification(:send_rally_point_notification, [rally_point]) do
    send_rally_point_notification(rally_point)
  end

  def send_notification(type, _data) do
    Logger.warning("Unknown notification type", type: type, category: :processor)
    {:error, :unknown_notification_type}
  end

  # ═══════════════════════════════════════════════════════════════════════════════
  # Private Helpers
  # ═══════════════════════════════════════════════════════════════════════════════

  defp ensure_killmail_struct(kill_data) when is_struct(kill_data, Killmail) do
    kill_data
  end

  defp ensure_killmail_struct(%{__struct__: _} = kill_data) do
    struct(Killmail, Map.from_struct(kill_data))
  end

  defp ensure_killmail_struct(kill_data) when is_map(kill_data) do
    struct(Killmail, kill_data)
  end

  defp send_rich_kill_notification(killmail) do
    enriched_killmail = EnrichmentHelper.enrich_killmail_with_system_name(killmail)

    case NotificationFormatter.format_notification(enriched_killmail) do
      {:ok, notification} ->
        notification = maybe_add_components(notification, killmail.killmail_id)
        channel_id = ChannelResolver.resolve_channel(:kill)

        result =
          if FeatureFlags.components_enabled?() and Map.has_key?(notification, :components) do
            NeoClient.send_message_with_components(
              notification,
              notification.components,
              channel_id
            )
          else
            NeoClient.send_embed(notification, channel_id)
          end

        case result do
          {:ok, :sent} -> :ok
          {:error, reason} -> {:error, reason}
        end

      {:error, reason} ->
        Logger.error("Failed to format kill notification: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp maybe_add_components(notification, killmail_id) do
    if Config.features()[:discord_components] do
      Map.put(notification, :components, [
        ComponentBuilder.kill_action_row(killmail_id)
      ])
    else
      notification
    end
  end

  defp send_simple_kill_notification(kill_data, channel_id) do
    message = NotificationFormatter.format_plain_text(kill_data)

    case NeoClient.send_message(message, channel_id) do
      {:ok, :sent} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end
end
