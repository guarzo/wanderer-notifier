defmodule WandererNotifier.Domains.Notifications.Formatters.KillmailFormatter do
  @moduledoc """
  Formats killmail notifications for Discord.

  Handles all killmail-specific formatting including victim/attacker details,
  ship information, notable loot, and system context.
  """

  alias WandererNotifier.Domains.Killmail.Killmail
  alias WandererNotifier.Domains.Notifications.Formatters.NotificationUtils, as: Utils
  alias WandererNotifier.Domains.Notifications.Formatters.FormatterHelpers
  alias WandererNotifier.Infrastructure.Cache
  require Logger

  # ══════════════════════════════════════════════════════════════════════════════
  # Public API
  # ══════════════════════════════════════════════════════════════════════════════

  @doc """
  Formats a killmail notification for Discord.
  """
  def format(%Killmail{} = killmail, opts \\ []) do
    format_killmail_notification(killmail, opts)
  end

  @doc """
  Formats a killmail embed for Discord.
  """
  def format_embed(%Killmail{} = killmail, opts \\ []) do
    build_killmail_embed(killmail, opts)
  end

  # ══════════════════════════════════════════════════════════════════════════════
  # Main Formatting Functions
  # ══════════════════════════════════════════════════════════════════════════════

  defp format_killmail_notification(%Killmail{} = killmail, _opts) do
    embed_color = FormatterHelpers.get_isk_color(killmail.value || 0)
    full_description = build_full_kill_description(killmail)

    %{
      type: :kill_notification,
      title: nil,
      description: full_description,
      color: embed_color,
      url: Utils.zkillboard_url(killmail.killmail_id),
      author: build_kill_author_icon(killmail),
      thumbnail: build_kill_thumbnail(killmail),
      fields: [],
      footer: nil,
      timestamp: nil
    }
  end

  defp build_killmail_embed(%Killmail{} = killmail, _opts) do
    format_killmail_notification(killmail, [])
  end

  # ══════════════════════════════════════════════════════════════════════════════
  # Kill Description Building
  # ══════════════════════════════════════════════════════════════════════════════

  defp build_full_kill_description(%Killmail{} = killmail) do
    # System line - use custom name if available
    system_name = get_system_display_name(killmail)

    system_link =
      if killmail.system_id do
        "[#{system_name}](https://zkillboard.com/system/#{killmail.system_id}/)"
      else
        system_name
      end

    # Main kill description
    victim_part = build_victim_description_part(killmail)
    attacker_part = build_attacker_description_part(killmail)
    main_line = "#{victim_part} #{attacker_part}"

    # Notable loot section
    notable_loot_section = build_notable_loot_section(killmail)

    # Value and timestamp
    value_time_line =
      if killmail.value && killmail.value > 0 do
        "Value: #{Utils.format_isk(killmail.value)} • #{format_timestamp(killmail)}"
      else
        format_timestamp(killmail)
      end

    # Combine all parts with blank lines
    """
    Ship destroyed in #{system_link}

    #{main_line}#{notable_loot_section}

    #{value_time_line}
    """
    |> String.trim()
  end

  # ══════════════════════════════════════════════════════════════════════════════
  # Author and Thumbnail Building
  # ══════════════════════════════════════════════════════════════════════════════

  defp build_kill_author_icon(%Killmail{} = killmail) do
    # Determine if tracked character is victim or attacker
    tracked_as = get_tracked_character_role(killmail)
    author_name = if tracked_as == :victim, do: "Loss", else: "Kill"

    final_blow = get_final_blow_attacker(killmail.attackers)

    corp_id =
      if final_blow do
        Map.get(final_blow, "corporation_id")
      end

    if corp_id do
      %{
        name: author_name,
        icon_url: Utils.corporation_logo_url(corp_id, 32),
        url: Utils.zkillboard_url(killmail.killmail_id)
      }
    else
      %{
        name: author_name,
        url: Utils.zkillboard_url(killmail.killmail_id)
      }
    end
  end

  defp build_kill_thumbnail(%Killmail{} = killmail) do
    # Always prefer ship image over character portrait
    cond do
      killmail.victim_ship_type_id ->
        killmail.victim_ship_type_id
        # Larger size for main thumbnail
        |> Utils.ship_render_url(512)
        |> Utils.build_thumbnail()

      killmail.victim_character_id ->
        killmail.victim_character_id
        |> Utils.character_portrait_url()
        |> Utils.build_thumbnail()

      true ->
        nil
    end
  end

  # ══════════════════════════════════════════════════════════════════════════════
  # Victim and Attacker Description Building
  # ══════════════════════════════════════════════════════════════════════════════

  defp build_victim_description_part(%Killmail{} = killmail) do
    victim_name = killmail.victim_character_name || "Unknown pilot"
    victim_id = killmail.victim_character_id
    corp_id = killmail.victim_corporation_id
    ship_name = get_ship_name_from_killmail(killmail, :victim)

    # Get corporation ticker
    corp_ticker = get_corp_ticker_from_killmail(killmail, "victim")

    # Create character link
    victim_link =
      if victim_id do
        "[#{victim_name}](https://zkillboard.com/character/#{victim_id}/)"
      else
        victim_name
      end

    # Create corp ticker link
    corp_link =
      if corp_id do
        "[#{corp_ticker}](https://zkillboard.com/corporation/#{corp_id}/)"
      else
        corp_ticker
      end

    "#{victim_link}(#{corp_link}) lost their #{ship_name} to"
  end

  defp build_attacker_description_part(%Killmail{} = killmail) do
    final_blow = get_final_blow_attacker(killmail.attackers)
    attacker_count = length(killmail.attackers || [])

    case final_blow do
      nil ->
        "unknown attackers"

      final_blow ->
        build_attacker_description_with_final_blow(final_blow, killmail.attackers, attacker_count)
    end
  end

  defp build_attacker_description_with_final_blow(final_blow, attackers, attacker_count) do
    attacker_display = build_attacker_display(final_blow)
    attacker_ship = get_attacker_ship_name(final_blow)

    if attacker_count == 1 do
      "#{attacker_display} flying in a #{attacker_ship} solo."
    else
      build_multi_attacker_description(
        attacker_display,
        attacker_ship,
        final_blow,
        attackers,
        attacker_count
      )
    end
  end

  defp build_multi_attacker_description(
         attacker_display,
         attacker_ship,
         final_blow,
         attackers,
         attacker_count
       ) do
    top_damage_part = build_top_damage_part(attackers, final_blow)
    others_count = attacker_count - 1

    "#{attacker_display} flying in a #{attacker_ship}#{top_damage_part} and #{others_count} others"
  end

  defp build_top_damage_part(attackers, final_blow) do
    top_damage = get_top_damage_attacker(attackers)

    if top_damage && top_damage != final_blow do
      top_display = build_attacker_display(top_damage)
      top_ship = get_attacker_ship_name(top_damage)
      ", Top Damage was done by #{top_display} flying in a #{top_ship}"
    else
      ""
    end
  end

  defp build_attacker_display(attacker) do
    attacker_name = Map.get(attacker, "character_name", "Unknown")
    attacker_id = Map.get(attacker, "character_id")
    attacker_corp_id = Map.get(attacker, "corporation_id")
    attacker_ticker = get_attacker_corp_ticker(attacker)

    attacker_link = create_character_link(attacker_name, attacker_id)
    attacker_corp_link = create_corporation_link(attacker_ticker, attacker_corp_id)

    "#{attacker_link}(#{attacker_corp_link})"
  end

  # ══════════════════════════════════════════════════════════════════════════════
  # Notable Loot Section
  # ══════════════════════════════════════════════════════════════════════════════

  defp build_notable_loot_section(%Killmail{
         items_dropped: items_dropped,
         notable_items: notable_items
       }) do
    # Use notable_items if available, otherwise fall back to items_dropped
    items = notable_items || items_dropped || []
    filtered_items = filter_notable_items(items)

    if length(filtered_items) > 0 do
      notable_list = build_notable_items_list(filtered_items)
      "\n\n**Notable Items:**\n#{notable_list}"
    else
      ""
    end
  end

  defp filter_notable_items(items) do
    items
    |> Enum.filter(fn item ->
      value = Map.get(item, "value", 0)
      # 50M ISK threshold
      value > 50_000_000
    end)
    # Limit to top 5 items
    |> Enum.take(5)
  end

  defp build_notable_items_list(items) do
    items
    |> Enum.map(fn item ->
      name = Map.get(item, "type_name", "Unknown Item")
      value = Map.get(item, "value", 0)
      quantity = Map.get(item, "quantity", 1)

      if quantity > 1 do
        "• #{name} x#{quantity} (~#{FormatterHelpers.format_isk(value)})"
      else
        "• #{name} (~#{FormatterHelpers.format_isk(value)})"
      end
    end)
    |> Enum.join("\n")
  end

  # ══════════════════════════════════════════════════════════════════════════════
  # Helper Functions
  # ══════════════════════════════════════════════════════════════════════════════

  defp create_character_link(name, nil), do: name
  defp create_character_link(name, id), do: "[#{name}](https://zkillboard.com/character/#{id}/)"

  defp create_corporation_link(ticker, nil), do: ticker

  defp create_corporation_link(ticker, id),
    do: "[#{ticker}](https://zkillboard.com/corporation/#{id}/)"

  defp get_corp_ticker_from_killmail(%Killmail{} = killmail, "victim") do
    # Try to get from cache first
    case Cache.get("corporation:#{killmail.victim_corporation_id}") do
      {:ok, corp_data} when is_map(corp_data) ->
        Map.get(corp_data, "ticker", "????")

      _ ->
        # Fallback to extracting from killmail data if available
        killmail.victim_corporation_name || "????"
    end
  end

  defp get_attacker_corp_ticker(attacker) do
    corp_id = Map.get(attacker, "corporation_id")

    if corp_id do
      case Cache.get("corporation:#{corp_id}") do
        {:ok, corp_data} when is_map(corp_data) ->
          Map.get(corp_data, "ticker", "????")

        _ ->
          Map.get(attacker, "corporation_ticker", "????")
      end
    else
      "????"
    end
  end

  defp get_ship_name_from_killmail(%Killmail{} = killmail, :victim) do
    # Try to get from cache first
    case Cache.get("ship_type:#{killmail.victim_ship_type_id}") do
      {:ok, ship_data} when is_map(ship_data) ->
        Map.get(ship_data, "name", "Unknown Ship")

      _ ->
        # Fallback to killmail data
        killmail.victim_ship_name || "Unknown Ship"
    end
  end

  defp get_attacker_ship_name(attacker) do
    ship_type_id = Map.get(attacker, "ship_type_id")

    if ship_type_id do
      case Cache.get("ship_type:#{ship_type_id}") do
        {:ok, ship_data} when is_map(ship_data) ->
          Map.get(ship_data, "name", "Unknown Ship")

        _ ->
          Map.get(attacker, "ship_type_name", "Unknown Ship")
      end
    else
      "Unknown Ship"
    end
  end

  defp get_final_blow_attacker(nil), do: nil
  defp get_final_blow_attacker([]), do: nil

  defp get_final_blow_attacker(attackers) do
    Enum.find(attackers, fn att -> Map.get(att, "final_blow") == true end) ||
      Enum.max_by(attackers, fn att -> Map.get(att, "damage_done", 0) end, fn -> nil end)
  end

  defp get_top_damage_attacker(attackers) do
    Enum.max_by(attackers, fn att -> Map.get(att, "damage_done", 0) end, fn -> nil end)
  end

  defp get_tracked_character_role(%Killmail{} = killmail) do
    # Check if victim is tracked
    victim_tracked = character_tracked?(killmail.victim_character_id)

    if victim_tracked do
      :victim
    else
      # Check if any attacker is tracked
      attacker_tracked =
        (killmail.attackers || [])
        |> Enum.any?(fn attacker ->
          char_id = Map.get(attacker, "character_id")
          character_tracked?(char_id)
        end)

      if attacker_tracked, do: :attacker, else: :unknown
    end
  end

  defp character_tracked?(nil), do: false

  defp character_tracked?(character_id) do
    case Cache.get("tracked_character:#{character_id}") do
      {:ok, _} -> true
      _ -> false
    end
  end

  defp get_system_display_name(%Killmail{} = killmail) do
    get_custom_system_name(killmail.system_id, killmail) ||
      get_fallback_system_name(killmail) ||
      "Unknown System"
  end

  defp get_custom_system_name(system_id, killmail) when is_integer(system_id) do
    get_custom_system_name(Integer.to_string(system_id), killmail)
  end

  defp get_custom_system_name(system_id, killmail) when is_binary(system_id) do
    fetch_system_name(system_id, killmail)
  end

  defp fetch_system_name(system_id_string, killmail) do
    case Cache.get("tracked_system:#{system_id_string}") do
      {:ok, system_data} when is_map(system_data) ->
        custom_name = Map.get(system_data, "custom_name")

        if custom_name && custom_name != "" do
          custom_name
        else
          Map.get(system_data, "name") || Map.get(system_data, "system_name")
        end

      _ ->
        get_fallback_system_name(killmail)
    end
  end

  defp get_fallback_system_name(killmail) do
    killmail.system_name ||
      (killmail.system_id && "System #{killmail.system_id}") ||
      nil
  end

  defp format_timestamp(%Killmail{kill_time: kill_time}) when is_binary(kill_time) do
    FormatterHelpers.format_timestamp_with_context(kill_time)
  end

  defp format_timestamp(_), do: "Recently"
end
