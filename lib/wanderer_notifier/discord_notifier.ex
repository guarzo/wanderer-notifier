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
        # Determine all channels to send to (may be multiple if both system and character are tracked)
        channels = determine_kill_channels(killmail)

        Logger.info("Kill notification channel routing",
          killmail_id: Map.get(killmail, :killmail_id),
          channels: inspect(channels),
          category: :notifications
        )

        # Send to each channel
        Enum.each(channels, fn channel_id ->
          use_custom_name = system_kill_channel?(channel_id)

          # Format the notification with channel context
          case format_notification(killmail, use_custom_system_name: use_custom_name) do
            {:ok, formatted_notification} ->
              send_to_discord(formatted_notification, channel_id)
              Logger.debug("Kill notification sent to channel #{channel_id}")

            {:error, reason} ->
              Logger.error("Failed to format kill notification: #{inspect(reason)}")
          end
        end)

        :sent
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
          {:ok, formatted_notification} ->
            channel_id = Config.discord_rally_channel_id() || Config.discord_channel_id()

            # Add @group mention if configured
            content = build_rally_content()
            formatted_with_content = Map.put(formatted_notification, :content, content)

            send_to_discord(formatted_with_content, channel_id)
            Logger.debug("Rally point notification sent successfully")
            :sent

          {:error, reason} ->
            Logger.error("Failed to format rally point notification: #{inspect(reason)}")
            :error
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
          {:ok, formatted_notification} ->
            channel_id = Config.discord_system_channel_id() || Config.discord_channel_id()
            send_to_discord(formatted_notification, channel_id)
            Logger.debug("System notification sent successfully")
            :sent

          {:error, reason} ->
            Logger.error("Failed to format system notification: #{inspect(reason)}")
            :error
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
          {:ok, formatted_notification} ->
            channel_id = Config.discord_character_channel_id() || Config.discord_channel_id()
            send_to_discord(formatted_notification, channel_id)
            Logger.debug("Character notification sent successfully")
            :sent

          {:error, reason} ->
            Logger.error("Failed to format character notification: #{inspect(reason)}")
            :error
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

  defp format_notification(data, opts \\ []) do
    try do
      NotificationFormatter.format_notification(data, opts)
    rescue
      e ->
        Logger.error("Notification formatting failed: #{Exception.message(e)}")
        {:error, {:format_exception, Exception.message(e)}}
    end
  end

  defp system_kill_channel?(channel_id) do
    system_kill_channel = Config.discord_system_kill_channel_id()
    system_kill_channel != nil and channel_id == system_kill_channel
  end

  defp determine_kill_channels(killmail) do
    # Determine all channels to send to - may be multiple if both system and character are tracked
    system_id = Map.get(killmail, :system_id)
    has_tracked_system = tracked_system?(system_id)
    has_tracked_character = tracked_character?(killmail)

    default_channel = Config.discord_channel_id()
    system_channel = Config.discord_system_kill_channel_id()
    character_channel = Config.discord_character_kill_channel_id()

    # Check if corporation exclusion applies (only affects system kill channel)
    # Only compute when system-based routing is actually in use
    corp_excluded =
      if has_tracked_system and system_channel != nil do
        corporation_excluded?(killmail)
      else
        false
      end

    channels =
      []
      |> maybe_add_system_channel(
        has_tracked_system,
        corp_excluded,
        system_channel,
        default_channel
      )
      |> maybe_add_channel(has_tracked_character, character_channel, default_channel)

    # If no channels were added (neither system nor character tracked), use default
    if Enum.empty?(channels) do
      [default_channel]
    else
      # Return unique channels to avoid sending duplicates if both channels are the same
      Enum.uniq(channels)
    end
  end

  # For system channel, check corporation exclusion - only add if not excluded
  defp maybe_add_system_channel(channels, true, false, specific_channel, default_channel) do
    # System is tracked and corporation is NOT excluded - add the channel
    channel = specific_channel || default_channel
    [channel | channels]
  end

  defp maybe_add_system_channel(channels, true, true, specific_channel, _default_channel) do
    # System is tracked but corporation IS excluded
    # Only skip if there's a dedicated system kill channel configured
    if specific_channel != nil do
      Logger.info(
        "Kill notification excluded from system kill channel - corporation in exclusion list"
      )

      channels
    else
      # No dedicated system channel, so exclusion doesn't apply (falls back to default)
      # In this case, we don't add the channel here - let the default logic handle it
      channels
    end
  end

  defp maybe_add_system_channel(
         channels,
         false,
         _corp_excluded,
         _specific_channel,
         _default_channel
       ) do
    # System not tracked - don't add system channel
    channels
  end

  defp maybe_add_channel(channels, true, specific_channel, default_channel) do
    channel = specific_channel || default_channel
    [channel | channels]
  end

  defp maybe_add_channel(channels, false, _specific_channel, _default_channel) do
    channels
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

  # ═══════════════════════════════════════════════════════════════════════════════
  # Corporation Exclusion - Only applies to system kill channel
  # ═══════════════════════════════════════════════════════════════════════════════

  defp corporation_excluded?(killmail) do
    exclude_list = Config.corporation_exclude_list()

    if exclude_list == [] do
      false
    else
      # Convert to MapSet once for O(1) lookups
      exclude_set = MapSet.new(exclude_list)

      victim_corp_excluded?(killmail, exclude_set) or
        any_attacker_corp_excluded?(killmail, exclude_set)
    end
  end

  defp victim_corp_excluded?(killmail, exclude_set) do
    victim_corp_id = Map.get(killmail, :victim_corporation_id)

    case victim_corp_id do
      nil -> false
      id when is_integer(id) -> MapSet.member?(exclude_set, id)
      _ -> false
    end
  end

  defp any_attacker_corp_excluded?(killmail, exclude_set) do
    attackers = Map.get(killmail, :attackers, []) || []

    Enum.any?(attackers, fn attacker ->
      corp_id = Map.get(attacker, "corporation_id") || Map.get(attacker, :corporation_id)

      case corp_id do
        nil -> false
        id when is_integer(id) -> MapSet.member?(exclude_set, id)
        _ -> false
      end
    end)
  end
end
