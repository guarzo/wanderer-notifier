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
    channels = determine_kill_channels(killmail)

    Logger.info("Kill notification channel routing",
      killmail_id: killmail_id,
      channels: inspect(channels),
      category: :notifications
    )

    notifications_sent = send_to_channels(killmail, channels)
    record_notifications_sent(killmail_id, notifications_sent)

    :sent
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
      {:ok, _} -> {:ok, :recorded}
      {:error, err} -> {:error, err}
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

    # Check if wormhole-only filter applies (only affects system kill channel)
    # Only compute when system-based routing is actually in use
    wormhole_excluded =
      if has_tracked_system and system_channel != nil do
        wormhole_excluded?(system_id)
      else
        false
      end

    channels =
      []
      |> maybe_add_system_channel(
        has_tracked_system,
        corp_excluded or wormhole_excluded,
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
  # System Kill Channel Exclusions
  # ═══════════════════════════════════════════════════════════════════════════════

  # Checks if system should be excluded from system kill channel due to wormhole-only filter
  defp wormhole_excluded?(system_id) do
    wormhole_only = Config.wormhole_only_kill_notifications?()

    if wormhole_only do
      # Use system ID range to reliably detect wormhole systems
      # J-space (wormhole) systems have IDs in range 31000000-31999999
      is_wormhole = wormhole_system?(system_id)

      if not is_wormhole do
        Logger.info(
          "Kill notification excluded from system kill channel - non-wormhole system",
          system_id: system_id,
          wormhole_only: wormhole_only
        )
      end

      not is_wormhole
    else
      false
    end
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

  defp corporation_excluded?(killmail) do
    exclude_list = Config.corporation_exclude_list()

    if exclude_list == [] do
      false
    else
      # Convert to MapSet once for O(1) lookups
      exclude_set = MapSet.new(exclude_list)

      victim_excluded = victim_corp_excluded?(killmail, exclude_set)
      attacker_excluded = any_attacker_corp_excluded?(killmail, exclude_set)

      if victim_excluded or attacker_excluded do
        Logger.debug(
          "Corporation exclusion matched - killmail_id: #{Map.get(killmail, :killmail_id)}, " <>
            "victim_corp: #{inspect(Map.get(killmail, :victim_corporation_id))}, " <>
            "victim_excluded: #{victim_excluded}, attacker_excluded: #{attacker_excluded}"
        )
      end

      victim_excluded or attacker_excluded
    end
  end

  defp victim_corp_excluded?(killmail, exclude_set) do
    victim_corp_id = Map.get(killmail, :victim_corporation_id)
    normalized_id = normalize_corp_id(victim_corp_id)

    case normalized_id do
      nil -> false
      id -> MapSet.member?(exclude_set, id)
    end
  end

  # Normalizes corporation ID to integer for consistent comparison
  # Handles both integer and string IDs from different data sources
  defp normalize_corp_id(nil), do: nil
  defp normalize_corp_id(id) when is_integer(id), do: id

  defp normalize_corp_id(id) when is_binary(id) do
    case Integer.parse(id) do
      {num, ""} -> num
      _ -> nil
    end
  end

  defp normalize_corp_id(_), do: nil

  defp any_attacker_corp_excluded?(killmail, exclude_set) do
    attackers = Map.get(killmail, :attackers, []) || []

    Enum.any?(attackers, fn attacker ->
      corp_id = Map.get(attacker, "corporation_id") || Map.get(attacker, :corporation_id)
      normalized_id = normalize_corp_id(corp_id)

      case normalized_id do
        nil -> false
        id -> MapSet.member?(exclude_set, id)
      end
    end)
  end
end
