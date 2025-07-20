defmodule WandererNotifier.Domains.Notifications.Formatters.Killmail do
  @moduledoc """
  Killmail notification formatting utilities for Discord notifications.
  Provides rich formatting for killmail events.
  """
  alias WandererNotifier.Domains.Killmail.Killmail
  alias WandererNotifier.Shared.Logger.ErrorLogger
  alias WandererNotifier.Shared.Config.Utils
  alias WandererNotifier.Domains.SystemTracking.System
  alias WandererNotifier.Domains.Notifications.Formatters.Base, as: FormatterBase

  @doc """
  Creates a standard formatted kill notification embed/attachment from a Killmail struct.
  Returns data in a generic format that can be converted to platform-specific format.
  """
  def format_kill_notification(%Killmail{} = killmail) do
    kill_id = killmail.killmail_id
    kill_time = Map.get(killmail.esi_data || %{}, "killmail_time")
    victim_info = extract_victim_info(killmail)
    kill_context = extract_kill_context(killmail)
    final_blow_details = get_final_blow_details(killmail)
    fields = build_kill_notification_fields(victim_info, kill_context, final_blow_details)

    notification =
      build_kill_notification(
        kill_id,
        kill_time,
        victim_info,
        kill_context,
        final_blow_details,
        fields
      )

    notification
  rescue
    e ->
      ErrorLogger.log_exception(
        "Error formatting kill notification",
        e,
        kill_id: killmail.killmail_id,
        module: __MODULE__,
        killmail_struct: inspect(killmail)
      )

      reraise e, __STACKTRACE__
  end

  @doc """
  Formats a killmail for notification.
  """
  def format(%Killmail{} = killmail) do
    %{
      title: "New Killmail",
      description: format_description(killmail),
      color: 0xFF0000,
      fields: format_fields(killmail)
    }
  end

  defp extract_victim_info(killmail) do
    victim = Killmail.get_victim(killmail) || %{}

    victim_name = killmail.victim_name || Map.get(victim, "character_name", "Unknown Pilot")
    victim_ship = killmail.ship_name || Map.get(victim, "ship_type_name", "Unknown Ship")

    victim_corp =
      killmail.victim_corporation || Map.get(victim, "corporation_name", "Unknown Corp")

    victim_corp_ticker = killmail.victim_corp_ticker
    victim_alliance = killmail.victim_alliance || Map.get(victim, "alliance_name")
    victim_ship_type_id = Map.get(victim, "ship_type_id")
    victim_character_id = Map.get(victim, "character_id")

    %{
      name: victim_name,
      ship: victim_ship,
      corp: victim_corp,
      corp_ticker: victim_corp_ticker,
      alliance: victim_alliance,
      ship_type_id: victim_ship_type_id,
      character_id: victim_character_id,
      raw_victim_data: victim
    }
  end

  defp extract_kill_context(killmail) do
    system_id = killmail.system_id || Map.get(killmail.esi_data || %{}, "solar_system_id")

    system_name =
      killmail.system_name ||
        Map.get(killmail.esi_data || %{}, "solar_system_name") ||
        if(system_id,
          do: get_system_name_from_map_or_esi(system_id),
          else: "Unknown"
        )

    security_status = get_system_security_status(system_id)
    security_formatted = format_security_status(security_status)

    zkb = killmail.zkb
    kill_value = Map.get(zkb, "totalValue", 0)
    formatted_value = format_isk_value(kill_value)

    attackers = Map.get(killmail.esi_data || %{}, "attackers", [])
    attackers_count = length(attackers)

    %{
      system_name: system_name,
      system_id: system_id,
      security_status: security_status,
      security_formatted: security_formatted,
      formatted_value: formatted_value,
      attackers_count: attackers_count,
      is_npc_kill: Map.get(zkb, "npc", false) == true
    }
  end

  defp get_system_security_status(system_id) when is_integer(system_id) do
    # You may want to use your cache or static info here
    0.0
  end

  defp get_system_security_status(_), do: 0.0

  defp format_security_status(security_status)
       when is_float(security_status) and security_status >= 0.5,
       do: "High Sec"

  defp format_security_status(security_status)
       when is_float(security_status) and security_status > 0.0,
       do: "Low Sec"

  defp format_security_status(security_status)
       when is_float(security_status) and security_status == 0.0,
       do: "Null Sec"

  defp format_security_status(security_status)
       when is_float(security_status) and security_status < 0.0,
       do: "W-Space"

  defp format_security_status(_), do: "Unknown"

  defp get_final_blow_details(killmail) do
    # Get the final blow attacker or fall back to first attacker
    final_blow_attacker =
      Enum.find(killmail.attackers, fn attacker ->
        get_attacker_value(attacker, :final_blow) in [true, "true"]
      end) || List.first(killmail.attackers)

    # Extract enriched attacker data
    enriched_attacker = enrich_attacker_data(final_blow_attacker, killmail)

    # Check if this is an NPC kill
    is_npc_kill = Map.get(killmail.zkb, "npc", false)

    # Build the final blow details
    %{
      character: enriched_attacker.character,
      character_id: enriched_attacker.character_id,
      ship: enriched_attacker.ship,
      ship_id: enriched_attacker.ship_id,
      corp: enriched_attacker.corp,
      corp_id: enriched_attacker.corp_id,
      alliance: enriched_attacker.alliance,
      alliance_id: enriched_attacker.alliance_id,
      corp_ticker: enriched_attacker.corp_ticker,
      alliance_ticker: enriched_attacker.alliance_ticker,
      icon_url: enriched_attacker.icon_url,
      text: build_final_blow_text(enriched_attacker, is_npc_kill)
    }
  end

  defp enrich_attacker_data(attacker, _killmail) do
    # Get character info
    character = get_attacker_value(attacker, :character_name)
    character_id = get_attacker_value(attacker, :character_id)

    # Get ship info
    ship = get_attacker_value(attacker, :ship_name)
    ship_id = get_attacker_value(attacker, :ship_type_id)

    # Get corp info
    corp = get_attacker_value(attacker, :corporation_name)
    corp_id = get_attacker_value(attacker, :corporation_id)

    # Get alliance info
    alliance = get_attacker_value(attacker, :alliance_name)
    alliance_id = get_attacker_value(attacker, :alliance_id)

    # Get tickers
    corp_ticker = get_attacker_value(attacker, :corporation_ticker)
    alliance_ticker = get_attacker_value(attacker, :alliance_ticker)

    # Build icon URL
    icon_url = build_attacker_icon_url(character_id, corp_id, alliance_id)

    %{
      character: character,
      character_id: character_id,
      ship: ship,
      ship_id: ship_id,
      corp: corp,
      corp_id: corp_id,
      alliance: alliance,
      alliance_id: alliance_id,
      corp_ticker: corp_ticker,
      alliance_ticker: alliance_ticker,
      icon_url: icon_url
    }
  end

  defp build_final_blow_text(_attacker, true), do: "NPC"

  defp build_final_blow_text(%{character: character, ship: ship}, false)
       when is_binary(character) and is_binary(ship) do
    "#{character} in #{ship}"
  end

  defp build_final_blow_text(%{character: character}, false)
       when is_binary(character) do
    character
  end

  defp build_final_blow_text(%{ship: ship}, false)
       when is_binary(ship) do
    ship
  end

  defp build_final_blow_text(_attacker, _is_npc_kill), do: "Unknown"

  defp build_attacker_icon_url(character_id, _corp_id, _alliance_id)
       when is_integer(character_id) and character_id > 0 do
    "https://images.evetech.net/characters/#{character_id}/portrait?size=64"
  end

  defp build_attacker_icon_url(_character_id, corp_id, _alliance_id)
       when is_integer(corp_id) and corp_id > 0 do
    "https://images.evetech.net/corporations/#{corp_id}/logo?size=64"
  end

  defp build_attacker_icon_url(_character_id, _corp_id, alliance_id)
       when is_integer(alliance_id) and alliance_id > 0 do
    "https://images.evetech.net/alliances/#{alliance_id}/logo?size=64"
  end

  defp build_attacker_icon_url(_character_id, _corp_id, _alliance_id), do: nil

  defp get_attacker_value(attacker, key) when is_map(attacker) do
    case {Map.has_key?(attacker, key), Map.has_key?(attacker, to_string(key))} do
      {true, _} -> Map.get(attacker, key)
      {false, true} -> Map.get(attacker, to_string(key))
      {false, false} -> nil
    end
  end

  defp get_attacker_value(_attacker, _key), do: nil

  defp build_kill_notification_fields(_victim_info, kill_context, final_blow_details) do
    # Build base fields (value, attackers, final blow)
    fields = build_base_fields(kill_context, final_blow_details)

    # Add attacker corp field if available
    corp_field = build_corp_field(final_blow_details)
    alliance_field = build_alliance_field(final_blow_details)
    security_field = build_security_field(kill_context)

    # Combine all fields
    fields = if corp_field, do: fields ++ [corp_field], else: fields
    fields = if alliance_field, do: fields ++ [alliance_field], else: fields
    fields = if security_field, do: fields ++ [security_field], else: fields

    fields
  end

  defp build_base_fields(kill_context, final_blow_details) do
    [
      %{name: "Value", value: kill_context.formatted_value, inline: true},
      %{name: "Attackers", value: "#{kill_context.attackers_count}", inline: true},
      %{name: "Final Blow", value: format_final_blow(final_blow_details), inline: true}
    ]
  end

  defp format_final_blow(%{character: character, character_id: character_id, ship: ship})
       when is_binary(character) and is_integer(character_id) and is_binary(ship) do
    "[#{character}](#{build_zkillboard_url(:character, character_id)})/#{ship}"
  end

  defp format_final_blow(%{character: character, character_id: character_id})
       when is_binary(character) and is_integer(character_id) do
    "[#{character}](#{build_zkillboard_url(:character, character_id)})"
  end

  defp format_final_blow(%{character: character}) when is_binary(character) do
    character
  end

  defp format_final_blow(_), do: "Unknown"

  defp build_zkillboard_url(:character, id), do: "https://zkillboard.com/character/#{id}/"
  defp build_zkillboard_url(:corporation, id), do: "https://zkillboard.com/corporation/#{id}/"
  defp build_zkillboard_url(:alliance, id), do: "https://zkillboard.com/alliance/#{id}/"

  defp build_corp_field(%{corp: corp, corp_id: corp_id})
       when is_binary(corp) and is_integer(corp_id) and corp_id > 0 do
    %{
      name: "Attacker Corp",
      value: "[#{corp}](#{build_zkillboard_url(:corporation, corp_id)})",
      inline: true
    }
  end

  defp build_corp_field(%{corp: corp}) when is_binary(corp) do
    %{name: "Attacker Corp", value: corp, inline: true}
  end

  defp build_corp_field(_), do: nil

  defp build_alliance_field(%{alliance: alliance, alliance_id: alliance_id})
       when is_binary(alliance) and is_integer(alliance_id) and alliance_id > 0 do
    %{
      name: "Attacker Alliance",
      value: "[#{alliance}](#{build_zkillboard_url(:alliance, alliance_id)})",
      inline: true
    }
  end

  defp build_alliance_field(%{alliance: alliance}) when is_binary(alliance) do
    %{name: "Attacker Alliance", value: alliance, inline: true}
  end

  defp build_alliance_field(_), do: nil

  defp build_security_field(%{security_formatted: security})
       when is_binary(security) and security != "" and security != "Unknown" do
    %{name: "Security", value: security, inline: true}
  end

  defp build_security_field(%{security_formatted: _}), do: nil

  defp build_kill_notification(
         kill_id,
         kill_time,
         victim_info,
         kill_context,
         final_blow_details,
         _fields
       ) do
    title = "Ship destroyed in #{kill_context.system_name}"
    author_info = build_author_info(victim_info, kill_context)
    description = build_prose_description(victim_info, kill_context, final_blow_details)
    minimal_fields = build_minimal_fields(kill_context)

    %{
      type: :kill_notification,
      title: title,
      description: description,
      color: 0xD9534F,
      url: FormatterBase.zkillboard_killmail_url(kill_id),
      timestamp: kill_time,
      footer: FormatterBase.build_footer("Value: #{kill_context.formatted_value} ISK"),
      thumbnail: victim_info |> build_thumbnail_url() |> FormatterBase.build_thumbnail(),
      author: author_info,
      fields: minimal_fields,
      image: nil,
      victim: victim_info,
      kill_context: kill_context,
      final_blow: final_blow_details,
      kill_id: kill_id,
      kill_time: kill_time,
      system: %{
        name: kill_context.system_name,
        id: kill_context.system_id,
        security: kill_context.security_formatted
      },
      value: kill_context.formatted_value,
      attackers_count: kill_context.attackers_count,
      is_npc_kill: kill_context.is_npc_kill
    }
  end

  defp build_prose_description(victim_info, kill_context, final_blow_details) do
    victim_part = build_victim_description_part(victim_info)
    attacker_part = build_attacker_description_part(final_blow_details, kill_context)
    system_link = build_system_link(kill_context)

    base_description =
      "#{victim_part} lost their #{victim_info.ship} to #{attacker_part} in #{system_link}."

    notable_items = extract_notable_items(victim_info)

    if Enum.any?(notable_items) do
      items_text = format_notable_items(notable_items)
      "#{base_description}\n\n**Notable Items:**\n#{items_text}"
    else
      base_description
    end
  end

  defp build_victim_description_part(victim_info) do
    corp_display = format_corp_display(victim_info.corp, victim_info.corp_ticker)

    if victim_info.character_id do
      "[#{victim_info.name}](https://zkillboard.com/character/#{victim_info.character_id}/)(#{corp_display})"
    else
      "#{victim_info.name}(#{corp_display})"
    end
  end

  defp build_attacker_description_part(_final_blow_details, %{is_npc_kill: true}), do: "NPCs"

  defp build_attacker_description_part(
         %{character: character, corp: corp} = final_blow_details,
         kill_context
       )
       when is_binary(character) and character != "" and
              is_binary(corp) and corp not in ["", "Unknown Corp"] do
    attacker_name_part = build_attacker_name_part(final_blow_details)
    corp_part = build_attacker_corp_part(final_blow_details)
    ship_part = build_attacker_ship_part(final_blow_details, kill_context)

    [attacker_name_part, corp_part, ship_part]
    |> Enum.filter(&(&1 != ""))
    |> Enum.join(" ")
  end

  defp build_attacker_description_part(
         %{character: character, character_id: character_id},
         _kill_context
       )
       when is_binary(character) and character != "" and is_integer(character_id) do
    "[#{character}](https://zkillboard.com/character/#{character_id}/)"
  end

  defp build_attacker_description_part(%{character: character}, _kill_context)
       when is_binary(character) and character != "" do
    trimmed = String.trim(character)
    if trimmed != "", do: trimmed, else: nil
  end

  defp build_attacker_description_part(_final_blow_details, _kill_context), do: "Unknown attacker"

  defp build_attacker_name_part(final_blow_details) do
    if final_blow_details.character_id do
      "[#{final_blow_details.character}](https://zkillboard.com/character/#{final_blow_details.character_id}/)"
    else
      final_blow_details.character
    end
  end

  defp build_attacker_corp_part(final_blow_details) do
    corp_display =
      format_corp_display_with_link(
        final_blow_details.corp,
        final_blow_details.corp_ticker,
        final_blow_details.corp_id
      )

    alliance_display =
      format_alliance_display_with_link(
        final_blow_details.alliance,
        final_blow_details.alliance_ticker,
        final_blow_details.alliance_id
      )

    if alliance_display do
      "(#{corp_display} / #{alliance_display})"
    else
      "(#{corp_display})"
    end
  end

  defp build_attacker_ship_part(final_blow_details, kill_context) do
    ship_text =
      if final_blow_details.ship, do: " flying in a #{final_blow_details.ship}", else: ""

    attacker_count_text =
      case kill_context.attackers_count do
        1 -> " solo"
        count when count > 1 -> " (#{count} attackers)"
        _ -> ""
      end

    "#{ship_text}#{attacker_count_text}"
  end

  defp format_corp_display_with_link(corp, corp_ticker, corp_id) do
    display_name = get_corp_display_name(corp, corp_ticker)

    if corp_id && corp_id > 0 do
      "[#{display_name}](#{build_zkillboard_url(:corporation, corp_id)})"
    else
      display_name
    end
  end

  defp format_alliance_display_with_link(alliance, alliance_ticker, alliance_id) do
    if valid_alliance?(alliance) do
      display_name = get_alliance_display_name(alliance, alliance_ticker)
      format_alliance_link(display_name, alliance_id)
    else
      nil
    end
  end

  # Helper functions to reduce complexity
  defp get_corp_display_name(_corp, corp_ticker)
       when is_binary(corp_ticker) and corp_ticker != "" and corp_ticker != "Unknown" do
    corp_ticker
  end

  defp get_corp_display_name(corp, _corp_ticker)
       when is_binary(corp) and corp != "" and corp != "Unknown Corp" do
    corp
  end

  defp get_corp_display_name(_corp, _corp_ticker), do: "Unknown Corp"

  defp get_alliance_display_name(alliance, alliance_ticker) do
    if valid_ticker?(alliance_ticker) do
      alliance_ticker
    else
      alliance
    end
  end

  defp valid_alliance?(alliance) do
    not Utils.nil_or_empty?(alliance) and alliance not in ["Unknown", "Unknown Alliance"]
  end

  defp valid_ticker?(ticker) do
    not Utils.nil_or_empty?(ticker) and ticker != "Unknown"
  end

  defp format_alliance_link(display_name, alliance_id) do
    if alliance_id && alliance_id > 0 do
      "[#{display_name}](#{build_zkillboard_url(:alliance, alliance_id)})"
    else
      display_name
    end
  end

  defp format_corp_display(_corp, corp_ticker)
       when is_binary(corp_ticker) and corp_ticker != "" and corp_ticker != "Unknown" do
    corp_ticker
  end

  defp format_corp_display(corp, _corp_ticker)
       when is_binary(corp) and corp != "" and corp != "Unknown Corp" do
    corp
  end

  defp format_corp_display(_corp, _corp_ticker), do: "Unknown Corp"

  defp build_minimal_fields(_kill_context) do
    # Return empty fields array to use prose description instead
    []
  end

  defp build_author_info(victim_info, kill_context) do
    author_corp = get_author_corp(victim_info)
    author_name = get_author_name(victim_info, author_corp, kill_context)
    author_icon_url = get_author_icon_url(victim_info, author_corp)

    %{
      name: author_name,
      icon_url: author_icon_url
    }
  end

  defp get_author_corp(victim_info) do
    if is_binary(victim_info.corp_ticker) and victim_info.corp_ticker != "" do
      victim_info.corp_ticker
    else
      victim_info.corp
    end
  end

  defp get_author_name(victim_info, author_corp, kill_context) do
    if victim_info.name == "Unknown Pilot" and author_corp == "Unknown Corp" do
      "Kill in #{kill_context.system_name}"
    else
      "#{victim_info.name} [#{author_corp}]"
    end
  end

  defp get_author_icon_url(victim_info, author_corp) do
    if victim_info.name == "Unknown Pilot" and author_corp == "Unknown Corp" do
      "https://images.evetech.net/types/30_371/icon"
    else
      if victim_info.character_id do
        "https://imageserver.eveonline.com/Character/#{victim_info.character_id}_64.jpg"
      else
        nil
      end
    end
  end

  defp build_system_link(kill_context) do
    if kill_context.system_id do
      "[#{kill_context.system_name}](https://zkillboard.com/system/#{kill_context.system_id}/)"
    else
      kill_context.system_name
    end
  end

  defp build_thumbnail_url(victim_info) do
    if victim_info.ship_type_id do
      "https://images.evetech.net/types/#{victim_info.ship_type_id}/render"
    else
      nil
    end
  end

  defp format_isk_value(value) when is_number(value) and value >= 1_000_000_000 do
    "#{Float.round(value / 1_000_000_000, 2)}B"
  end

  defp format_isk_value(value) when is_number(value) and value >= 1_000_000 do
    "#{Float.round(value / 1_000_000, 2)}M"
  end

  defp format_isk_value(value) when is_number(value) and value >= 1_000 do
    "#{Float.round(value / 1_000, 2)}K"
  end

  defp format_isk_value(value) when is_number(value) do
    "#{Float.round(value, 0)}"
  end

  def format_description(killmail) do
    victim = killmail.esi_data["victim"]
    attackers = killmail.esi_data["attackers"]

    victim_name = victim["character_name"] || "Unknown"
    victim_corp = victim["corporation_name"] || "Unknown"
    attacker_name = List.first(attackers)["character_name"] || "Unknown"
    attacker_corp = List.first(attackers)["corporation_name"] || "Unknown"

    "#{victim_name} (#{victim_corp}) was killed by #{attacker_name} (#{attacker_corp})"
  end

  def format_victim(killmail) do
    victim = killmail.esi_data["victim"]
    victim_name = victim["character_name"] || "Unknown"
    victim_corp = victim["corporation_name"] || "Unknown"
    ship_name = victim["ship_type_name"] || "Unknown"

    "#{victim_name} (#{victim_corp}) flying a #{ship_name}"
  end

  defp format_fields(%Killmail{} = killmail) do
    [
      %{
        name: "Value",
        value: format_value(killmail),
        inline: true
      },
      %{
        name: "Victim",
        value: format_victim(killmail),
        inline: true
      }
    ]
  end

  defp format_value(%Killmail{} = killmail) do
    case killmail.zkb do
      %{"totalValue" => value} when is_number(value) ->
        :erlang.float_to_binary(value / 1_000_000, decimals: 2) <> "M ISK"

      _ ->
        "Unknown"
    end
  end

  defp extract_notable_items(victim_info) do
    # Get items from victim data if available
    victim_data = victim_info[:raw_victim_data] || %{}
    items = Map.get(victim_data, "items", [])

    items
    |> Enum.map(&enrich_item_data/1)
    |> Enum.filter(& &1.is_notable)
    # Limit to 3 notable items to keep message manageable
    |> Enum.take(3)
  end

  defp enrich_item_data(item) do
    type_id = Map.get(item, "type_id") || Map.get(item, "item_type_id")
    quantity = Map.get(item, "quantity_destroyed", 0) + Map.get(item, "quantity_dropped", 0)

    # Get item info from ESI with error handling
    item_info = get_item_info_safe(type_id)
    item_name = Map.get(item_info, "name", "Unknown Item")

    # Check for special item types
    is_abyssal =
      item_name
      |> String.downcase()
      |> String.contains?("abyssal")

    # Check if item is likely worth 50M+ ISK
    is_high_value = expensive_item?(type_id, item_name)

    # Notable if abyssal OR high value
    is_notable = is_abyssal or is_high_value

    %{
      type_id: type_id,
      name: item_name,
      quantity: quantity,
      is_notable: is_notable,
      is_abyssal: is_abyssal,
      is_high_value: is_high_value,
      category: get_item_category_simple(is_abyssal, is_high_value, item_name)
    }
  end

  defp get_item_info_safe(type_id) do
    case esi_service().get_type_info(type_id, []) do
      {:ok, info} when is_map(info) -> info
      _ -> %{"name" => "Unknown Item"}
    end
  rescue
    _ -> %{"name" => "Unknown Item"}
  end

  # Heuristic to identify items likely worth 50M+ ISK
  defp expensive_item?(type_id, item_name) when is_integer(type_id) do
    item_name_lower = String.downcase(item_name)

    # Check by item name patterns (high-value item types)
    name_indicators = [
      "deadspace",
      "officer",
      "x-type",
      "a-type",
      "b-type",
      "c-type"
    ]

    has_valuable_name =
      Enum.any?(name_indicators, fn indicator ->
        String.contains?(item_name_lower, indicator)
      end)

    has_valuable_name
  end

  defp expensive_item?(_, _), do: false

  defp get_item_category_simple(is_abyssal, is_high_value, item_name) do
    item_name_lower = String.downcase(item_name)

    cond do
      is_abyssal -> "Abyssal"
      String.contains?(item_name_lower, "officer") -> "Officer"
      String.contains?(item_name_lower, "deadspace") -> "Deadspace"
      is_high_value -> "High-Value"
      true -> "Notable"
    end
  end

  defp format_notable_items(notable_items) do
    notable_items
    |> Enum.map(&format_notable_item/1)
    |> Enum.join("\n")
  end

  defp format_notable_item(item) do
    quantity_text = if item.quantity > 1, do: " x#{item.quantity}", else: ""
    category_text = if item.category != "Notable", do: " [#{item.category}]", else: ""

    "• #{item.name}#{quantity_text}#{category_text}"
  end

  # System name resolution helper - prefer Map API over ESI for custom system names
  defp get_system_name_from_map_or_esi(system_id) do
    case System.get_system(system_id) do
      %{"name" => name} when is_binary(name) and name != "" ->
        name

      _not_found ->
        # Fallback to ESI for systems not in the map cache
        WandererNotifier.Domains.Killmail.Cache.get_system_name(system_id)
    end
  end

  # ESI service configuration
  defp esi_service, do: WandererNotifier.Application.Services.Dependencies.esi_service()
end
