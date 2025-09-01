defmodule WandererNotifier.DiscordNotifier do
  @moduledoc """
  Simplified Discord notification system.

  Handles all Discord notifications (kills, rally points, system/character tracking)
  using a single, unified approach with proper async handling and Nostrum integration.

  Key design principles:
  - Fire-and-forget: All public functions return immediately
  - Single Discord client: Uses Nostrum via NeoClient for all Discord API calls
  - No blocking: All Discord API calls run in separate Tasks
  - Built-in Discord features: Leverages Nostrum's rate limiting and reconnection handling
  """

  require Logger
  alias WandererNotifier.Shared.Config
  alias WandererNotifier.Domains.Notifications.Formatters.NotificationFormatter
  alias WandererNotifier.Domains.Notifications.Notifiers.Discord.NeoClient

  @doc """
  Send a kill notification asynchronously.
  Returns immediately, actual sending happens in background Task.
  """
  def send_kill_async(killmail) do
    Task.start(fn ->
      try do
        send_kill_notification(killmail)
        Logger.debug("Kill notification sent successfully", killmail_id: killmail.killmail_id)
      rescue
        error ->
          Logger.error("Kill notification failed",
            killmail_id: killmail.killmail_id,
            error: inspect(error),
            stacktrace: Exception.format_stacktrace(__STACKTRACE__)
          )

          # Emit telemetry for notification failures
          :telemetry.execute([:wanderer_notifier, :notification, :failed], %{count: 1}, %{
            type: :kill,
            killmail_id: killmail.killmail_id,
            reason: inspect(error)
          })
      end
    end)

    :ok
  end

  @doc """
  Send a rally point notification asynchronously.
  Returns immediately, actual sending happens in background Task.
  """
  def send_rally_point_async(rally_point) do
    Task.start(fn -> send_rally_point_notification(rally_point) end)
    :ok
  end

  @doc """
  Send a system notification asynchronously.
  Returns immediately, actual sending happens in background Task.
  """
  def send_system_async(system) do
    Task.start(fn -> send_system_notification(system) end)
    :ok
  end

  @doc """
  Send a character notification asynchronously.
  Returns immediately, actual sending happens in background Task.
  """
  def send_character_async(character) do
    Task.start(fn -> send_character_notification(character) end)
    :ok
  end

  @doc """
  Send a generic Discord embed asynchronously.
  Returns immediately, actual sending happens in background Task.
  """
  def send_embed_async(embed, opts \\ []) do
    Task.start(fn -> send_generic_embed(embed, opts) end)
    :ok
  end

  # ═══════════════════════════════════════════════════════════════════════════════
  # Private Implementation - All Discord API calls happen here
  # ═══════════════════════════════════════════════════════════════════════════════

  defp send_kill_notification(killmail) do
    Logger.debug("Processing kill notification async",
      killmail_id: Map.get(killmail, :killmail_id)
    )

    try do
      # Check if notifications are enabled
      if notifications_enabled?() and kill_notifications_enabled?() do
        # Format the notification
        case format_notification(killmail) do
          nil ->
            Logger.error("Failed to format kill notification")
            :error

          formatted_notification ->
            # Determine channel and send
            channel_id = determine_kill_channel(killmail)
            send_to_discord(formatted_notification, channel_id)
            Logger.debug("Kill notification sent successfully")
            :sent
        end
      else
        Logger.debug("Kill notifications disabled, skipping")
        :skipped
      end
    rescue
      e ->
        Logger.error("Exception in send_kill_notification: #{Exception.message(e)}")
        :error
    end
  end

  defp send_rally_point_notification(rally_point) do
    Logger.debug("Processing rally point notification async", rally_id: rally_point[:id])

    try do
      if notifications_enabled?() and rally_notifications_enabled?() do
        case format_notification(rally_point) do
          nil ->
            Logger.error("Failed to format rally point notification")
            :error

          formatted_notification ->
            channel_id = Config.discord_rally_channel_id() || Config.discord_channel_id()

            # Add @group mention if configured
            content = build_rally_content()
            formatted_with_content = Map.put(formatted_notification, :content, content)

            send_to_discord(formatted_with_content, channel_id)
            Logger.debug("Rally point notification sent successfully")
            :sent
        end
      else
        Logger.debug("Rally point notifications disabled, skipping")
        :skipped
      end
    rescue
      e ->
        Logger.error("Exception in send_rally_point_notification: #{Exception.message(e)}")
        :error
    end
  end

  defp send_system_notification(system) do
    Logger.debug("Processing system notification async",
      system_id: Map.get(system, :solar_system_id)
    )

    try do
      if notifications_enabled?() and system_notifications_enabled?() do
        case format_notification(system) do
          nil ->
            Logger.error("Failed to format system notification")
            :error

          formatted_notification ->
            channel_id = Config.discord_system_channel_id() || Config.discord_channel_id()
            send_to_discord(formatted_notification, channel_id)
            Logger.debug("System notification sent successfully")
            :sent
        end
      else
        Logger.debug("System notifications disabled, skipping")
        :skipped
      end
    rescue
      e ->
        Logger.error("Exception in send_system_notification: #{Exception.message(e)}")
        :error
    end
  end

  defp send_character_notification(character) do
    Logger.debug("Processing character notification async",
      character_id: Map.get(character, :character_id)
    )

    try do
      if notifications_enabled?() and character_notifications_enabled?() do
        case format_notification(character) do
          nil ->
            Logger.error("Failed to format character notification")
            :error

          formatted_notification ->
            channel_id = Config.discord_character_channel_id() || Config.discord_channel_id()
            send_to_discord(formatted_notification, channel_id)
            Logger.debug("Character notification sent successfully")
            :sent
        end
      else
        Logger.debug("Character notifications disabled, skipping")
        :skipped
      end
    rescue
      e ->
        Logger.error("Exception in send_character_notification: #{Exception.message(e)}")
        :error
    end
  end

  defp send_generic_embed(embed, opts) do
    Logger.debug("Processing generic embed notification async")

    try do
      if notifications_enabled?() do
        # Extract channel from opts or use default
        channel_id = Keyword.get(opts, :channel_id, Config.discord_channel_id())

        send_to_discord(embed, channel_id)
        Logger.debug("Generic embed sent successfully")
        :sent
      else
        Logger.debug("Notifications disabled, skipping generic embed")
        :skipped
      end
    rescue
      e ->
        Logger.error("Exception in send_generic_embed: #{Exception.message(e)}")
        :error
    end
  end

  # ═══════════════════════════════════════════════════════════════════════════════
  # Discord API Communication - Using Nostrum via NeoClient
  # ═══════════════════════════════════════════════════════════════════════════════

  defp send_to_discord(embed, channel_id) do
    # NeoClient already handles test mode internally
    # Extract content from embed if present
    embed_with_content =
      case Map.get(embed, :content) do
        nil ->
          embed

        "" ->
          embed

        content ->
          # NeoClient expects content at the top level for embeds with content
          Map.put(embed, :content, content)
      end

    case NeoClient.send_embed(embed_with_content, channel_id) do
      {:ok, :sent} ->
        Logger.debug("Discord notification sent successfully via Nostrum", channel: channel_id)
        :ok

      {:error, reason} ->
        Logger.error(
          "Discord notification failed via Nostrum",
          channel: channel_id,
          reason: inspect(reason)
        )

        {:error, reason}
    end
  end

  # ═══════════════════════════════════════════════════════════════════════════════
  # Helper Functions
  # ═══════════════════════════════════════════════════════════════════════════════

  defp format_notification(data) do
    try do
      NotificationFormatter.format_notification(data)
    rescue
      e ->
        Logger.error("Notification formatting failed: #{Exception.message(e)}")
        nil
    end
  end

  defp determine_kill_channel(killmail) do
    # Simple channel selection logic
    system_id = Map.get(killmail, :system_id)
    has_tracked_system = tracked_system?(system_id)
    has_tracked_character = tracked_character?(killmail)

    cond do
      has_tracked_character ->
        Config.discord_character_kill_channel_id() || Config.discord_channel_id()

      has_tracked_system ->
        Config.discord_system_kill_channel_id() || Config.discord_channel_id()

      true ->
        Config.discord_channel_id()
    end
  end

  defp build_rally_content do
    alias WandererNotifier.Domains.Notifications.Formatters.NotificationUtils

    case NotificationUtils.rally_mentions() do
      "" ->
        "Rally point created!"

      mentions ->
        "#{mentions} Rally point created!"
    end
  end

  # Simplified tracking checks - delegate to existing modules
  defp tracked_system?(system_id) do
    WandererNotifier.Domains.Notifications.Determiner.tracked_system_for_killmail?(system_id)
  end

  defp tracked_character?(killmail) do
    WandererNotifier.Domains.Notifications.Determiner.has_tracked_character?(killmail)
  end

  # Feature flags
  defp notifications_enabled?, do: Config.notifications_enabled?()
  defp kill_notifications_enabled?, do: Config.kill_notifications_enabled?()
  defp rally_notifications_enabled?, do: Config.rally_notifications_enabled?()
  defp system_notifications_enabled?, do: Config.system_notifications_enabled?()
  defp character_notifications_enabled?, do: Config.character_notifications_enabled?()
end
