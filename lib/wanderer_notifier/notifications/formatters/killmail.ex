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

  defp log_killmail_data(killmail) do
    AppLogger.processor_debug(
      "[KillmailFormatter] Formatting killmail: #{inspect(killmail, limit: 200)}"
    )
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
      character_id: victim_character_id
    }
  end

  defp extract_kill_context(killmail) do
    system_name =
      killmail.system_name ||
        Map.get(killmail.esi_data || %{}, "solar_system_name", "Unknown System")

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
        get_attacker_value(attacker, :final_blow) in [true, "true"]
      end)

    is_npc_kill = Map.get(zkb, "npc", false) == true
    extract_final_blow_details(final_blow_attacker, is_npc_kill)
  end

  defp extract_final_blow_details(nil, true), do: %{text: "NPC", icon_url: nil}
  defp extract_final_blow_details(nil, _), do: %{text: "Unknown", icon_url: nil}

  defp extract_final_blow_details(attacker, _) do
    base_details = build_base_attacker_details(attacker)
    details_with_corp = add_corp_details(base_details, attacker)
    details_with_alliance = add_alliance_details(details_with_corp, attacker)
    add_character_link(details_with_alliance, attacker)
  end

  defp build_base_attacker_details(attacker) do
    character_id = get_attacker_value(attacker, :character_id)
    character_name = get_attacker_value(attacker, :character_name) || "Unknown"

    ship_name =
      get_attacker_value(attacker, :ship_name) || get_attacker_value(attacker, :ship_type_name) ||
        "Unknown Ship"

    %{
      text: "#{character_name} (#{ship_name})",
      icon_url:
        if(character_id,
          do: "https://imageserver.eveonline.com/Character/#{character_id}_64.jpg",
          else: nil
        ),
      name: character_name,
      ship: ship_name,
      character_id: character_id
    }
  end

  defp get_attacker_value(attacker, key) do
    Map.get(attacker, key) || Map.get(attacker, to_string(key))
  end

  defp add_corp_details(details, attacker) do
    corp = get_attacker_value(attacker, :corporation_name)
    corp_id = get_attacker_value(attacker, :corporation_id)
    corp_ticker = get_attacker_value(attacker, :corporation_ticker)

    details
    |> add_corp_ticker(corp_ticker, corp_id)
    |> add_corp_name(corp)
    |> add_corp_id(corp_id)
  end

  defp add_corp_ticker(details, ticker, corp_id)
       when not is_nil(ticker) and not is_nil(corp_id) do
    Map.put(details, :corp_ticker, "[#{ticker}](https://zkillboard.com/corporation/#{corp_id}/)")
  end

  defp add_corp_ticker(details, _, _), do: details

  defp add_corp_name(details, corp) when not is_nil(corp), do: Map.put(details, :corp, corp)
  defp add_corp_name(details, _), do: details

  defp add_corp_id(details, corp_id) when not is_nil(corp_id),
    do: Map.put(details, :corp_id, corp_id)

  defp add_corp_id(details, _), do: details

  defp add_alliance_details(details, attacker) do
    alliance = get_attacker_value(attacker, :alliance_name)
    alliance_id = get_attacker_value(attacker, :alliance_id)
    alliance_ticker = get_attacker_value(attacker, :alliance_ticker)

    details
    |> add_alliance_ticker(alliance_ticker, alliance_id)
    |> add_alliance_name(alliance)
    |> add_alliance_id(alliance_id)
  end

  defp add_alliance_ticker(details, ticker, alliance_id)
       when not is_nil(ticker) and not is_nil(alliance_id) do
    Map.put(
      details,
      :alliance_ticker,
      "[#{ticker}](https://zkillboard.com/alliance/#{alliance_id}/)"
    )
  end

  defp add_alliance_ticker(details, _, _), do: details

  defp add_alliance_name(details, alliance) when not is_nil(alliance),
    do: Map.put(details, :alliance, alliance)

  defp add_alliance_name(details, _), do: details

  defp add_alliance_id(details, alliance_id) when not is_nil(alliance_id),
    do: Map.put(details, :alliance_id, alliance_id)

  defp add_alliance_id(details, _), do: details

  defp add_character_link(details, attacker) do
    if details.character_id do
      char_link = "[#{details.name}](https://zkillboard.com/character/#{details.character_id}/)"

      ship_type_id =
        get_attacker_value(attacker, :ship_id) || get_attacker_value(attacker, :ship_type_id)

      ship_link =
        "[#{details.ship}](https://zkillboard.com/ship/#{ship_type_id}/)"

      %{details | text: "#{char_link} (#{ship_link})"}
    else
      details
    end
  end

  defp build_kill_notification_fields(_victim_info, kill_context, final_blow_details) do
    base_fields = build_base_fields(kill_context, final_blow_details)
    corp_field = build_corp_field(final_blow_details)
    alliance_field = build_alliance_field(final_blow_details)

    fields = base_fields
    fields = if corp_field, do: fields ++ [corp_field], else: fields
    fields = if alliance_field, do: fields ++ [alliance_field], else: fields
    fields
  end

  defp build_base_fields(kill_context, final_blow_details) do
    [
      %{name: "Value", value: kill_context.formatted_value, inline: true},
      %{name: "Attackers", value: "#{kill_context.attackers_count}", inline: true},
      %{name: "Final Blow", value: final_blow_details.text, inline: true}
    ]
  end

  defp build_corp_field(%{corp_ticker: ticker}) when not is_nil(ticker) do
    %{name: "Attacker Corp", value: ticker, inline: true}
  end

  defp build_corp_field(%{corp: corp, corp_id: corp_id})
       when not is_nil(corp) and not is_nil(corp_id) do
    %{
      name: "Attacker Corp",
      value: "[#{corp}](https://zkillboard.com/corporation/#{corp_id}/)",
      inline: true
    }
  end

  defp build_corp_field(%{corp: corp}) when not is_nil(corp) do
    %{name: "Attacker Corp", value: corp, inline: true}
  end

  defp build_corp_field(_), do: nil

  defp build_alliance_field(%{alliance_ticker: ticker}) when not is_nil(ticker) do
    %{name: "Attacker Alliance", value: ticker, inline: true}
  end

  defp build_alliance_field(%{alliance: alliance, alliance_id: alliance_id})
       when not is_nil(alliance) and not is_nil(alliance_id) do
    %{
      name: "Attacker Alliance",
      value: "[#{alliance}](https://zkillboard.com/alliance/#{alliance_id}/)",
      inline: true
    }
  end

  defp build_alliance_field(%{alliance: alliance}) when not is_nil(alliance) do
    %{name: "Attacker Alliance", value: alliance, inline: true}
  end

  defp build_alliance_field(_), do: nil

  defp build_kill_notification(
         kill_id,
         kill_time,
         victim_info,
         kill_context,
         final_blow_details,
         fields
       ) do
    title = "Kill Notification: #{victim_info.name}"
    author_info = build_author_info(victim_info, kill_context)
    system_with_link = build_system_link(kill_context)
    description = build_description(victim_info, system_with_link)
    updated_fields = update_final_blow_field(fields, final_blow_details)

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
        url: build_thumbnail_url(victim_info)
      },
      author: author_info,
      fields: updated_fields
    }
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

  defp build_description(victim_info, system_with_link) do
    "[#{victim_info.name}](https://zkillboard.com/character/#{victim_info.character_id}/) lost a #{victim_info.ship} in #{system_with_link}"
  end

  defp build_thumbnail_url(victim_info) do
    if victim_info.ship_type_id do
      "https://images.evetech.net/types/#{victim_info.ship_type_id}/render"
    else
      nil
    end
  end

  defp update_final_blow_field(fields, final_blow_details) do
    Enum.map(fields, fn
      %{name: "Final Blow"} = field ->
        if final_blow_details[:character_id] do
          char_link =
            "[#{final_blow_details[:name]}](https://zkillboard.com/character/#{final_blow_details[:character_id]}/)"

          %{field | value: "#{char_link} (#{final_blow_details[:ship]})"}
        else
          field
        end

      other ->
        other
    end)
  end

  defp format_isk_value(value) when is_number(value) do
    cond do
      value >= 1_000_000_000 -> "#{Float.round(value / 1_000_000_000, 1)}B"
      value >= 1_000_000 -> "#{Float.round(value / 1_000_000, 1)}M"
      value >= 1_000 -> "#{Float.round(value / 1_000, 1)}K"
      true -> "#{Float.round(value, 0)}"
    end
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
end
