defmodule WandererNotifier.Domains.Notifications.Formatters.NotificationFormatter do
  @moduledoc """
  Main notification formatter for all notification types.
  Consolidates killmail, character, and system formatting into a single module.
  """

  alias WandererNotifier.Domains.Killmail.Killmail
  alias WandererNotifier.Domains.Tracking.Entities.{Character, System}
  alias WandererNotifier.Domains.Notifications.Formatters.NotificationUtils, as: Utils
  require Logger

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
    # Build complete description with all information
    full_description = build_full_kill_description(killmail)

    %{
      type: :kill_notification,
      # No title to avoid duplication
      title: nil,
      description: full_description,
      color: Utils.get_color(:kill),
      url: Utils.zkillboard_url(killmail.killmail_id),
      # Keep corp icon with "Kill"
      author: build_kill_author_icon(killmail),
      thumbnail: build_kill_thumbnail(killmail),
      # No separate fields - everything in description
      fields: [],
      # No footer
      footer: nil,
      # No timestamp
      timestamp: nil
    }
  end

  defp build_kill_author_icon(%Killmail{} = killmail) do
    final_blow = get_final_blow_attacker(killmail.attackers)

    corp_id =
      if final_blow do
        Map.get(final_blow, "corporation_id")
      end

    if corp_id do
      %{
        name: "Kill",
        icon_url: Utils.corporation_logo_url(corp_id, 32),
        url: Utils.zkillboard_url(killmail.killmail_id)
      }
    else
      %{
        name: "Kill",
        url: Utils.zkillboard_url(killmail.killmail_id)
      }
    end
  end

  defp build_full_kill_description(%Killmail{} = killmail) do
    # System line
    system_name = killmail.system_name || "Unknown System"

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

    #{main_line}

    #{value_time_line}
    """
    |> String.trim()
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

  defp build_victim_description_part(%Killmail{} = killmail) do
    victim_name = killmail.victim_character_name || "Unknown pilot"
    victim_id = killmail.victim_character_id
    corp_id = killmail.victim_corporation_id
    ship_name = killmail.victim_ship_name || "ship"

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

    if final_blow do
      attacker_name = Map.get(final_blow, "character_name", "Unknown")
      attacker_id = Map.get(final_blow, "character_id")
      attacker_corp_id = Map.get(final_blow, "corporation_id")
      attacker_ship = Map.get(final_blow, "ship_name", "Unknown Ship")

      # Get corporation ticker
      attacker_ticker = get_attacker_corp_ticker(final_blow)

      # Create character link
      attacker_link =
        if attacker_id do
          "[#{attacker_name}](https://zkillboard.com/character/#{attacker_id}/)"
        else
          attacker_name
        end

      # Create corp ticker link
      attacker_corp_link =
        if attacker_corp_id do
          "[#{attacker_ticker}](https://zkillboard.com/corporation/#{attacker_corp_id}/)"
        else
          attacker_ticker
        end

      attacker_display = "#{attacker_link}(#{attacker_corp_link})"

      if attacker_count == 1 do
        "#{attacker_display} flying in a #{attacker_ship} solo."
      else
        top_damage = get_top_damage_attacker(killmail.attackers)

        top_damage_part =
          if top_damage && top_damage != final_blow do
            top_name = Map.get(top_damage, "character_name", "Unknown")
            top_id = Map.get(top_damage, "character_id")
            top_corp_id = Map.get(top_damage, "corporation_id")
            top_ship = Map.get(top_damage, "ship_name", "Unknown Ship")
            top_ticker = get_attacker_corp_ticker(top_damage)

            # Create character link
            top_link =
              if top_id do
                "[#{top_name}](https://zkillboard.com/character/#{top_id}/)"
              else
                top_name
              end

            # Create corp ticker link
            top_corp_link =
              if top_corp_id do
                "[#{top_ticker}](https://zkillboard.com/corporation/#{top_corp_id}/)"
              else
                top_ticker
              end

            ", Top Damage was done by #{top_link}(#{top_corp_link}) flying in a #{top_ship}"
          else
            ""
          end

        others_count = attacker_count - 1

        "#{attacker_display} flying in a #{attacker_ship}#{top_damage_part} and #{others_count} others"
      end
    else
      "unknown attackers"
    end
  end

  defp get_top_damage_attacker(nil), do: nil
  defp get_top_damage_attacker([]), do: nil

  defp get_top_damage_attacker(attackers) do
    Enum.max_by(attackers, fn att -> Map.get(att, "damage_done", 0) end, fn -> nil end)
  end

  defp get_corp_ticker_from_killmail(%Killmail{} = killmail, "victim") do
    case killmail.victim_corporation_id do
      nil ->
        "NONE"

      corp_id ->
        # Try to get ticker from ESI
        case get_corp_ticker_from_esi(corp_id) do
          {:ok, ticker} ->
            ticker

          _ ->
            # Fallback to abbreviated corp name
            case killmail.victim_corporation_name do
              nil ->
                "CORP"

              name ->
                # Try to extract a reasonable ticker from the name
                create_ticker_from_name(name)
            end
        end
    end
  end

  defp get_attacker_corp_ticker(attacker) do
    # First check if we have a ticker in the attacker data
    ticker = Map.get(attacker, "corporation_ticker") || Map.get(attacker, "ticker")

    if ticker do
      ticker
    else
      case Map.get(attacker, "corporation_id") do
        nil ->
          "NONE"

        corp_id ->
          # Try to get ticker from ESI
          case get_corp_ticker_from_esi(corp_id) do
            {:ok, ticker} ->
              ticker

            _ ->
              # Fallback to creating ticker from name
              case Map.get(attacker, "corporation_name") do
                nil -> "CORP"
                name -> create_ticker_from_name(name)
              end
          end
      end
    end
  end

  defp get_corp_ticker_from_esi(corp_id) do
    # Check cache first
    cache_key = "esi:corporation:#{corp_id}:ticker"

    case WandererNotifier.Infrastructure.Cache.get(cache_key) do
      {:ok, ticker} ->
        {:ok, ticker}

      _ ->
        # Fetch from ESI
        case WandererNotifier.Infrastructure.Adapters.ESI.Service.get_corporation_info(corp_id) do
          {:ok, %{"ticker" => ticker}} when is_binary(ticker) ->
            # Cache for 24 hours
            WandererNotifier.Infrastructure.Cache.put(cache_key, ticker, :timer.hours(24))
            {:ok, ticker}

          _ ->
            {:error, :not_found}
        end
    end
  end

  defp create_ticker_from_name(name) do
    # Create a ticker from corporation name
    # Examples: "Goonswarm Federation" -> "GOONF", "Pandemic Horde" -> "HORDE"
    words = String.split(name, " ")

    case length(words) do
      1 ->
        # Single word - take first 5 chars
        String.slice(name, 0, 5) |> String.upcase()

      _ ->
        # Multiple words - try to create an acronym
        acronym =
          words
          |> Enum.map(&String.first/1)
          |> Enum.join("")
          |> String.upcase()

        if String.length(acronym) <= 5 do
          acronym
        else
          # Too long, just use first 5 chars of name
          String.slice(name, 0, 5) |> String.upcase()
        end
    end
  end

  defp format_timestamp(%Killmail{kill_time: kill_time}) when is_binary(kill_time) do
    # Format timestamp as "Today at 5:12 PM" style
    # For now, just return a simple format
    "Today at #{format_time_from_iso(kill_time)}"
  end

  defp format_timestamp(_), do: "Recently"

  defp format_time_from_iso(iso_time) do
    # Simple time extraction - in production would use proper date parsing
    case String.split(iso_time, "T") do
      [_date, time_part] ->
        case String.split(time_part, ":") do
          [hour_str, minute_str | _] ->
            hour = String.to_integer(hour_str)

            {display_hour, period} =
              if hour >= 12 do
                {if(hour > 12, do: hour - 12, else: hour), "PM"}
              else
                {if(hour == 0, do: 12, else: hour), "AM"}
              end

            "#{display_hour}:#{minute_str} #{period}"

          _ ->
            "Unknown time"
        end

      _ ->
        "Unknown time"
    end
  end

  defp get_final_blow_attacker(nil), do: nil
  defp get_final_blow_attacker([]), do: nil

  defp get_final_blow_attacker(attackers) do
    Enum.find(attackers, fn att -> Map.get(att, "final_blow") == true end) ||
      Enum.max_by(attackers, fn att -> Map.get(att, "damage_done", 0) end, fn -> nil end)
  end

  # ═══════════════════════════════════════════════════════════════════════════════
  # Character Notifications
  # ═══════════════════════════════════════════════════════════════════════════════

  defp format_character_notification(%Character{} = character) do
    # Convert character_id to integer for portrait URL
    character_id_int =
      case character.character_id do
        id when is_integer(id) -> id
        id when is_binary(id) -> String.to_integer(id)
        _ -> nil
      end

    %{
      type: :character_notification,
      title: "New Character Tracked: #{character.name}",
      description: build_character_description(character),
      color: Utils.get_color(:character),
      url: character_id_int && "https://zkillboard.com/character/#{character_id_int}/",
      thumbnail:
        character_id_int &&
          Utils.character_portrait_url(character_id_int) |> Utils.build_thumbnail(),
      fields: build_character_fields(character),
      footer: Utils.build_footer("Character ID: #{character.character_id}")
    }
  end

  defp build_character_description(%Character{}) do
    # Simple description without showing tickers since they appear in the fields
    "A new character has been added to tracking."
  end

  defp build_character_fields(%Character{} = character) do
    []
    |> add_character_field(character)
    |> add_corporation_field(character)
    |> add_alliance_field(character)
    |> Enum.reverse()
  end

  defp add_character_field(fields, %Character{} = character) do
    character_id_int = normalize_character_id(character.character_id)
    char_link = Utils.create_character_link(character.name, character_id_int)
    [Utils.build_field("Character", char_link, true) | fields]
  end

  defp add_corporation_field(fields, %Character{corporation_id: nil}), do: fields

  defp add_corporation_field(fields, %Character{} = character) do
    corp_name = get_corporation_name(character)
    corp_link = Utils.create_corporation_link(corp_name, character.corporation_id)
    [Utils.build_field("Corporation", corp_link, true) | fields]
  end

  defp add_alliance_field(fields, %Character{alliance_id: nil}), do: fields

  defp add_alliance_field(fields, %Character{} = character) do
    alliance_name = get_alliance_name(character)
    alliance_link = Utils.create_alliance_link(alliance_name, character.alliance_id)
    [Utils.build_field("Alliance", alliance_link, true) | fields]
  end

  defp normalize_character_id(id) when is_integer(id), do: id
  defp normalize_character_id(id) when is_binary(id), do: String.to_integer(id)
  defp normalize_character_id(_), do: nil

  # Helper functions to get corporation and alliance names from character data
  defp get_corporation_name(%Character{} = character) do
    # For character notifications, we want to use ticker as the primary name since
    # we don't have full corp names in the character tracking data
    character.corporation_ticker || "Unknown Corporation"
  end

  defp get_alliance_name(%Character{} = character) do
    # For character notifications, we want to use ticker as the primary name since  
    # we don't have full alliance names in the character tracking data
    character.alliance_ticker || "Unknown Alliance"
  end

  # ═══════════════════════════════════════════════════════════════════════════════
  # System Notifications
  # ═══════════════════════════════════════════════════════════════════════════════

  defp format_system_notification(%System{} = system) do
    is_wormhole = System.wormhole?(system)

    # Log system data for debugging
    Logger.info("[Formatter] Formatting system notification",
      system_name: system.name,
      system_type: system.system_type,
      is_wormhole: is_wormhole,
      statics: inspect(system.statics),
      class_title: system.class_title,
      category: :notification
    )

    # Helper functions to handle potentially nil values
    system_name = Map.get(system, :name, "Unknown")
    system_id = Map.get(system, :solar_system_id, "Unknown")

    %{
      type: :system_notification,
      title: "New System Tracked: #{system_name}",
      description: build_system_description(system, is_wormhole),
      color:
        determine_system_color(system, is_wormhole)
        |> Utils.get_color(),
      thumbnail:
        determine_system_icon(system, is_wormhole)
        |> Utils.get_system_icon()
        |> Utils.build_thumbnail(),
      fields: build_system_fields(system, is_wormhole),
      footer: Utils.build_footer("System ID: #{system_id}")
    }
  end

  defp build_system_description(%System{} = system, is_wormhole) do
    cond do
      is_wormhole && system.class_title ->
        "A new wormhole system (#{system.class_title}) has been added to tracking."

      is_wormhole && system.type_description ->
        "A new #{system.type_description} wormhole system has been added to tracking."

      is_wormhole ->
        "A new wormhole system has been added to tracking."

      system.type_description ->
        "A new #{system.type_description} system has been added to tracking."

      true ->
        "A new system has been added to tracking."
    end
  end

  defp build_system_fields(%System{} = system, is_wormhole) do
    fields =
      []
      |> add_system_field(system)
      |> add_class_field(system, is_wormhole)
      |> add_shattered_field(system, is_wormhole)
      |> add_statics_field(system, is_wormhole)
      |> add_region_field(system)
      |> add_effect_field(system, is_wormhole)
      |> add_recent_kills_field(system)
      |> Enum.reverse()

    # Log fields for debugging
    Logger.debug("System fields built",
      fields_count: length(fields),
      fields: inspect(fields),
      statics: inspect(system.statics),
      category: :notification
    )

    fields
  end

  defp add_system_field(fields, system) do
    system_link = Utils.create_system_link(system.name, system.solar_system_id)
    [Utils.build_field("System", system_link, true) | fields]
  end

  defp add_class_field(fields, system, is_wormhole) do
    if is_wormhole && system.class_title do
      [Utils.build_field("Class", system.class_title, true) | fields]
    else
      fields
    end
  end

  defp add_shattered_field(fields, system, is_wormhole) do
    if is_wormhole && system.is_shattered do
      [Utils.build_field("Shattered", "Yes", true) | fields]
    else
      fields
    end
  end

  defp add_statics_field(fields, system, is_wormhole) do
    Logger.info(
      "[Formatter] add_statics_field - is_wormhole: #{is_wormhole}, statics: #{inspect(system.statics)}"
    )

    if is_wormhole && system.statics && length(system.statics) > 0 do
      statics_text = format_statics(system.statics)
      Logger.info("[Formatter] Adding statics field with text: #{statics_text}")
      [Utils.build_field("Static Wormholes", statics_text, true) | fields]
    else
      Logger.info("[Formatter] Not adding statics field - conditions not met")
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
    # If we have enriched static data with destinations, format it nicely
    statics
    |> Enum.map(fn
      %{"name" => name, "destination" => %{"short_name" => dest}} ->
        "#{name} → #{dest}"

      %{"name" => name} ->
        name

      static when is_binary(static) ->
        static

      _ ->
        "Unknown"
    end)
    |> Enum.join(", ")
  end

  defp format_statics(_), do: "N/A"

  defp add_recent_kills_field(fields, system) do
    # Try to get recent kills for the system
    case WandererNotifier.Domains.Killmail.Enrichment.recent_kills_for_system(
           system.solar_system_id,
           3
         ) do
      kills when is_binary(kills) and kills != "" and kills != "No recent kills found" ->
        [Utils.build_field("Recent Kills", kills, false) | fields]

      _ ->
        fields
    end
  rescue
    _ -> fields
  end

  defp determine_system_color(system, is_wormhole) do
    cond do
      is_wormhole -> :wormhole
      is_nil(system.security_status) -> :default
      system.security_status >= 0.5 -> :highsec
      system.security_status > 0.0 -> :lowsec
      system.security_status == 0.0 -> :nullsec
      true -> :default
    end
  end

  defp determine_system_icon(system, is_wormhole) do
    cond do
      is_wormhole -> :wormhole
      system.type_description -> icon_from_type_description(system.type_description)
      is_nil(system.security_status) -> :wormhole
      true -> icon_from_security_status(system.security_status)
    end
  end

  defp icon_from_type_description("High-sec"), do: :highsec
  defp icon_from_type_description("Low-sec"), do: :lowsec
  defp icon_from_type_description("Null-sec"), do: :nullsec
  defp icon_from_type_description(_), do: :wormhole

  defp icon_from_security_status(security) when security >= 0.5, do: :highsec
  defp icon_from_security_status(security) when security > 0.0, do: :lowsec
  defp icon_from_security_status(+0.0), do: :nullsec
  defp icon_from_security_status(_), do: :wormhole

  # ═══════════════════════════════════════════════════════════════════════════════
  # Plain Text Formatting
  # ═══════════════════════════════════════════════════════════════════════════════

  @doc """
  Format notification as plain text for fallback scenarios.
  """
  def format_plain_text(%{type: :kill_notification} = notification) do
    main_text =
      case notification.fields do
        [%{value: main_desc} | _] -> main_desc
        _ -> ""
      end

    value_text =
      case get_field_value(notification.fields, "Value") do
        "" -> ""
        value -> "\nValue: #{value}"
      end

    """
    #{notification.title}
    #{notification.description}
    #{main_text}#{value_text}
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
