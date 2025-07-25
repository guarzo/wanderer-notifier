defmodule WandererNotifier.Domains.Notifications.Formatters.Unified do
  @moduledoc """
  Unified notification formatter for all notification types.
  Consolidates killmail, character, and system formatting into a single module.
  """

  alias WandererNotifier.Domains.Killmail.Killmail
  alias WandererNotifier.Domains.Tracking.Entities.{Character, System}
  alias WandererNotifier.Domains.Notifications.Formatters.Utilities, as: Utils

  # ═══════════════════════════════════════════════════════════════════════════════
  # Public API
  # ═══════════════════════════════════════════════════════════════════════════════

  @doc """
  Format any notification based on its type.
  """
  def format_notification(%Killmail{} = killmail) do
    format_kill_notification(killmail)
  end

  def format_notification(%Character{} = character) do
    format_character_notification(character)
  end

  def format_notification(%System{} = system) do
    format_system_notification(system)
  end

  # ═══════════════════════════════════════════════════════════════════════════════
  # Kill Notifications
  # ═══════════════════════════════════════════════════════════════════════════════

  defp format_kill_notification(%Killmail{} = killmail) do
    victim_name = killmail.victim_character_name || killmail.victim_ship_name || "Unknown"
    system_link = Utils.create_system_link(killmail.system_name, killmail.system_id)

    %{
      type: :kill_notification,
      title: build_kill_title(victim_name, killmail.victim_ship_name),
      description: build_kill_description(killmail),
      color: Utils.get_color(:kill),
      url: Utils.zkillboard_url(killmail.killmail_id),
      thumbnail: build_kill_thumbnail(killmail),
      fields: build_kill_fields(killmail, system_link),
      footer: build_kill_footer(killmail),
      timestamp: get_timestamp(killmail)
    }
  end

  defp build_kill_title(victim_name, ship_name) do
    if ship_name do
      "#{victim_name}'s #{ship_name} destroyed"
    else
      "#{victim_name} destroyed"
    end
  end

  defp build_kill_description(%Killmail{} = killmail) do
    attacker_count = length(killmail.attackers || [])
    value_str = Utils.format_isk(killmail.value)

    "A #{value_str} kill involving #{attacker_count} attacker(s)"
  end

  defp build_kill_thumbnail(%Killmail{} = killmail) do
    cond do
      killmail.victim_character_id ->
        killmail.victim_character_id
        |> Utils.character_portrait_url()
        |> Utils.build_thumbnail()

      killmail.victim_ship_type_id ->
        killmail.victim_ship_type_id
        |> Utils.ship_render_url()
        |> Utils.build_thumbnail()

      true ->
        nil
    end
  end

  defp build_kill_fields(%Killmail{} = killmail, system_link) do
    fields = []

    # Victim field
    victim_field = build_victim_field(killmail)
    fields = if victim_field, do: [victim_field | fields], else: fields

    # System field
    fields = [Utils.build_field("System", system_link, true) | fields]

    # Value field
    fields =
      if killmail.value && killmail.value > 0 do
        [Utils.build_field("Value", Utils.format_isk(killmail.value), true) | fields]
      else
        fields
      end

    # Corporation/Alliance fields
    fields = add_corp_alliance_fields(fields, killmail)

    # Final blow field
    final_blow = get_final_blow_attacker(killmail.attackers)

    fields =
      if final_blow do
        [build_final_blow_field(final_blow) | fields]
      else
        fields
      end

    Enum.reverse(fields)
  end

  defp build_victim_field(%Killmail{} = killmail) do
    if killmail.victim_character_name do
      victim_link =
        Utils.create_character_link(
          killmail.victim_character_name,
          killmail.victim_character_id
        )

      Utils.build_field("Victim", victim_link, true)
    else
      nil
    end
  end

  defp add_corp_alliance_fields(fields, %Killmail{} = killmail) do
    fields =
      if killmail.victim_corporation_name do
        [Utils.build_field("Corporation", killmail.victim_corporation_name, true) | fields]
      else
        fields
      end

    if killmail.victim_alliance_name do
      [Utils.build_field("Alliance", killmail.victim_alliance_name, true) | fields]
    else
      fields
    end
  end

  defp get_final_blow_attacker(nil), do: nil
  defp get_final_blow_attacker([]), do: nil

  defp get_final_blow_attacker(attackers) do
    Enum.find(attackers, fn att -> Map.get(att, "final_blow") == true end) ||
      Enum.max_by(attackers, fn att -> Map.get(att, "damage_done", 0) end, fn -> nil end)
  end

  defp build_final_blow_field(attacker) do
    name = Map.get(attacker, "character_name", "Unknown")
    char_id = Map.get(attacker, "character_id")
    ship = Map.get(attacker, "ship_name", "Unknown Ship")

    final_blow_text =
      if char_id do
        "#{Utils.create_character_link(name, char_id)} (#{ship})"
      else
        "#{name} (#{ship})"
      end

    Utils.build_field("Final Blow", final_blow_text, false)
  end

  defp build_kill_footer(%Killmail{points: points}) when is_integer(points) do
    Utils.build_footer("zKillboard • #{points} points")
  end

  defp build_kill_footer(_) do
    Utils.build_footer("zKillboard")
  end

  defp get_timestamp(%Killmail{kill_time: kill_time}) when is_binary(kill_time) do
    kill_time
  end

  defp get_timestamp(%Killmail{esi_data: %{"killmail_time" => time}}) when is_binary(time) do
    time
  end

  defp get_timestamp(_), do: DateTime.utc_now() |> DateTime.to_iso8601()

  # ═══════════════════════════════════════════════════════════════════════════════
  # Character Notifications
  # ═══════════════════════════════════════════════════════════════════════════════

  defp format_character_notification(%Character{} = character) do
    %{
      type: :character_notification,
      title: "New Character Tracked: #{character.name}",
      description: build_character_description(character),
      color: Utils.get_color(:character),
      url: Utils.evewho_url(character.character_id),
      thumbnail:
        character.character_id |> Utils.character_portrait_url() |> Utils.build_thumbnail(),
      fields: build_character_fields(character),
      footer: Utils.build_footer("Character ID: #{character.character_id}")
    }
  end

  defp build_character_description(%Character{} = character) do
    parts = []

    parts =
      if character.corporation_ticker do
        ["[#{character.corporation_ticker}]" | parts]
      else
        parts
      end

    parts =
      if character.alliance_ticker do
        ["<#{character.alliance_ticker}>" | parts]
      else
        parts
      end

    if Enum.empty?(parts) do
      "A new character has been added to tracking."
    else
      "#{Enum.join(parts, " ")} has been added to tracking."
    end
  end

  defp build_character_fields(%Character{} = character) do
    fields = []

    # Character name with link
    char_link = Utils.create_character_link(character.name, character.character_id)
    fields = [Utils.build_field("Character", char_link, true) | fields]

    # Corporation
    fields =
      if character.corporation_ticker do
        [Utils.build_field("Corporation", character.corporation_ticker, true) | fields]
      else
        fields
      end

    # Alliance
    fields =
      if character.alliance_ticker do
        [Utils.build_field("Alliance", character.alliance_ticker, true) | fields]
      else
        fields
      end

    Enum.reverse(fields)
  end

  # ═══════════════════════════════════════════════════════════════════════════════
  # System Notifications
  # ═══════════════════════════════════════════════════════════════════════════════

  defp format_system_notification(%System{} = system) do
    is_wormhole = System.wormhole?(system)

    %{
      type: :system_notification,
      title: "New System Tracked: #{system.name}",
      description: build_system_description(system, is_wormhole),
      color:
        if(is_wormhole, do: :wormhole, else: Utils.security_color(system.type_description))
        |> Utils.get_color(),
      thumbnail:
        if(is_wormhole, do: :wormhole, else: system.type_description)
        |> Utils.get_system_icon()
        |> Utils.build_thumbnail(),
      fields: build_system_fields(system, is_wormhole),
      footer: Utils.build_footer("System ID: #{system.solar_system_id}")
    }
  end

  defp build_system_description(%System{} = system, is_wormhole) do
    cond do
      is_wormhole && system.class_title ->
        "A new wormhole system (#{system.class_title}) has been added to tracking."

      system.type_description ->
        "A new #{system.type_description} system has been added to tracking."

      true ->
        "A new system has been added to tracking."
    end
  end

  defp build_system_fields(%System{} = system, is_wormhole) do
    []
    |> add_system_field(system)
    |> add_shattered_field(system, is_wormhole)
    |> add_statics_field(system, is_wormhole)
    |> add_region_field(system)
    |> add_effect_field(system, is_wormhole)
    |> Enum.reverse()
  end

  defp add_system_field(fields, system) do
    system_link = Utils.create_system_link(system.name, system.solar_system_id)
    [Utils.build_field("System", system_link, true) | fields]
  end

  defp add_shattered_field(fields, system, is_wormhole) do
    if is_wormhole && system.is_shattered do
      [Utils.build_field("Shattered", "Yes", true) | fields]
    else
      fields
    end
  end

  defp add_statics_field(fields, system, is_wormhole) do
    if is_wormhole && system.statics && length(system.statics) > 0 do
      statics_text = format_statics(system.statics)
      [Utils.build_field("Statics", statics_text, true) | fields]
    else
      fields
    end
  end

  defp add_region_field(fields, system) do
    if system.region_name do
      region_link =
        Utils.create_link(system.region_name, Utils.dotlan_region_url(system.region_name))

      [Utils.build_field("Region", region_link, true) | fields]
    else
      fields
    end
  end

  defp add_effect_field(fields, system, is_wormhole) do
    if is_wormhole && system.effect_name do
      [Utils.build_field("Effect", system.effect_name, true) | fields]
    else
      fields
    end
  end

  defp format_statics(statics) when is_list(statics) do
    Enum.join(statics, ", ")
  end

  defp format_statics(_), do: "N/A"

  # ═══════════════════════════════════════════════════════════════════════════════
  # Plain Text Formatting
  # ═══════════════════════════════════════════════════════════════════════════════

  @doc """
  Format notification as plain text for fallback scenarios.
  """
  def format_plain_text(%{type: :kill_notification} = notification) do
    """
    💀 #{notification.title}
    #{notification.description}
    System: #{get_field_value(notification.fields, "System")}
    Value: #{get_field_value(notification.fields, "Value")}
    #{notification.url}
    """
  end

  def format_plain_text(%{type: :character_notification} = notification) do
    """
    👤 #{notification.title}
    #{notification.description}
    #{notification.url || ""}
    """
  end

  def format_plain_text(%{type: :system_notification} = notification) do
    """
    🌌 #{notification.title}
    #{notification.description}
    """
  end

  def format_plain_text(_), do: "Notification"

  defp get_field_value(fields, name) do
    case Enum.find(fields, fn f -> f.name == name end) do
      %{value: value} -> value
      _ -> ""
    end
  end
end
