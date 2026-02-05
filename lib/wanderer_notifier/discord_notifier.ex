defmodule WandererNotifier.DiscordNotifier do
  @moduledoc """
  Discord notification system.

  Handles all Discord notifications (kills, rally points, system/character tracking)
  with proper async handling and Nostrum integration.

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
  alias WandererNotifier.Infrastructure.Adapters.Discord.VoiceParticipants

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
      if notifications_enabled?() and kill_notifications_enabled?() do
        do_send_kill_notification(killmail)
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

  defp do_send_kill_notification(killmail) do
    killmail_id = Map.get(killmail, :killmail_id)
    system_id = Map.get(killmail, :system_id)

    # Check wormhole-only filter at the top level - blocks ALL kill notifications for non-wormhole systems
    if wormhole_only_excluded?(system_id) do
      Logger.debug(
        "Kill notification skipped - non-wormhole system with wormhole-only filter enabled",
        killmail_id: killmail_id,
        system_id: system_id
      )

      {:ok, :skipped}
    else
      channels = determine_kill_channels(killmail)

      Logger.info("Kill notification channel routing",
        killmail_id: killmail_id,
        channels: inspect(channels),
        category: :notifications
      )

      dispatch_to_channels(killmail, channels, killmail_id)
    end
  end

  defp dispatch_to_channels(_killmail, [], killmail_id) do
    Logger.debug("No channels to send to, kill notification skipped",
      killmail_id: killmail_id
    )

    {:ok, :skipped}
  end

  defp dispatch_to_channels(killmail, channels, killmail_id) do
    notifications_sent = send_to_channels(killmail, channels)
    record_notifications_sent(killmail_id, notifications_sent)
    {:ok, :sent}
  end

  defp send_to_channels(killmail, channels) do
    Enum.reduce(channels, 0, fn channel_id, sent_count ->
      case send_kill_to_channel(killmail, channel_id) do
        {:ok, :sent} -> sent_count + 1
        {:error, _reason} -> sent_count
      end
    end)
  end

  defp send_kill_to_channel(killmail, channel_id) do
    use_custom_name = system_kill_channel?(channel_id)
    killmail_id = Map.get(killmail, :killmail_id)

    case format_notification(killmail, use_custom_system_name: use_custom_name) do
      {:ok, formatted_notification} ->
        # Add voice mentions for system kill channel notifications
        {:ok, formatted_notification} =
          maybe_add_voice_mentions(formatted_notification, killmail, channel_id)

        case send_to_discord(formatted_notification, channel_id) do
          :ok ->
            Logger.debug("Kill notification sent to channel #{channel_id}")
            {:ok, :sent}

          {:error, reason} ->
            # Record the failed kill for health monitoring (error already logged in send_to_discord)
            record_failed_kill(killmail_id, reason)
            {:error, reason}
        end

      {:error, reason} ->
        Logger.error("Failed to format kill notification: #{inspect(reason)}")
        record_failed_kill(killmail_id, {:format_error, reason})
        {:error, {:format_error, reason}}
    end
  end

  defp record_failed_kill(nil, _reason), do: {:ok, :recorded}

  defp record_failed_kill(killmail_id, reason) do
    alias WandererNotifier.Domains.Notifications.Discord.ConnectionHealth

    # Use record_failed_killmail to add to the failed kills list without affecting counters
    # (NeoClient already records the failure/timeout for health metrics)
    case ConnectionHealth.record_failed_killmail(killmail_id, reason) do
      {:ok, _} ->
        {:ok, :recorded}

      {:error, err} ->
        Logger.error(
          "Failed to record failed killmail in ConnectionHealth",
          killmail_id: killmail_id,
          reason: inspect(reason),
          error: inspect(err)
        )

        {:error, err}
    end
  end

  defp record_notifications_sent(_killmail_id, 0), do: :ok

  defp record_notifications_sent(killmail_id, count) do
    WandererNotifier.Shared.Metrics.record_killmail_notified(killmail_id)

    Logger.info("Kill notification sent",
      killmail_id: killmail_id,
      channels_count: count
    )
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
        Logger.info("Discord notification sent successfully via Nostrum", channel: channel_id)
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
    ctx = build_channel_context(killmail)
    select_channels(ctx) |> Enum.uniq()
  end

  defp build_channel_context(killmail) do
    system_id = Map.get(killmail, :system_id)
    has_tracked_system = tracked_system?(system_id)

    %{
      killmail_id: Map.get(killmail, :killmail_id),
      involves_focused_corp: involves_focused_corporation?(killmail),
      has_tracked_system: has_tracked_system,
      wormhole_excluded: has_tracked_system && wormhole_excluded?(system_id),
      default_channel: Config.discord_channel_id(),
      system_channel: Config.discord_system_kill_channel_id(),
      character_channel: Config.discord_character_kill_channel_id()
    }
  end

  # Kill involves focused corporation -> character channel only
  defp select_channels(%{involves_focused_corp: true} = ctx) do
    Logger.info("Kill routed to character channel - focused corporation involved",
      killmail_id: ctx.killmail_id
    )

    [ctx.character_channel || ctx.default_channel]
  end

  # System tracked and not wormhole-excluded -> system channel
  defp select_channels(%{has_tracked_system: true, wormhole_excluded: false} = ctx) do
    [ctx.system_channel || ctx.default_channel]
  end

  # System tracked but wormhole-excluded -> no notification
  defp select_channels(%{has_tracked_system: true, wormhole_excluded: true}) do
    []
  end

  # Fallback -> default channel
  defp select_channels(ctx) do
    [ctx.default_channel]
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

  # Feature flags
  defp notifications_enabled?, do: Config.notifications_enabled?()
  defp kill_notifications_enabled?, do: Config.kill_notifications_enabled?()
  defp rally_notifications_enabled?, do: Config.rally_notifications_enabled?()
  defp system_notifications_enabled?, do: Config.system_notifications_enabled?()
  defp character_notifications_enabled?, do: Config.character_notifications_enabled?()

  # ═══════════════════════════════════════════════════════════════════════════════
  # System Kill Channel Exclusions
  # ═══════════════════════════════════════════════════════════════════════════════

  # Top-level check: should this kill be excluded entirely due to wormhole-only filter?
  # This blocks ALL kill notifications for non-wormhole systems when WORMHOLE_ONLY is enabled
  defp wormhole_only_excluded?(system_id) do
    Config.wormhole_only_kill_notifications?() and not wormhole_system?(system_id)
  end

  # Checks if system should be excluded from system kill channel due to wormhole-only filter
  # (Used for channel routing decisions - kept for backwards compatibility)
  defp wormhole_excluded?(system_id) do
    wormhole_only_excluded?(system_id)
  end

  # Detects wormhole systems by EVE system ID range
  # J-space (wormhole) systems: 31000000-31999999
  defp wormhole_system?(system_id) when is_integer(system_id) do
    system_id >= 31_000_000 and system_id <= 31_999_999
  end

  defp wormhole_system?(system_id) when is_binary(system_id) do
    case Integer.parse(system_id) do
      {id, ""} -> wormhole_system?(id)
      _ -> false
    end
  end

  defp wormhole_system?(_), do: false

  # ═══════════════════════════════════════════════════════════════════════════════
  # Corporation Kill Focus
  # ═══════════════════════════════════════════════════════════════════════════════

  # Checks if a kill involves any character from a focused corporation.
  # When CORPORATION_KILL_FOCUS is configured, kills involving these corps:
  # - Are routed to the character kill channel
  # - Are excluded from the system kill channel
  defp involves_focused_corporation?(killmail) do
    focus_corps = Config.corporation_kill_focus()
    do_involves_focused_corporation?(killmail, focus_corps)
  end

  defp do_involves_focused_corporation?(_killmail, []), do: false

  defp do_involves_focused_corporation?(killmail, focus_corps) do
    focus_set = MapSet.new(focus_corps)

    victim_in_focus = victim_in_focused_corp?(killmail, focus_set)
    attacker_in_focus = any_attacker_in_focused_corp?(killmail, focus_set)

    victim_in_focus or attacker_in_focus
  end

  defp victim_in_focused_corp?(killmail, focus_set) do
    victim_corp_id = Map.get(killmail, :victim_corporation_id)
    corp_in_set?(victim_corp_id, focus_set)
  end

  defp any_attacker_in_focused_corp?(killmail, focus_set) do
    attackers = Map.get(killmail, :attackers, []) || []

    Enum.any?(attackers, fn attacker ->
      corp_id = Map.get(attacker, "corporation_id") || Map.get(attacker, :corporation_id)
      corp_in_set?(corp_id, focus_set)
    end)
  end

  defp corp_in_set?(corp_id, set) do
    case normalize_corp_id(corp_id) do
      nil -> false
      id -> MapSet.member?(set, id)
    end
  end

  # Normalizes corporation ID to integer for consistent comparison
  defp normalize_corp_id(nil), do: nil
  defp normalize_corp_id(id) when is_integer(id), do: id

  defp normalize_corp_id(id) when is_binary(id) do
    case Integer.parse(id) do
      {num, ""} -> num
      _ -> nil
    end
  end

  defp normalize_corp_id(_), do: nil

  # ═══════════════════════════════════════════════════════════════════════════════
  # Voice Channel Mentions
  # ═══════════════════════════════════════════════════════════════════════════════

  defp maybe_add_voice_mentions(notification, killmail, channel_id) do
    case {voice_pings_enabled?(), system_kill_channel?(channel_id), system_kill?(killmail)} do
      {true, true, true} ->
        prepend_voice_mentions(notification)

      _ ->
        {:ok, notification}
    end
  end

  @spec voice_pings_enabled?() :: boolean()
  defp voice_pings_enabled?, do: Config.voice_participant_notifications_enabled?()

  # Returns true if the kill is in a tracked system (for voice notification purposes)
  @spec system_kill?(map()) :: boolean()
  defp system_kill?(killmail) do
    case Map.get(killmail, :system_id) do
      nil -> false
      system_id -> tracked_system?(system_id)
    end
  end

  defp prepend_voice_mentions(notification) do
    case VoiceParticipants.get_active_voice_mentions() do
      [] -> {:ok, notification}
      mentions -> prepend_mentions(notification, mentions)
    end
  end

  defp prepend_mentions(notification, mentions) do
    mention_string = Enum.join(mentions, " ")
    existing_content = Map.get(notification, :content, "")
    {:ok, Map.put(notification, :content, "#{mention_string} #{existing_content}")}
  end
end
