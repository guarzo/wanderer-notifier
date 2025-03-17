defmodule WandererNotifier.Discord.Notifier do
  @moduledoc """
  Discord notification service.
  Handles sending notifications to Discord.
  """
  require Logger
  alias WandererNotifier.Http.Client, as: HttpClient
  alias WandererNotifier.Helpers.NotificationHelpers

  @behaviour WandererNotifier.NotifierBehaviour

  # Default embed colors
  @default_embed_color 0x3498DB
  @wormhole_color 0x428BCA  # Blue for Pulsar
  @highsec_color 0x5CB85C   # Green for highsec
  @lowsec_color 0xE28A0D    # Yellow/orange for lowsec
  @nullsec_color 0xD9534F   # Red for nullsec

  @base_url "https://discord.com/api/channels"
  @verbose_logging false  # Set to true to enable verbose logging

  @callback send_message(String.t()) :: :ok | {:error, any()}
  @callback send_embed(String.t(), String.t(), any(), integer()) :: :ok | {:error, any()}

  # -- ENVIRONMENT AND CONFIGURATION HELPERS --

  # Use runtime configuration so tests can override it
  defp env, do: Application.get_env(:wanderer_notifier, :env, :prod)

  defp get_config!(key, error_msg) do
    environment = env()
    case Application.get_env(:wanderer_notifier, key) do
      nil when environment != :test -> raise error_msg
      "" when environment != :test -> raise error_msg
      value -> value
    end
  end

  defp channel_id,
    do: get_config!(:discord_channel_id, "Discord channel ID not configured. Please set :discord_channel_id in your configuration.")

  defp bot_token,
    do: get_config!(:discord_bot_token, "Discord bot token not configured. Please set :discord_bot_token in your configuration.")

  defp build_url, do: "#{@base_url}/#{channel_id()}/messages"

  defp headers do
    [
      {"Content-Type", "application/json"},
      {"Authorization", "Bot #{bot_token()}"}
    ]
  end

  # -- MESSAGE SENDING --

  @doc """
  Sends a plain text message to Discord.
  """
  @impl WandererNotifier.NotifierBehaviour
  def send_message(message) when is_binary(message) do
    if env() == :test do
      if @verbose_logging, do: Logger.info("DISCORD MOCK: #{message}")
      :ok
    else
      payload =
        if String.contains?(message, "test kill notification") do
          process_test_kill_notification(message)
        else
          %{"content" => message, "embeds" => []}
        end

      send_payload(payload)
    end
  end

  defp process_test_kill_notification(message) do
    recent_kills = WandererNotifier.Service.KillProcessor.get_recent_kills() || []

    if recent_kills != [] do
      recent_kill = List.first(recent_kills)
      kill_id = Map.get(recent_kill, "killmail_id") || Map.get(recent_kill, :killmail_id)
      if kill_id, do: send_enriched_kill_embed(recent_kill, kill_id), else: %{"content" => message, "embeds" => []}
    else
      %{"content" => message, "embeds" => []}
    end
  end

  @spec send_embed(any(), any()) :: :ok | {:error, any()}
  @doc """
  Sends a basic embed message to Discord.
  """
  @impl WandererNotifier.NotifierBehaviour
  def send_embed(title, description, url \\ nil, color \\ @default_embed_color) do
    if env() == :test do
      if @verbose_logging, do: Logger.info("DISCORD MOCK EMBED: #{title} - #{description}")
      :ok
    else
      payload =
        if title == "Test Kill" do
          process_test_embed(title, description, url, color)
        else
          build_embed_payload(title, description, url, color)
        end

      send_payload(payload)
    end
  end

  defp process_test_embed(title, description, url, color) do
    recent_kills = WandererNotifier.Service.KillProcessor.get_recent_kills() || []

    if recent_kills != [] do
      recent_kill = List.first(recent_kills)
      kill_id = Map.get(recent_kill, "killmail_id") || Map.get(recent_kill, :killmail_id)
      if kill_id, do: send_enriched_kill_embed(recent_kill, kill_id), else: build_embed_payload(title, description, url, color)
    else
      build_embed_payload(title, description, url, color)
    end
  end

  defp build_embed_payload(title, description, url, color) do
    embed =
      %{
        "title" => title,
        "description" => description,
        "color" => color
      }
      |> maybe_put("url", url)

    %{"embeds" => [embed]}
  end

  # Inserts a key only if the value is not nil.
  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  @doc """
  Formats a timestamp string into a human-readable format.
  """
  def format_time(timestamp) when is_binary(timestamp) do
    case DateTime.from_iso8601(timestamp) do
      {:ok, datetime, _} -> DateTime.to_string(datetime)
      _ -> timestamp
    end
  end

  def format_time(_), do: "Unknown Time"

  @doc """
  Sends a Discord embed using the Discord API.
  """
  def send_discord_embed(embed) do
    url = build_url()
    Logger.info("Sending Discord embed to URL: #{url}")
    Logger.debug("Embed content: #{inspect(embed)}")

    payload = %{"embeds" => [embed]}

    with {:ok, json} <- Jason.encode(payload),
         {:ok, %{status_code: status}} when status in 200..299 <- HttpClient.request("POST", url, headers(), json) do
      Logger.info("Successfully sent Discord embed, status: #{status}")
      :ok
    else
      {:ok, %{status_code: status, body: body}} ->
        Logger.error("Failed to send Discord embed: status=#{status}, body=#{inspect(body)}")
        {:error, "Discord API error: #{status}"}
      {:error, reason} ->
        Logger.error("Error sending Discord embed: #{inspect(reason)}")
        {:error, reason}
      error ->
        Logger.error("Unexpected error: #{inspect(error)}")
        {:error, error}
    end
  end

  @doc """
  Sends a rich embed message for an enriched killmail.
  Expects the enriched killmail (and its nested maps) to have string keys.
  """
  @impl WandererNotifier.NotifierBehaviour
  def send_enriched_kill_embed(enriched_kill, kill_id) do
    if env() == :test do
      Logger.info("TEST MODE: Would send enriched kill embed for kill_id=#{kill_id}")
      :ok
    else
      enriched_kill = fully_enrich_kill_data(enriched_kill)
      victim = Map.get(enriched_kill, "victim") || %{}
      victim_name = get_value(victim, ["character_name"], "Unknown Pilot")
      victim_ship = get_value(victim, ["ship_type_name"], "Unknown Ship")
      system_name = Map.get(enriched_kill, "solar_system_name") || "Unknown System"

      if WandererNotifier.License.status().valid do
        create_and_send_kill_embed(enriched_kill, kill_id, victim_name, victim_ship, system_name)
      else
        Logger.info("License not valid, sending plain text kill notification instead of rich embed")
        send_message("Kill Alert: #{victim_name} lost a #{victim_ship} in #{system_name}.")
      end
    end
  end

  # Retrieves a value from a map checking both string and atom keys.
  defp get_value(map, keys, default) do
    Enum.find_value(keys, default, fn key ->
      Map.get(map, key) || Map.get(map, String.to_atom(key))
    end)
  end

  # -- ENRICHMENT FUNCTIONS --

  defp fully_enrich_kill_data(enriched_kill) do
    Logger.debug("Processing kill data: #{inspect(enriched_kill, pretty: true)}")

    victim =
      enriched_kill
      |> Map.get("victim", %{})
      |> enrich_victim_data()

    attackers =
      enriched_kill
      |> Map.get("attackers", [])
      |> Enum.map(&enrich_attacker_data/1)

    enriched_kill
    |> Map.put("victim", victim)
    |> Map.put("attackers", attackers)
  end

  defp enrich_victim_data(victim) do
    victim =
      case get_value(victim, ["character_name"], nil) do
        nil ->
          victim
          |> enrich_character("character_id", fn character_id ->
            case WandererNotifier.ESI.Service.get_character_info(character_id) do
              {:ok, char_data} ->
                Map.put(victim, "character_name", Map.get(char_data, "name", "Unknown Pilot"))
                |> enrich_corporation("corporation_id", char_data)
              _ ->
                Map.put_new(victim, "character_name", "Unknown Pilot")
            end
          end)
        _ ->
          victim
      end

    victim =
      case get_value(victim, ["ship_type_name"], nil) do
        nil ->
          victim
          |> enrich_character("ship_type_id", fn ship_type_id ->
            case WandererNotifier.ESI.Service.get_ship_type_name(ship_type_id) do
              {:ok, ship_data} -> Map.put(victim, "ship_type_name", Map.get(ship_data, "name", "Unknown Ship"))
              _ -> Map.put_new(victim, "ship_type_name", "Unknown Ship")
            end
          end)
        _ ->
          victim
      end

    if get_value(victim, ["corporation_name"], "Unknown Corp") == "Unknown Corp" do
      victim =
        enrich_character(victim, "character_id", fn character_id ->
          case WandererNotifier.ESI.Service.get_character_info(character_id) do
            {:ok, char_data} ->
              case Map.get(char_data, "corporation_id") do
                nil ->
                  victim
                corp_id ->
                  case WandererNotifier.ESI.Service.get_corporation_info(corp_id) do
                    {:ok, corp_data} -> Map.put(victim, "corporation_name", Map.get(corp_data, "name", "Unknown Corp"))
                    _ -> Map.put_new(victim, "corporation_name", "Unknown Corp")
                  end
              end
            _ -> victim
          end
        end)

      victim
    else
      victim
    end
  end

  defp enrich_character(data, key, fun) do
    case Map.get(data, key) || Map.get(data, String.to_atom(key)) do
      nil -> data
      value -> fun.(value)
    end
  end

  defp enrich_corporation(victim, _key, char_data) do
    case Map.get(victim, "corporation_id") || Map.get(victim, :corporation_id) || Map.get(char_data, "corporation_id") do
      nil -> victim
      corp_id ->
        case WandererNotifier.ESI.Service.get_corporation_info(corp_id) do
          {:ok, corp_data} -> Map.put(victim, "corporation_name", Map.get(corp_data, "name", "Unknown Corp"))
          _ -> Map.put_new(victim, "corporation_name", "Unknown Corp")
        end
    end
  end

  defp enrich_attacker_data(attacker) do
    attacker =
      case get_value(attacker, ["character_name"], nil) do
        nil ->
          enrich_character(attacker, "character_id", fn character_id ->
            case WandererNotifier.ESI.Service.get_character_info(character_id) do
              {:ok, char_data} -> Map.put(attacker, "character_name", Map.get(char_data, "name", "Unknown Pilot"))
              _ -> Map.put_new(attacker, "character_name", "Unknown Pilot")
            end
          end)
        _ ->
          attacker
      end

    case get_value(attacker, ["ship_type_name"], nil) do
      nil ->
        enrich_character(attacker, "ship_type_id", fn ship_type_id ->
          case WandererNotifier.ESI.Service.get_ship_type_name(ship_type_id) do
            {:ok, ship_data} -> Map.put(attacker, "ship_type_name", Map.get(ship_data, "name", "Unknown Ship"))
            _ -> Map.put_new(attacker, "ship_type_name", "Unknown Ship")
          end
        end)
      _ ->
        attacker
    end
  end

  # -- KILL EMBED --

  defp create_and_send_kill_embed(enriched_kill, kill_id, victim_name, victim_ship, system_name) do
    victim = Map.get(enriched_kill, "victim") || %{}
    victim_corp = get_value(victim, ["corporation_name"], "Unknown Corp")
    victim_alliance = get_value(victim, ["alliance_name"], nil)
    kill_value = get_in(enriched_kill, ["zkb", "totalValue"]) || 0
    formatted_value = format_isk_value(kill_value)
    kill_time = get_in(enriched_kill, ["killmail_time"])
    attackers = Map.get(enriched_kill, "attackers") || []

    final_blow_attacker =
      Enum.find(attackers, fn attacker ->
        Map.get(attacker, "final_blow") in [true, "true"]
      end)

    final_blow_name =
      if final_blow_attacker,
        do: get_value(final_blow_attacker, ["character_name"], "Unknown Pilot"),
        else: "Unknown Pilot"

    final_blow_ship =
      if final_blow_attacker,
        do: get_value(final_blow_attacker, ["ship_type_name"], "Unknown Ship"),
        else: "Unknown Ship"

    is_npc_kill = get_in(enriched_kill, ["zkb", "npc"]) == true
    final_blow_name = if is_npc_kill, do: "NPC", else: final_blow_name

    final_blow_character_id =
      if final_blow_attacker do
        Map.get(final_blow_attacker, "character_id") || Map.get(final_blow_attacker, :character_id)
      else
        nil
      end

    final_blow_text =
      if final_blow_character_id do
        "[#{final_blow_name}](https://zkillboard.com/character/#{final_blow_character_id}/) (#{final_blow_ship})"
      else
        "#{final_blow_name} (#{final_blow_ship})"
      end

    attackers_count = length(attackers)
    victim_ship_type_id = get_value(victim, ["ship_type_id"], nil)
    victim_character_id = get_value(victim, ["character_id"], nil)

    embed =
      %{
        "title" => "Kill Notification",
        "description" => "#{victim_name} lost a #{victim_ship} in #{system_name}",
        "color" => 0xFF0000,
        "url" => "https://zkillboard.com/kill/#{kill_id}/",
        "timestamp" => kill_time,
        "footer" => %{"text" => "Kill ID: #{kill_id}"},
        "thumbnail" => %{"url" => (if victim_ship_type_id, do: "https://images.evetech.net/types/#{victim_ship_type_id}/render", else: nil)},
        "author" => %{
          "name" =>
            if victim_name == "Unknown Pilot" and victim_corp == "Unknown Corp" do
              "Kill in #{system_name}"
            else
              "#{victim_name} (#{victim_corp})"
            end,
          "icon_url" =>
            if victim_name == "Unknown Pilot" and victim_corp == "Unknown Corp" do
              "https://images.evetech.net/types/30371/icon"
            else
              if victim_character_id, do: "https://imageserver.eveonline.com/Character/#{victim_character_id}_64.jpg", else: nil
            end
        },
        "fields" => [
          %{"name" => "Value", "value" => formatted_value, "inline" => true},
          %{"name" => "Attackers", "value" => "#{attackers_count}", "inline" => true},
          %{"name" => "Final Blow", "value" => final_blow_text, "inline" => true}
        ]
      }

    embed =
      if victim_alliance do
        NotificationHelpers.add_field_if_available(embed, "Alliance", victim_alliance)
      else
        embed
      end

    send_discord_embed(embed)
  end

  defp format_isk_value(value) when is_float(value) or is_integer(value) do
    cond do
      value < 1000 -> "<1k ISK"
      value < 1_000_000 -> "#{round(value / 1000)}k ISK"
      true -> "#{round(value / 1_000_000)}M ISK"
    end
  end

  defp format_isk_value(_), do: "0 ISK"

  # -- NEW TRACKED CHARACTER NOTIFICATION --

  @doc """
  Sends a notification for a new tracked character.
  Expects a map with keys: "character_id", "character_name", "corporation_id", "corporation_name".
  If names are missing, ESI lookups are performed.
  """
  @impl WandererNotifier.NotifierBehaviour
  def send_new_tracked_character_notification(character) when is_map(character) do
    if env() == :test do
      character_id = Map.get(character, "character_id") || Map.get(character, "eve_id")
      if @verbose_logging, do: Logger.info("DISCORD TEST CHARACTER NOTIFICATION: Character ID #{character_id}")
      :ok
    else
      try do
        WandererNotifier.Stats.increment(:characters)
      rescue
        _ -> :ok
      end

      character = enrich_character_data(character)
      character_id = NotificationHelpers.extract_character_id(character)
      character_name = NotificationHelpers.extract_character_name(character)
      corporation_name = NotificationHelpers.extract_corporation_name(character)

      if WandererNotifier.License.status().valid do
        create_and_send_character_embed(character_id, character_name, corporation_name)
      else
        Logger.info("License not valid, sending plain text character notification")
        message =
          "New Character Tracked: #{character_name}" <>
            if corporation_name, do: " (#{corporation_name})", else: ""
        send_message(message)
      end
    end
  end

  defp enrich_character_data(character) do
    character =
      case get_value(character, ["character_name"], nil) do
        nil ->
          enrich_character(character, "character_id", fn character_id ->
            case WandererNotifier.ESI.Service.get_character_info(character_id) do
              {:ok, char_data} ->
                Map.put(character, "character_name", Map.get(char_data, "name", "Unknown Pilot"))
              _ ->
                Map.put_new(character, "character_name", "Unknown Pilot")
            end
          end)
        _ ->
          character
      end

    character =
      case get_value(character, ["corporation_name"], nil) do
        nil ->
          case Map.get(character, "corporation_id") || Map.get(character, :corporation_id) do
            nil -> Map.put_new(character, "corporation_name", "Unknown Corp")
            corp_id ->
              case WandererNotifier.ESI.Service.get_corporation_info(corp_id) do
                {:ok, corp_data} ->
                  Map.put(character, "corporation_name", Map.get(corp_data, "name", "Unknown Corp"))
                _ ->
                  Map.put_new(character, "corporation_name", "Unknown Corp")
              end
          end
        _ ->
          character
      end

    character
  end

  defp create_and_send_character_embed(character_id, character_name, corporation_name) do
    embed =
      %{
        "title" => "New Character Tracked",
        "description" => "A new character has been added to the tracking list.",
        "color" => @default_embed_color,
        "timestamp" => DateTime.utc_now() |> DateTime.to_iso8601(),
        "thumbnail" => %{"url" => "https://imageserver.eveonline.com/Character/#{character_id}_128.jpg"},
        "fields" => [
          %{"name" => "Character", "value" => "[#{character_name}](https://zkillboard.com/character/#{character_id}/)", "inline" => true}
        ]
      }

    embed =
      if corporation_name do
        fields = embed["fields"] ++ [%{"name" => "Corporation", "value" => corporation_name, "inline" => true}]
        Map.put(embed, "fields", fields)
      else
        embed
      end

    send_discord_embed(embed)
  end

  # -- NEW SYSTEM NOTIFICATION --

  @doc """
  Sends a notification for a new system found.
  Expects a map with keys: "system_id" and optionally "system_name".
  If "system_name" is missing, falls back to a lookup.
  """
  @impl WandererNotifier.NotifierBehaviour
  def send_new_system_notification(system) when is_map(system) do
    if env() == :test do
      system_id = Map.get(system, "system_id") || Map.get(system, :system_id)
      if @verbose_logging, do: Logger.info("DISCORD TEST SYSTEM NOTIFICATION: System ID #{system_id}")
      :ok
    else
      try do
        WandererNotifier.Stats.increment(:systems)
      rescue
        _ -> :ok
      end

      system =
        if Map.has_key?(system, "data") and is_map(system["data"]) do
          Map.merge(system, system["data"])
        else
          system
        end

      create_and_send_system_embed(system)
    end
  end

  defp create_and_send_system_embed(system) do
    system =
      if Map.has_key?(system, "data") and is_map(system["data"]) do
        Map.merge(system, system["data"])
      else
        system
      end

    system_id =
      Map.get(system, "solar_system_id") ||
        Map.get(system, :solar_system_id)

    system_name =
      Map.get(system, "solar_system_name") ||
        Map.get(system, :solar_system_name) ||
        Map.get(system, "system_name") ||
        Map.get(system, :system_name) ||
        "Unknown System"

    security =
      Map.get(system, "security") ||
        Map.get(system, :security) ||
        Map.get(system, "security_status") ||
        Map.get(system, :security_status)

    type_description =
      Map.get(system, "type_description") ||
        Map.get(system, :type_description)

    if type_description == nil do
      Logger.error("Cannot send system notification: type_description not available for system #{system_name} (ID: #{system_id})")
      :error
    else
      effect_name = Map.get(system, "effect_name") || Map.get(system, :effect_name)
      is_shattered = Map.get(system, "is_shattered") || Map.get(system, :is_shattered)
      statics = Map.get(system, "statics") || Map.get(system, :statics) || []
      region_name = Map.get(system, "region_name") || Map.get(system, :region_name)

      security_str =
        case security do
          sec when is_binary(sec) -> sec
          sec when is_float(sec) -> Float.to_string(sec)
          _ -> ""
        end

      title =
        if security_str != "" do
          "New #{security_str} #{type_description} System Mapped"
        else
          "New #{type_description} System Mapped"
        end

      description =
        if security_str != "" do
          "A new #{security_str} #{type_description} system has been discovered and added to the map."
        else
          "A new #{type_description} system has been discovered and added to the map."
        end

      is_wormhole = String.contains?(type_description, "Class")
      sun_type_id = Map.get(system, "sun_type_id") || Map.get(system, :sun_type_id)

      icon_url =
        if sun_type_id do
          "https://images.evetech.net/types/#{sun_type_id}/icon"
        else
          cond do
            effect_name == "Pulsar" -> "https://images.evetech.net/types/30488/icon"
            effect_name == "Magnetar" -> "https://images.evetech.net/types/30484/icon"
            effect_name == "Wolf-Rayet Star" -> "https://images.evetech.net/types/30489/icon"
            effect_name == "Black Hole" -> "https://images.evetech.net/types/30483/icon"
            effect_name == "Cataclysmic Variable" -> "https://images.evetech.net/types/30486/icon"
            effect_name == "Red Giant" -> "https://images.evetech.net/types/30485/icon"
            String.contains?(type_description, "High-sec") -> "https://images.evetech.net/types/45041/icon"
            String.contains?(type_description, "Low-sec") -> "https://images.evetech.net/types/45031/icon"
            String.contains?(type_description, "Null-sec") -> "https://images.evetech.net/types/45033/icon"
            true -> "https://images.evetech.net/types/3802/icon"
          end
        end

      embed_color =
        cond do
          String.contains?(type_description, "High-sec") -> @highsec_color
          String.contains?(type_description, "Low-sec") -> @lowsec_color
          String.contains?(type_description, "Null-sec") -> @nullsec_color
          is_wormhole -> @wormhole_color
          true -> @default_embed_color
        end

      display_name = "[#{system_name}](https://zkillboard.com/system/#{system_id}/)"

      embed =
        %{
          "title" => title,
          "description" => description,
          "color" => embed_color,
          "timestamp" => DateTime.utc_now() |> DateTime.to_iso8601(),
          "thumbnail" => %{"url" => icon_url},
          "fields" => [
            %{"name" => "System", "value" => display_name, "inline" => true}
          ]
        }

      embed =
        if is_wormhole and is_shattered do
          fields = embed["fields"] ++ [%{"name" => "Shattered", "value" => "Yes", "inline" => true}]
          Map.put(embed, "fields", fields)
        else
          embed
        end

      embed =
        cond do
          is_wormhole and is_list(statics) and length(statics) > 0 ->
            statics_str = Enum.map_join(statics, ", ", fn static ->
              cond do
                is_map(static) -> Map.get(static, "name") || Map.get(static, :name) || inspect(static)
                is_binary(static) -> static
                true -> inspect(static)
              end
            end)
            fields = embed["fields"] ++ [%{"name" => "Statics", "value" => statics_str, "inline" => true}]
            Map.put(embed, "fields", fields)

          region_name ->
            encoded_region_name = URI.encode(region_name)
            region_link = "[#{region_name}](https://evemaps.dotlan.net/region/#{encoded_region_name})"
            fields = embed["fields"] ++ [%{"name" => "Region", "value" => region_link, "inline" => true}]
            Map.put(embed, "fields", fields)

          true ->
            embed
        end

      system_kills =
        if system_id do
          case WandererNotifier.ZKill.Service.get_system_kills(system_id, 5) do
            {:ok, zkill_kills} when is_list(zkill_kills) and length(zkill_kills) > 0 ->
              Logger.info("Found #{length(zkill_kills)} recent kills for system #{system_id} from zKillboard")
              zkill_kills

            {:ok, []} ->
              Logger.info("No recent kills found for system #{system_id} from zKillboard")
              []

            {:error, reason} ->
              Logger.error("Failed to fetch kills for system #{system_id} from zKillboard: #{inspect(reason)}")
              []
          end
        else
          []
        end

      embed =
        if length(system_kills) > 0 do
          kills_text = Enum.map_join(system_kills, "\n", fn kill ->
            kill_id = Map.get(kill, "killmail_id")
            zkb = Map.get(kill, "zkb") || %{}
            hash = Map.get(zkb, "hash")
            enriched_kill =
              if kill_id != nil and hash do
                case WandererNotifier.ESI.Service.get_esi_kill_mail(kill_id, hash) do
                  {:ok, killmail_data} -> Map.merge(kill, killmail_data)
                  _ -> kill
                end
              else
                kill
              end

            victim = Map.get(enriched_kill, "victim") || %{}
            victim_name =
              if Map.has_key?(victim, "character_id") do
                character_id = Map.get(victim, "character_id")
                case WandererNotifier.ESI.Service.get_character_info(character_id) do
                  {:ok, char_info} -> Map.get(char_info, "name", "Unknown Pilot")
                  _ -> "Unknown Pilot"
                end
              else
                "Unknown Pilot"
              end

            ship_type =
              if Map.has_key?(victim, "ship_type_id") do
                ship_type_id = Map.get(victim, "ship_type_id")
                case WandererNotifier.ESI.Service.get_ship_type_name(ship_type_id) do
                  {:ok, ship_info} -> Map.get(ship_info, "name", "Unknown Ship")
                  _ -> "Unknown Ship"
                end
              else
                "Unknown Ship"
              end

            zkb = Map.get(kill, "zkb") || %{}
            kill_value = Map.get(zkb, "totalValue")
            kill_time = Map.get(kill, "killmail_time") || Map.get(enriched_kill, "killmail_time")
            time_ago =
              if kill_time do
                case DateTime.from_iso8601(kill_time) do
                  {:ok, kill_datetime, _} ->
                    diff_seconds = DateTime.diff(DateTime.utc_now(), kill_datetime)
                    cond do
                      diff_seconds < 60 -> "just now"
                      diff_seconds < 3600 -> "#{div(diff_seconds, 60)}m ago"
                      diff_seconds < 86400 -> "#{div(diff_seconds, 3600)}h ago"
                      diff_seconds < 2592000 -> "#{div(diff_seconds, 86400)}d ago"
                      true -> "#{div(diff_seconds, 2592000)}mo ago"
                    end
                  _ -> ""
                end
              else
                ""
              end

            time_display = if time_ago != "", do: " (#{time_ago})", else: ""
            value_text =
              if kill_value do
                " - #{format_isk_value(kill_value)}"
              else
                ""
              end

            if victim_name == "Unknown Pilot" do
              "#{ship_type}#{value_text}#{time_display}"
            else
              "[#{victim_name}](https://zkillboard.com/kill/#{kill_id}/) - #{ship_type}#{value_text}#{time_display}"
            end
          end)

          fields = embed["fields"] ++ [%{"name" => "Recent Kills in System", "value" => kills_text, "inline" => false}]
          Map.put(embed, "fields", fields)
        else
          fields = embed["fields"] ++ [%{"name" => "Recent Kills in System", "value" => "No recent kills found for this system.", "inline" => false}]
          Map.put(embed, "fields", fields)
        end

      send_discord_embed(embed)
    end
  end

  # -- HELPER FOR SENDING PAYLOAD --

  defp send_payload(payload) do
    url = build_url()
    json_payload = Jason.encode!(payload)

    case HttpClient.request("POST", url, headers(), json_payload) do
      {:ok, %{status_code: status}} when status in 200..299 ->
        :ok

      {:ok, %{status_code: status, body: body}} ->
        Logger.error("Discord API request failed with status #{status}")
        Logger.error("Discord API error response: Elided for security. Enable debug logs for details.")
        {:error, body}

      {:error, err} ->
        Logger.error("Discord API request error: #{inspect(err)}")
        {:error, err}
    end
  end
end
