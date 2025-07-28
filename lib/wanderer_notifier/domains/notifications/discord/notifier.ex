defmodule WandererNotifier.Domains.Notifications.Notifiers.Discord.Notifier do
  @moduledoc """
  Clean Discord notification service without test logic or unused parameters.
  """

  require Logger
  alias WandererNotifier.Application.Services.Stats
  alias WandererNotifier.Domains.Killmail.{Killmail, Enrichment}

  alias WandererNotifier.Domains.Notifications.Notifiers.Discord.{
    ComponentBuilder,
    FeatureFlags,
    NeoClient
  }

  alias WandererNotifier.Domains.Notifications.Formatters.{NotificationFormatter, PlainText}
  alias WandererNotifier.Domains.Notifications.LicenseLimiter
  alias WandererNotifier.Domains.Notifications.Determiner
  alias WandererNotifier.Shared.Config
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

  def send_message(_) do
    {:error, :invalid_message_type}
  end

  @doc """
  Send an embed to Discord.
  """
  def send_embed(title, description, url \\ nil, color \\ @default_embed_color) do
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

  # ═══════════════════════════════════════════════════════════════════════════════
  # Kill Notifications
  # ═══════════════════════════════════════════════════════════════════════════════

  @doc """
  Send a kill notification.
  """
  def send_kill_notification(kill_data) do
    if LicenseLimiter.should_send_rich?(:killmail) do
      killmail = ensure_killmail_struct(kill_data)
      send_rich_kill_notification(killmail)
      LicenseLimiter.increment(:killmail)
    else
      channel_id = Config.discord_channel_id()
      send_simple_kill_notification(kill_data, channel_id)
    end
  rescue
    e ->
      Logger.error("Exception in send_kill_notification",
        error: Exception.message(e),
        category: :processor,
        stacktrace: Exception.format_stacktrace(__STACKTRACE__)
      )

      {:error, e}
  end

  @doc """
  Send a kill notification to a specific channel.
  """
  def send_kill_notification_to_channel(kill_data, channel_id) do
    killmail = ensure_killmail_struct(kill_data)

    # Enrich with system name if needed
    enriched_killmail = enrich_with_system_name(killmail)

    # Format the notification
    notification = NotificationFormatter.format_notification(enriched_killmail)

    # Check if this is a system kill and add voice mentions
    notification = maybe_add_voice_mentions(notification, killmail, channel_id)

    # Send to channel
    NeoClient.send_embed(notification, channel_id)
  rescue
    e ->
      Logger.error("Exception in send_kill_notification_to_channel",
        error: Exception.message(e),
        category: :api,
        stacktrace: Exception.format_stacktrace(__STACKTRACE__)
      )

      {:error, {:exception, Exception.message(e)}}
  end

  # ═══════════════════════════════════════════════════════════════════════════════
  # Character Notifications
  # ═══════════════════════════════════════════════════════════════════════════════

  @doc """
  Send a character tracking notification.
  """
  def send_new_tracked_character_notification(character) do
    if LicenseLimiter.should_send_rich?(:character) do
      notification = NotificationFormatter.format_notification(character)
      channel_id = Config.discord_character_channel_id() || Config.discord_channel_id()
      NeoClient.send_embed(notification, channel_id)
      LicenseLimiter.increment(:character)
    else
      message = PlainText.format_plain_text(character)
      NeoClient.send_message(message)
    end

    Stats.increment(:characters)

    Logger.info("Character #{character.name} (#{character.character_id}) notified",
      category: :processor
    )

    {:ok, :sent}
  rescue
    e ->
      Logger.error("Exception in send_new_tracked_character_notification",
        error: Exception.message(e),
        category: :processor,
        stacktrace: Exception.format_stacktrace(__STACKTRACE__)
      )

      {:error, e}
  end

  # ═══════════════════════════════════════════════════════════════════════════════
  # System Notifications
  # ═══════════════════════════════════════════════════════════════════════════════

  @doc """
  Send a system tracking notification.
  """
  def send_new_system_notification(system) do
    if LicenseLimiter.should_send_rich?(:system) do
      notification = NotificationFormatter.format_notification(system)
      channel_id = Config.discord_system_channel_id() || Config.discord_channel_id()
      NeoClient.send_embed(notification, channel_id)
      LicenseLimiter.increment(:system)
    else
      message = PlainText.format_plain_text(system)
      NeoClient.send_message(message)
    end

    Stats.increment(:systems)

    Logger.info("System #{system.name} (#{system.solar_system_id}) notified",
      category: :processor
    )

    {:ok, :sent}
  rescue
    e ->
      Logger.error("Exception in send_new_system_notification",
        error: Exception.message(e),
        category: :processor,
        stacktrace: Exception.format_stacktrace(__STACKTRACE__)
      )

      {:error, e}
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
    notification = NotificationFormatter.format_notification(enriched_killmail)

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

    if FeatureFlags.components_enabled?() and Map.has_key?(notification, :components) do
      NeoClient.send_message_with_components(notification, notification.components, channel_id)
    else
      NeoClient.send_embed(notification, channel_id)
    end
  end

  defp send_simple_kill_notification(kill_data, channel_id) do
    message = PlainText.format_plain_text(kill_data)
    NeoClient.send_message(message, channel_id)
  end

  defp enrich_with_system_name(%Killmail{} = killmail) do
    system_id = get_system_id_from_killmail(killmail)

    case system_id do
      id when is_integer(id) ->
        system_name = Enrichment.get_system_name(id)
        %{killmail | system_name: system_name}

      _ ->
        killmail
    end
  end

  defp get_system_id_from_killmail(%Killmail{system_id: system_id}) when is_integer(system_id) do
    system_id
  end

  defp get_system_id_from_killmail(_), do: nil

  defp maybe_add_voice_mentions(notification, killmail, channel_id) do
    # Check if this is being sent to the system kill channel
    system_kill_channel = Config.discord_system_kill_channel_id()

    # Check if killmail is for a tracked system (not character)
    is_system_kill =
      channel_id == system_kill_channel and
        Determiner.tracked_system_for_killmail?(killmail.system_id) and
        not Determiner.has_tracked_character?(killmail)

    if is_system_kill do
      # Get voice channel mentions
      mentions = VoiceParticipants.get_active_voice_mentions()

      case mentions do
        [] ->
          notification

        mentions_list ->
          # Add mentions to the content field
          mention_string = Enum.join(mentions_list, " ")
          existing_content = Map.get(notification, :content, "")

          # Prepend mentions to content
          Map.put(notification, :content, "#{mention_string} #{existing_content}")
      end
    else
      notification
    end
  end
end
