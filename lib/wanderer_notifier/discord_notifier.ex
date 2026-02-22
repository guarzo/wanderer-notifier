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
  alias WandererNotifier.Map.MapConfig

  defp map_registry do
    Application.get_env(
      :wanderer_notifier,
      :map_registry_module,
      WandererNotifier.Map.MapRegistry
    )
  end

  @doc """
  Send a kill notification asynchronously.
  Returns immediately, actual sending happens in background Task.
  """
  def send_kill_async(killmail) do
    Task.Supervisor.start_child(WandererNotifier.TaskSupervisor, fn ->
      handle_kill_result(send_kill_notification(killmail), killmail)
    end)

    :ok
  end

  @doc """
  Send a rally point notification asynchronously.
  Returns immediately, actual sending happens in background Task.
  """
  def send_rally_point_async(rally_point) do
    Task.Supervisor.start_child(WandererNotifier.TaskSupervisor, fn ->
      send_rally_point_notification(rally_point)
    end)

    :ok
  end

  @doc """
  Send a system notification asynchronously.
  Returns immediately, actual sending happens in background Task.
  """
  def send_system_async(system) do
    Task.Supervisor.start_child(WandererNotifier.TaskSupervisor, fn ->
      send_system_notification(system)
    end)

    :ok
  end

  @doc """
  Send a character notification asynchronously.
  Returns immediately, actual sending happens in background Task.
  """
  def send_character_async(character) do
    Task.Supervisor.start_child(WandererNotifier.TaskSupervisor, fn ->
      send_character_notification(character)
    end)

    :ok
  end

  @doc """
  Send a generic Discord embed asynchronously.
  Returns immediately, actual sending happens in background Task.
  """
  def send_embed_async(embed, opts \\ []) do
    Task.Supervisor.start_child(WandererNotifier.TaskSupervisor, fn ->
      send_generic_embed(embed, opts)
    end)

    :ok
  end

  # ═══════════════════════════════════════════════════════════════════════════════
  # Multi-Map API - MapConfig-aware send functions
  # ═══════════════════════════════════════════════════════════════════════════════

  @doc """
  Send a kill notification for a specific map asynchronously.
  Uses MapConfig for channel routing, feature flags, and bot token.
  """
  def send_kill_async(killmail, %MapConfig{} = map_config) do
    Task.Supervisor.start_child(WandererNotifier.TaskSupervisor, fn ->
      handle_kill_result(
        send_kill_notification_for_map(killmail, map_config),
        killmail,
        map_config
      )
    end)

    :ok
  end

  @doc """
  Send a system notification for a specific map asynchronously.
  """
  def send_system_async(system, %MapConfig{} = map_config) do
    Task.Supervisor.start_child(WandererNotifier.TaskSupervisor, fn ->
      send_system_notification_for_map(system, map_config)
    end)

    :ok
  end

  @doc """
  Send a character notification for a specific map asynchronously.
  """
  def send_character_async(character, %MapConfig{} = map_config) do
    Task.Supervisor.start_child(WandererNotifier.TaskSupervisor, fn ->
      send_character_notification_for_map(character, map_config)
    end)

    :ok
  end

  @doc """
  Send a rally point notification for a specific map asynchronously.
  """
  def send_rally_point_async(rally_point, %MapConfig{} = map_config) do
    Task.Supervisor.start_child(WandererNotifier.TaskSupervisor, fn ->
      send_rally_point_notification_for_map(rally_point, map_config)
    end)

    :ok
  end

  # ═══════════════════════════════════════════════════════════════════════════════
  # Private Implementation - All Discord API calls happen here
  # ═══════════════════════════════════════════════════════════════════════════════

  # Legacy (single-map) result handler
  defp handle_kill_result({:ok, :sent}, killmail) do
    Logger.debug("Kill notification sent successfully", killmail_id: killmail.killmail_id)
  end

  defp handle_kill_result({:ok, :skipped}, killmail) do
    Logger.debug("Kill notification skipped", killmail_id: killmail.killmail_id)
  end

  defp handle_kill_result(:skipped, killmail) do
    Logger.debug("Kill notification skipped", killmail_id: killmail.killmail_id)
  end

  defp handle_kill_result(:error, killmail) do
    emit_kill_failure_telemetry(killmail, :internal_error)
  end

  # Multi-map result handler
  defp handle_kill_result({:ok, %{sent: _, failed: 0}}, killmail, mc) do
    Logger.debug("Kill notification sent for map #{mc.slug}", killmail_id: killmail.killmail_id)
  end

  defp handle_kill_result({:ok, :skipped}, killmail, mc) do
    Logger.debug("Kill notification skipped for map #{mc.slug}",
      killmail_id: killmail.killmail_id
    )
  end

  defp handle_kill_result({:error, %{sent: _, failed: failed}}, killmail, mc) do
    Logger.error("Kill notification partially failed for map #{mc.slug}",
      killmail_id: killmail.killmail_id,
      map_slug: mc.slug,
      failed_channels: failed
    )

    emit_kill_failure_telemetry(killmail, :partial_failure)
  end

  defp handle_kill_result({:error, reason}, killmail, mc) do
    Logger.error("Kill notification failed for map #{mc.slug}",
      killmail_id: killmail.killmail_id,
      map_slug: mc.slug,
      reason: inspect(reason)
    )

    emit_kill_failure_telemetry(killmail, :internal_error)
  end

  defp emit_kill_failure_telemetry(killmail, reason) do
    :telemetry.execute([:wanderer_notifier, :notification, :failed], %{count: 1}, %{
      type: :kill,
      killmail_id: killmail.killmail_id,
      reason: inspect(reason)
    })
  end

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

    # Early return guard - wormhole-only filter blocks ALL kill notifications for non-wormhole systems
    if wormhole_only_excluded?(system_id) do
      Logger.debug(
        "Kill notification skipped - non-wormhole system with wormhole-only filter enabled",
        killmail_id: killmail_id,
        system_id: system_id
      )

      {:ok, :skipped}
    else
      process_kill_notification(killmail, killmail_id)
    end
  end

  defp process_kill_notification(killmail, killmail_id) do
    channels = determine_kill_channels(killmail)

    Logger.info("Kill notification channel routing",
      killmail_id: killmail_id,
      channels: inspect(channels),
      category: :notifications
    )

    dispatch_to_channels(killmail, channels, killmail_id)
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
    mc = legacy_map_config()
    send_rally_point_notification_for_map(rally_point, mc)
  end

  defp send_system_notification(system) do
    mc = legacy_map_config()
    send_system_notification_for_map(system, mc)
  end

  defp send_character_notification(character) do
    mc = legacy_map_config()
    send_character_notification_for_map(character, mc)
  end

  defp legacy_map_config do
    case map_registry().all_maps() do
      [config | _] -> config
      [] -> MapConfig.from_env()
    end
  end

  defp send_generic_embed(embed, opts) do
    Logger.debug("Processing generic embed notification async")

    try do
      if notifications_enabled?() do
        # Extract channel from opts or use default
        channel_id = Keyword.get(opts, :channel_id, Config.discord_channel_id())

        case send_to_discord(embed, channel_id) do
          :ok ->
            Logger.debug("Generic embed sent successfully")
            {:ok, :sent}

          {:error, reason} ->
            {:error, reason}
        end
      else
        Logger.debug("Notifications disabled, skipping generic embed")
        {:ok, :skipped}
      end
    rescue
      e ->
        Logger.error("Exception in send_generic_embed: #{Exception.message(e)}")
        {:error, {:exception, Exception.message(e)}}
    end
  end

  # ═══════════════════════════════════════════════════════════════════════════════
  # Private Implementation - Multi-Map (via HttpClient)
  # ═══════════════════════════════════════════════════════════════════════════════

  defp send_kill_notification_for_map(killmail, %MapConfig{} = mc) do
    if MapConfig.notifications_fully_enabled?(mc, :kill_notifications_enabled) do
      system_id = Map.get(killmail, :system_id)

      if map_wormhole_only_excluded?(mc, system_id) do
        {:ok, :skipped}
      else
        channels = determine_kill_channels_for_map(killmail, mc)
        dispatch_to_map_channels(killmail, channels, mc)
      end
    else
      {:ok, :skipped}
    end
  rescue
    e ->
      Logger.error("Exception in send_kill_notification_for_map: #{Exception.message(e)}")
      {:error, {:exception, Exception.message(e)}}
  end

  defp send_system_notification_for_map(system, %MapConfig{} = mc) do
    if MapConfig.notifications_fully_enabled?(mc, :system_notifications_enabled) do
      case format_notification(system) do
        {:ok, formatted} ->
          channel_id = MapConfig.channel_for(mc, :system)
          send_to_discord_for_map(formatted, channel_id, mc)

        {:error, reason} ->
          Logger.error("Failed to format system notification: #{inspect(reason)}")
          {:error, {:format_error, reason}}
      end
    else
      {:ok, :skipped}
    end
  rescue
    e ->
      Logger.error("Exception in send_system_notification_for_map: #{Exception.message(e)}")
      {:error, {:exception, Exception.message(e)}}
  end

  defp send_character_notification_for_map(character, %MapConfig{} = mc) do
    if MapConfig.notifications_fully_enabled?(mc, :character_notifications_enabled) do
      case format_notification(character) do
        {:ok, formatted} ->
          channel_id = MapConfig.channel_for(mc, :character)
          send_to_discord_for_map(formatted, channel_id, mc)

        {:error, reason} ->
          Logger.error("Failed to format character notification: #{inspect(reason)}")
          {:error, {:format_error, reason}}
      end
    else
      {:ok, :skipped}
    end
  rescue
    e ->
      Logger.error("Exception in send_character_notification_for_map: #{Exception.message(e)}")
      {:error, {:exception, Exception.message(e)}}
  end

  defp send_rally_point_notification_for_map(rally_point, %MapConfig{} = mc) do
    if MapConfig.notifications_fully_enabled?(mc, :rally_notifications_enabled) do
      case format_notification(rally_point) do
        {:ok, formatted} ->
          channel_id = MapConfig.channel_for(mc, :rally)
          content = build_rally_content_for_map(mc)
          formatted_with_content = Map.put(formatted, :content, content)
          send_to_discord_for_map(formatted_with_content, channel_id, mc)

        {:error, reason} ->
          Logger.error("Failed to format rally point notification: #{inspect(reason)}")
          {:error, {:format_error, reason}}
      end
    else
      {:ok, :skipped}
    end
  rescue
    e ->
      Logger.error("Exception in send_rally_point_notification_for_map: #{Exception.message(e)}")
      {:error, {:exception, Exception.message(e)}}
  end

  defp determine_kill_channels_for_map(killmail, %MapConfig{} = mc) do
    system_id = Map.get(killmail, :system_id)
    involves_focused = involves_focused_corporation_for_map?(killmail, mc)

    # has_tracked_system is always true: Pipeline fan-out already verified
    # this map tracks the system via MapRegistry reverse index before dispatching.
    ctx = %{
      involves_focused_corp: involves_focused,
      has_tracked_system: true,
      wormhole_excluded: map_wormhole_only_excluded?(mc, system_id),
      default_channel: MapConfig.channel_for(mc, :primary),
      system_channel: MapConfig.channel_for(mc, :system_kill),
      character_channel: MapConfig.channel_for(mc, :character_kill)
    }

    select_channels(ctx) |> Enum.uniq()
  end

  defp dispatch_to_map_channels(_killmail, [], _mc), do: {:ok, :skipped}

  defp dispatch_to_map_channels(killmail, channels, mc) do
    {sent, failed} =
      Enum.reduce(channels, {0, 0}, fn channel_id, {sent_count, fail_count} ->
        case send_kill_to_map_channel(killmail, channel_id, mc) do
          {:ok, _} -> {sent_count + 1, fail_count}
          {:error, _} -> {sent_count, fail_count + 1}
        end
      end)

    if failed == 0 do
      {:ok, %{sent: sent, failed: 0}}
    else
      {:error, %{sent: sent, failed: failed}}
    end
  end

  defp send_kill_to_map_channel(killmail, channel_id, mc) do
    system_kill = channel_id == MapConfig.channel_for(mc, :system_kill)

    case format_notification(killmail, use_custom_system_name: system_kill) do
      {:ok, formatted} ->
        case send_to_discord_for_map(formatted, channel_id, mc) do
          :ok -> {:ok, :sent}
          {:error, reason} -> {:error, reason}
        end

      {:error, reason} ->
        Logger.error("Failed to format kill notification: #{inspect(reason)}")
        {:error, {:format_error, reason}}
    end
  end

  defp send_to_discord_for_map(embed, channel_id, %MapConfig{} = mc) do
    content = Map.get(embed, :content)

    result =
      if is_binary(content) and String.trim(content) != "" do
        NeoClient.send_embed_with_content_for_map(embed, mc, channel_id, content)
      else
        NeoClient.send_embed_for_map(embed, mc, channel_id)
      end

    case result do
      {:ok, :sent} ->
        Logger.debug("Discord notification sent for map #{mc.slug}",
          channel: channel_id,
          map_slug: mc.slug
        )

        :ok

      {:error, reason} ->
        Logger.error("Discord notification failed for map #{mc.slug}",
          channel: channel_id,
          map_slug: mc.slug,
          reason: inspect(reason)
        )

        {:error, reason}
    end
  end

  defp map_wormhole_only_excluded?(%MapConfig{} = mc, system_id) do
    MapConfig.feature_enabled?(mc, :wormhole_only_kill_notifications) and
      not wormhole_system?(system_id)
  end

  defp involves_focused_corporation_for_map?(killmail, %MapConfig{} = mc) do
    focus_corps = MapConfig.corporation_kill_focus(mc)
    do_involves_focused_corporation?(killmail, focus_corps)
  end

  defp build_rally_content_for_map(%MapConfig{} = mc) do
    group_ids = MapConfig.rally_group_ids(mc)

    if group_ids == [] do
      "Rally point created!"
    else
      mentions = Enum.map_join(group_ids, " ", fn id -> "<@&#{id}>" end)
      "#{mentions} Rally point created!"
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

  # Simplified tracking checks - delegate to existing modules
  defp tracked_system?(system_id) do
    WandererNotifier.Domains.Notifications.Determiner.tracked_system_for_killmail?(system_id)
  end

  # Feature flags
  defp notifications_enabled?, do: Config.notifications_enabled?()
  defp kill_notifications_enabled?, do: Config.kill_notifications_enabled?()

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
