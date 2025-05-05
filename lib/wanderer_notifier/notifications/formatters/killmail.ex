defmodule WandererNotifier.Notifications.Formatters.Killmail do
  @moduledoc """
  Killmail notification formatting utilities for Discord notifications.
  Provides rich formatting for killmail events.
  """

  alias WandererNotifier.Killmail.Killmail
  alias WandererNotifier.Logger.Logger, as: AppLogger

  @error_color 0xD9534F

  @doc """
  Creates a standard formatted kill notification embed/attachment from a Killmail struct.
  Returns data in a generic format that can be converted to platform-specific format.
  """
  def format_kill_notification(%Killmail{} = killmail) do
    log_killmail_data(killmail)

    kill_id = killmail.killmail_id
    kill_time = Map.get(killmail.esi_data || %{}, "killmail_time")
    victim_info = extract_victim_info(killmail)
    kill_context = extract_kill_context(killmail)
    final_blow_details = get_final_blow_details(killmail)
    fields = build_kill_notification_fields(victim_info, kill_context, final_blow_details)

    build_kill_notification(
      kill_id,
      kill_time,
      victim_info,
      kill_context,
      final_blow_details,
      fields
    )
  end

  defp log_killmail_data(killmail) do
    AppLogger.processor_debug(
      "[KillmailFormatter] Formatting killmail: #{inspect(killmail, limit: 200)}"
    )
  end

  defp extract_victim_info(killmail) do
    victim = Killmail.get_victim(killmail) || %{}

    victim_name = killmail.victim_name || Map.get(victim, "character_name", "Unknown Pilot")
    victim_ship = killmail.ship_name || Map.get(victim, "ship_type_name", "Unknown Ship")
    victim_corp = killmail.victim_corporation || Map.get(victim, "corporation_name", "Unknown Corp")
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
      character_id: victim_character_id
    }
  end

  defp extract_kill_context(killmail) do
    system_name = killmail.system_name || Map.get(killmail.esi_data || %{}, "solar_system_name", "Unknown System")
    system_id = killmail.system_id || Map.get(killmail.esi_data || %{}, "solar_system_id")

    security_status = get_system_security_status(system_id)
    security_formatted = format_security_status(security_status)

    zkb = killmail.zkb || %{}
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

  defp format_security_status(security_status) when is_float(security_status) do
    cond do
      security_status >= 0.5 -> "High Sec"
      security_status > 0.0 -> "Low Sec"
      true -> "Null Sec"
    end
  end
  defp format_security_status(_), do: "Unknown"

  defp get_final_blow_details(killmail) do
    # Prefer enriched attackers if available
    attackers = killmail.attackers || Map.get(killmail.esi_data || %{}, "attackers", [])
    zkb = killmail.zkb || %{}
    final_blow_attacker =
      Enum.find(attackers, fn attacker ->
        (Map.get(attacker, "final_blow") in [true, "true"]) or (attacker[:final_blow] == true)
      end)
    is_npc_kill = Map.get(zkb, "npc", false) == true
    extract_final_blow_details(final_blow_attacker, is_npc_kill)
  end

  defp extract_final_blow_details(nil, true), do: %{text: "NPC", icon_url: nil}
  defp extract_final_blow_details(nil, _), do: %{text: "Unknown", icon_url: nil}
  defp extract_final_blow_details(attacker, _) do
    character_id = Map.get(attacker, :character_id) || Map.get(attacker, "character_id")
    character_name = Map.get(attacker, :character_name) || Map.get(attacker, "character_name") || "Unknown"
    ship_name = Map.get(attacker, :ship_type_name) || Map.get(attacker, "ship_type_name") || "Unknown Ship"
    corp = Map.get(attacker, :corporation_name) || Map.get(attacker, "corporation_name")
    corp_id = Map.get(attacker, :corporation_id) || Map.get(attacker, "corporation_id")
    corp_ticker = Map.get(attacker, :corporation_ticker) || Map.get(attacker, "corporation_ticker")
    alliance = Map.get(attacker, :alliance_name) || Map.get(attacker, "alliance_name")
    alliance_id = Map.get(attacker, :alliance_id) || Map.get(attacker, "alliance_id")
    alliance_ticker = Map.get(attacker, :alliance_ticker) || Map.get(attacker, "alliance_ticker")
    # Build zKillboard link for attacker
    if character_id do
      text = "[#{character_name}](https://zkillboard.com/character/#{character_id}/) ([#{ship_name}](https://zkillboard.com/ship/#{Map.get(attacker, :ship_type_id) || Map.get(attacker, "ship_type_id")}/))"
      icon_url = "https://imageserver.eveonline.com/Character/#{character_id}_64.jpg"
      details = %{text: text, icon_url: icon_url, character_id: character_id, name: character_name, ship: ship_name}
      details = if corp_ticker && corp_id, do: Map.put(details, :corp_ticker, "[#{corp_ticker}](https://zkillboard.com/corporation/#{corp_id}/)"), else: details
      details = if corp, do: Map.put(details, :corp, corp), else: details
      details = if corp_id, do: Map.put(details, :corp_id, corp_id), else: details
      details = if alliance_ticker && alliance_id, do: Map.put(details, :alliance_ticker, "[#{alliance_ticker}](https://zkillboard.com/alliance/#{alliance_id}/)"), else: details
      details = if alliance, do: Map.put(details, :alliance, alliance), else: details
      details = if alliance_id, do: Map.put(details, :alliance_id, alliance_id), else: details
      details
    else
      details = %{text: "#{character_name} (#{ship_name})", icon_url: nil, name: character_name, ship: ship_name}
      details = if corp_ticker && corp_id, do: Map.put(details, :corp_ticker, "[#{corp_ticker}](https://zkillboard.com/corporation/#{corp_id}/)"), else: details
      details = if corp, do: Map.put(details, :corp, corp), else: details
      details = if corp_id, do: Map.put(details, :corp_id, corp_id), else: details
      details = if alliance_ticker && alliance_id, do: Map.put(details, :alliance_ticker, "[#{alliance_ticker}](https://zkillboard.com/alliance/#{alliance_id}/)"), else: details
      details = if alliance, do: Map.put(details, :alliance, alliance), else: details
      details = if alliance_id, do: Map.put(details, :alliance_id, alliance_id), else: details
      details
    end
  end

  defp build_kill_notification_fields(_victim_info, kill_context, final_blow_details) do
    base_fields = [
      %{name: "Value", value: kill_context.formatted_value, inline: true},
      %{name: "Attackers", value: "#{kill_context.attackers_count}", inline: true},
      %{name: "Final Blow", value: final_blow_details.text, inline: true}
    ]

    # Attacker Corp field
    corp_field =
      cond do
        final_blow_details[:corp_ticker] ->
          %{name: "Attacker Corp", value: final_blow_details.corp_ticker, inline: true}
        final_blow_details[:corp] && final_blow_details[:corp_id] ->
          %{name: "Attacker Corp", value: "[#{final_blow_details.corp}](https://zkillboard.com/corporation/#{final_blow_details.corp_id}/)", inline: true}
        final_blow_details[:corp] ->
          %{name: "Attacker Corp", value: final_blow_details.corp, inline: true}
        true -> nil
      end

    # Attacker Alliance field
    alliance_field =
      cond do
        final_blow_details[:alliance_ticker] ->
          %{name: "Attacker Alliance", value: final_blow_details.alliance_ticker, inline: true}
        final_blow_details[:alliance] && final_blow_details[:alliance_id] ->
          %{name: "Attacker Alliance", value: "[#{final_blow_details.alliance}](https://zkillboard.com/alliance/#{final_blow_details.alliance_id}/)", inline: true}
        final_blow_details[:alliance] ->
          %{name: "Attacker Alliance", value: final_blow_details.alliance, inline: true}
        true -> nil
      end

    fields = base_fields
    fields = if corp_field, do: fields ++ [corp_field], else: fields
    fields = if alliance_field, do: fields ++ [alliance_field], else: fields
    fields
  end

  defp build_kill_notification(
         kill_id,
         kill_time,
         victim_info,
         kill_context,
         final_blow_details,
         fields
       ) do

    title = "Kill Notification: #{victim_info.name}"
    # Use ticker if present, otherwise full corp name
    author_corp =
      cond do
        is_binary(victim_info.corp_ticker) and victim_info.corp_ticker != "" -> victim_info.corp_ticker
        true -> victim_info.corp
      end
    author_name =
      if victim_info.name == "Unknown Pilot" and author_corp == "Unknown Corp" do
        "Kill in #{kill_context.system_name}"
      else
        "#{victim_info.name} [#{author_corp}]"
      end
    author_icon_url =
      if victim_info.name == "Unknown Pilot" and author_corp == "Unknown Corp" do
        "https://images.evetech.net/types/30_371/icon"
      else
        if victim_info.character_id do
          "https://imageserver.eveonline.com/Character/#{victim_info.character_id}_64.jpg"
        else
          nil
        end
      end
    thumbnail_url =
      if victim_info.ship_type_id do
        "https://images.evetech.net/types/#{victim_info.ship_type_id}/render"
      else
        nil
      end
    system_with_link =
      if kill_context.system_id do
        "[#{kill_context.system_name}](https://zkillboard.com/system/#{kill_context.system_id}/)"
      else
        kill_context.system_name
      end
    description = "[#{victim_info.name}](https://zkillboard.com/character/#{victim_info.character_id}/) lost a #{victim_info.ship} in #{system_with_link}"
    # Update Final Blow field in fields
    updated_fields = Enum.map(fields, fn
      %{name: "Final Blow"} = field ->
        # If final_blow_details has character_id, make it a link
        if final_blow_details[:character_id] do
          char_link = "[#{final_blow_details[:name]}](https://zkillboard.com/character/#{final_blow_details[:character_id]}/)"
          %{field | value: "#{char_link} (#{final_blow_details[:ship]})"}
        else
          field
        end
      other -> other
    end)
    %{
      type: :kill_notification,
      title: title,
      description: description,
      color: @error_color,
      url: "https://zkillboard.com/kill/#{kill_id}/",
      timestamp: kill_time,
      footer: %{
        text: "Kill ID: #{kill_id}"
      },
      thumbnail: %{
        url: thumbnail_url
      },
      author: %{
        name: author_name,
        icon_url: author_icon_url
      },
      fields: updated_fields
    }
  end

  defp format_isk_value(value) when is_number(value) do
    cond do
      value >= 1_000_000_000 -> "#{Float.round(value / 1_000_000_000, 1)}B"
      value >= 1_000_000 -> "#{Float.round(value / 1_000_000, 1)}M"
      value >= 1_000 -> "#{Float.round(value / 1_000, 1)}K"
      true -> "#{Float.round(value, 0)}"
    end
  end
end
