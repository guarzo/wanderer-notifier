defmodule WandererNotifier.Domains.Notifications.Notifiers.Discord.Notifier do
  @moduledoc """
  Clean Discord notification service without test logic or unused parameters.
  """

  require Logger
  alias WandererNotifier.Domains.Killmail.{Killmail, Enrichment}

  alias WandererNotifier.Domains.Notifications.Notifiers.Discord.{
    ComponentBuilder,
    FeatureFlags,
    NeoClient
  }

  alias WandererNotifier.Domains.Notifications.Formatters.NotificationFormatter
  alias WandererNotifier.Domains.Notifications.LicenseLimiter
  alias WandererNotifier.Domains.Notifications.Determiner
  alias WandererNotifier.Shared.Config
  alias WandererNotifier.Shared.Utils.ErrorHandler
  alias WandererNotifier.Infrastructure.Adapters.Discord.VoiceParticipants

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

  @doc """
  Send a kill notification to a specific channel.
  """
  def send_kill_notification_to_channel(kill_data, channel_id) do
    ErrorHandler.safe_execute(
      fn ->
        killmail = ensure_killmail_struct(kill_data)

        # Enrich with system name if needed
        enriched_killmail = enrich_with_system_name(killmail)

        # Format and send the notification
        case NotificationFormatter.format_notification(enriched_killmail) do
          {:ok, notification} ->
            notification = maybe_add_voice_mentions(notification, killmail, channel_id)
            send_kill_embed_to_channel(notification, channel_id, killmail.killmail_id)

          {:error, reason} ->
            Logger.error("Failed to format kill notification",
              category: :discord_notify,
              channel_id: channel_id,
              killmail_id: killmail.killmail_id,
              reason: inspect(reason)
            )

            {:error, reason}
        end
      end,
      context: %{
        operation: :send_kill_notification_to_channel,
        channel_id: channel_id,
        category: :api
      }
    )
  end

  defp send_kill_embed_to_channel(notification, channel_id, killmail_id) do
    case NeoClient.send_embed(notification, channel_id) do
      {:ok, _} ->
        {:ok, :sent}

      {:error, reason} ->
        Logger.error("Failed to send kill notification to Discord",
          category: :discord_notify,
          channel_id: channel_id,
          killmail_id: killmail_id,
          reason: inspect(reason)
        )

        {:error, reason}
    end
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
        channel_id = Config.discord_character_channel_id() || Config.discord_channel_id()

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
        channel_id = Config.discord_system_channel_id() || Config.discord_channel_id()

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
    start_time = System.monotonic_time(:millisecond)
    rally_id = rally_point[:id]

    ErrorHandler.safe_execute(
      fn ->
        log_rally_start(rally_id)

        # Enrich with custom system name if available
        enriched_rally_point = enrich_rally_with_system_name(rally_point)

        case format_rally_notification(enriched_rally_point, rally_id, start_time) do
          {:ok, notification} ->
            channel_id = get_rally_channel_id(rally_id, start_time)
            notification_with_content = add_rally_content(notification, enriched_rally_point)

            send_rally_to_discord(
              notification_with_content,
              channel_id,
              enriched_rally_point,
              rally_id,
              start_time
            )

          {:error, _reason} = error ->
            error
        end
      end,
      fallback: fn error ->
        handle_rally_exception(error, rally_id, start_time)
      end
    )
  end

  defp log_rally_start(rally_id) do
    Logger.info("[RALLY_TIMING] Starting send_rally_point_notification",
      rally_id: rally_id,
      category: :rally
    )
  end

  defp format_rally_notification(rally_point, rally_id, start_time) do
    Logger.info("[RALLY_TIMING] Calling NotificationFormatter.format_notification",
      rally_id: rally_id,
      elapsed_ms: System.monotonic_time(:millisecond) - start_time,
      category: :rally
    )

    case NotificationFormatter.format_notification(rally_point) do
      {:ok, notification} ->
        Logger.info(
          "[RALLY_TIMING] Formatting completed after #{System.monotonic_time(:millisecond) - start_time}ms",
          rally_id: rally_id,
          category: :rally
        )

        {:ok, notification}

      {:error, reason} ->
        elapsed_ms = System.monotonic_time(:millisecond) - start_time

        Logger.error("[RALLY_TIMING] Formatting failed after #{elapsed_ms}ms: #{inspect(reason)}",
          rally_id: rally_id,
          elapsed_ms: elapsed_ms,
          category: :rally
        )

        {:error, {:formatting_failed, reason}}
    end
  end

  defp get_rally_channel_id(rally_id, start_time) do
    channel_id = Config.discord_rally_channel_id()

    Logger.info(
      "[RALLY_TIMING] Retrieved channel_id: #{inspect(channel_id)} after #{System.monotonic_time(:millisecond) - start_time}ms",
      rally_id: rally_id,
      category: :rally
    )

    channel_id
  end

  defp add_rally_content(notification, rally_point) do
    content = build_rally_content(rally_point)
    Map.put(notification, :content, content)
  end

  defp send_rally_to_discord(notification, channel_id, rally_point, rally_id, start_time) do
    Logger.info("[RALLY_TIMING] Calling NeoClient.send_embed",
      rally_id: rally_id,
      channel_id: channel_id,
      elapsed_ms: System.monotonic_time(:millisecond) - start_time,
      category: :rally
    )

    case NeoClient.send_embed(notification, channel_id) do
      {:ok, :sent} ->
        log_rally_success(rally_point, rally_id, start_time)
        {:ok, :sent}

      {:error, reason} ->
        log_rally_error(reason, rally_id, start_time)
        {:error, reason}
    end
  end

  defp log_rally_success(rally_point, rally_id, start_time) do
    total_time = System.monotonic_time(:millisecond) - start_time

    Logger.info(
      "[RALLY_TIMING] NeoClient.send_embed returned success after #{total_time}ms total",
      rally_id: rally_id,
      system: rally_point.system_name,
      character: rally_point.character_name,
      category: :rally
    )
  end

  defp log_rally_error(reason, rally_id, start_time) do
    total_time = System.monotonic_time(:millisecond) - start_time

    Logger.error("[RALLY_TIMING] NeoClient.send_embed returned error after #{total_time}ms total",
      rally_id: rally_id,
      reason: inspect(reason),
      category: :rally
    )
  end

  defp handle_rally_exception(e, rally_id, start_time) do
    total_time = System.monotonic_time(:millisecond) - start_time

    Logger.error(
      "[RALLY_TIMING] Exception in send_rally_point_notification after #{total_time}ms",
      rally_id: rally_id,
      error: Exception.message(e),
      category: :rally
    )

    {:error, e}
  end

  defp build_rally_content(_rally_point) do
    alias WandererNotifier.Domains.Notifications.Formatters.NotificationUtils

    case NotificationUtils.rally_mentions() do
      "" ->
        "Rally point created!"

      mentions ->
        "#{mentions} Rally point created!"
    end
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

  defp ensure_killmail_struct(kill_data) do
    if is_struct(kill_data, Killmail) do
      kill_data
    else
      struct(Killmail, Map.from_struct(kill_data))
    end
  end

  defp send_rich_kill_notification(killmail) do
    enriched_killmail = enrich_with_system_name(killmail)

    case NotificationFormatter.format_notification(enriched_killmail) do
      {:ok, notification} ->
        # Add components if feature is enabled
        notification =
          if Config.features()[:discord_components] do
            Map.put(notification, :components, [
              ComponentBuilder.kill_action_row(killmail.killmail_id)
            ])
          else
            notification
          end

        channel_id = Config.discord_channel_id()

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

  defp send_simple_kill_notification(kill_data, channel_id) do
    message = NotificationFormatter.format_plain_text(kill_data)
    result = NeoClient.send_message(message, channel_id)

    case result do
      {:ok, :sent} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp enrich_with_system_name(%Killmail{} = killmail) do
    system_id = get_system_id_from_killmail(killmail)

    case system_id do
      id when is_integer(id) ->
        # First check if it's a tracked system with a custom name
        system_name = get_tracked_system_name(id) || Enrichment.get_system_name(id)
        %{killmail | system_name: system_name}

      _ ->
        killmail
    end
  end

  defp get_system_id_from_killmail(%Killmail{system_id: system_id}) when is_integer(system_id) do
    system_id
  end

  defp get_system_id_from_killmail(_), do: nil

  defp get_tracked_system_name(system_id) when is_integer(system_id) do
    # Get the tracked system from map cache to get custom name
    # Convert integer to string as get_system expects String.t()
    system_id
    |> Integer.to_string()
    |> WandererNotifier.Domains.Tracking.Entities.System.get_system()
    |> case do
      {:ok, %{name: name}} when is_binary(name) -> name
      _ -> nil
    end
  end

  defp enrich_rally_with_system_name(rally_point) do
    # Convert struct to map first to ensure Map.put/3 works
    rally_map =
      if is_struct(rally_point) do
        Map.from_struct(rally_point)
      else
        rally_point
      end

    system_id = rally_map[:system_id]

    case system_id do
      id when is_integer(id) ->
        # Check if tracked system has a custom name
        case get_tracked_system_name(id) do
          nil -> rally_map
          custom_name -> Map.put(rally_map, :system_name, custom_name)
        end

      _ ->
        rally_map
    end
  end

  defp debug_logging_enabled? do
    Config.feature_enabled?(:discord_debug_logging) or Logger.level() == :debug
  end

  defp maybe_add_voice_mentions(notification, killmail, channel_id) do
    if should_add_voice_mentions?(killmail, channel_id) do
      add_voice_mentions_to_notification(notification)
    else
      log_voice_ping_debug("[Voice Ping Debug] Not a system kill or voice pings disabled")
      notification
    end
  end

  defp should_add_voice_mentions?(killmail, channel_id) do
    system_kill_channel = Config.discord_system_kill_channel_id()

    log_voice_ping_debug(
      "[Voice Ping Debug] Channel comparison - channel_id: #{inspect(channel_id)}, " <>
        "system_kill_channel: #{inspect(system_kill_channel)}, channels_match: #{channel_id == system_kill_channel}"
    )

    is_system_kill = system_kill?(killmail, channel_id, system_kill_channel)
    voice_pings_enabled = Config.voice_participant_notifications_enabled?()

    log_voice_ping_debug(
      "[Voice Ping Debug] System kill determination - is_system_kill: #{is_system_kill}, " <>
        "voice_pings_enabled: #{voice_pings_enabled}"
    )

    is_system_kill and voice_pings_enabled
  end

  defp system_kill?(killmail, channel_id, system_kill_channel) do
    system_tracked = Determiner.tracked_system_for_killmail?(killmail.system_id)
    has_tracked_char = Determiner.has_tracked_character?(killmail)

    log_voice_ping_debug(
      "[Voice Ping Debug] Kill tracking status - system_id: #{killmail.system_id}, " <>
        "system_tracked: #{system_tracked}, has_tracked_character: #{has_tracked_char}"
    )

    channel_id == system_kill_channel and system_tracked and not has_tracked_char
  end

  defp add_voice_mentions_to_notification(notification) do
    mentions = VoiceParticipants.get_active_voice_mentions()

    log_voice_ping_debug(
      "[Voice Ping Debug] Voice mentions retrieved - count: #{length(mentions)}, mentions: #{inspect(mentions)}"
    )

    case mentions do
      [] ->
        log_voice_ping_debug("[Voice Ping Debug] No voice users found")
        notification

      mentions_list ->
        append_mentions_to_notification(notification, mentions_list)
    end
  end

  defp append_mentions_to_notification(notification, mentions_list) do
    mention_string = Enum.join(mentions_list, " ")
    existing_content = Map.get(notification, :content, "")

    log_voice_ping_debug(
      "[Voice Ping Debug] Adding mentions - mention_string: #{mention_string}, " <>
        "existing_content: #{existing_content}"
    )

    Map.put(notification, :content, "#{mention_string} #{existing_content}")
  end

  defp log_voice_ping_debug(message) do
    if debug_logging_enabled?(), do: Logger.debug(message)
  end
end
