defmodule WandererNotifier.Discord.Notifier do
  @moduledoc """
  Discord notification service.
  Handles sending notifications to Discord.
  """
  require Logger
  alias WandererNotifier.Http.Client, as: HttpClient
  alias WandererNotifier.Helpers.NotificationHelpers

  # Implement the NotifierBehaviour
  @behaviour WandererNotifier.NotifierBehaviour

  # Default embed color (blue)
  @default_embed_color 0x3498DB
  @wormhole_color 0x428BCA  # Blue for Pulsar
  @highsec_color 0x5CB85C  # Green for highsec
  @lowsec_color 0xE28A0D  # Yellow/orange for lowsec
  @nullsec_color 0xD9534F  # Red for nullsec

  # Use a runtime environment check instead of compile-time
  defp env do
    Application.get_env(:wanderer_notifier, :env, :prod)
  end

  @base_url "https://discord.com/api/channels"
  @verbose_logging false  # Set to true to enable verbose logging

  # Define behavior for mocking in tests
  @callback send_message(String.t()) :: :ok | {:error, any()}
  @callback send_embed(String.t(), String.t(), any(), integer()) :: :ok | {:error, any()}

  # Retrieve the channel ID and bot token at runtime.
  defp channel_id do
    Application.get_env(:wanderer_notifier, :discord_channel_id)
  end

  defp bot_token do
    Application.get_env(:wanderer_notifier, :discord_bot_token)
  end

  defp build_url do
    id = channel_id()

    if id in [nil, ""] and env() != :test do
      raise "Discord channel ID not configured. Please set :discord_channel_id in your configuration."
    end

    "#{@base_url}/#{id}/messages"
  end

  defp headers do
    token = bot_token()

    if token in [nil, ""] and env() != :test do
      raise "Discord bot token not configured. Please set :discord_bot_token in your configuration."
    end

    [
      {"Content-Type", "application/json"},
      {"Authorization", "Bot #{token}"}
    ]
  end

  @doc """
  Sends a plain text message to Discord.
  """
  @impl WandererNotifier.NotifierBehaviour
  def send_message(message) when is_binary(message) do
    if env() == :test do
      if @verbose_logging, do: Logger.info("DISCORD MOCK: #{message}")
      :ok
    else
      # Check if this is a test notification request
      if String.contains?(message, "test kill notification") do
        # Get a recent kill from the cache
        recent_kills = WandererNotifier.Service.KillProcessor.get_recent_kills()

        if recent_kills != nil && length(recent_kills) > 0 do
          # Use the most recent kill
          recent_kill = List.first(recent_kills)
          kill_id = Map.get(recent_kill, "killmail_id") || Map.get(recent_kill, :killmail_id)

          if kill_id do
            # Send the kill notification using the recent kill
            send_enriched_kill_embed(recent_kill, kill_id)
          else
            # Fallback to regular message if no kill ID found
            payload = %{"content" => message, "embeds" => []}
            send_payload(payload)
          end
        else
          # Fallback to regular message if no recent kills
          payload = %{"content" => message, "embeds" => []}
          send_payload(payload)
        end
      else
        # Regular message
        payload = %{"content" => message, "embeds" => []}
        send_payload(payload)
      end
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
      # Check if this is a test kill notification
      if title == "Test Kill" do
        # Get a recent kill from the cache
        recent_kills = WandererNotifier.Service.KillProcessor.get_recent_kills()

        if recent_kills != nil && length(recent_kills) > 0 do
          # Use the most recent kill
          recent_kill = List.first(recent_kills)
          kill_id = Map.get(recent_kill, "killmail_id") || Map.get(recent_kill, :killmail_id)

          if kill_id do
            # Send the kill notification using the recent kill
            send_enriched_kill_embed(recent_kill, kill_id)
          else
            # Fallback to regular embed if no kill ID found
            embed = %{"title" => title, "description" => description, "color" => color}
            embed = if url, do: Map.put(embed, "url", url), else: embed
            payload = %{"embeds" => [embed]}
            send_payload(payload)
          end
        else
          # Fallback to regular embed if no recent kills
          embed = %{"title" => title, "description" => description, "color" => color}
          embed = if url, do: Map.put(embed, "url", url), else: embed
          payload = %{"embeds" => [embed]}
          send_payload(payload)
        end
      else
        # Regular embed
        embed = %{"title" => title, "description" => description, "color" => color}
        embed = if url, do: Map.put(embed, "url", url), else: embed
        payload = %{"embeds" => [embed]}
        send_payload(payload)
      end
    end
  end

  @doc """
  Formats a timestamp string into a human-readable format.
  """
  def format_time(timestamp) when is_binary(timestamp) do
    case DateTime.from_iso8601(timestamp) do
      {:ok, datetime, _} ->
        # Format as "YYYY-MM-DD HH:MM:SS UTC"
        "#{DateTime.to_string(datetime)}"
      _ ->
        timestamp
    end
  end
  def format_time(_), do: "Unknown Time"

  @doc """
  Sends a Discord embed using the Discord API.
  """
  def send_discord_embed(embed) do
    url = "#{@base_url}/#{channel_id()}/messages"
    Logger.info("Sending Discord embed to URL: #{url}")
    Logger.debug("Embed content: #{inspect(embed)}")

    headers = [
      {"Authorization", "Bot #{bot_token()}"},
      {"Content-Type", "application/json"}
    ]

    payload = %{
      embeds: [embed]
    }

    case Jason.encode(payload) do
      {:ok, json} ->
        Logger.debug("Successfully encoded payload, size: #{byte_size(json)} bytes")
        case HttpClient.request("POST", url, headers, json) do
          {:ok, %{status_code: status}} when status in 200..299 ->
            Logger.info("Successfully sent Discord embed, status: #{status}")
            :ok
          {:ok, %{status_code: status, body: body}} ->
            Logger.error("Failed to send Discord embed: status=#{status}, body=#{inspect(body)}")
            {:error, "Discord API error: #{status}"}
          {:error, reason} ->
            Logger.error("Error sending Discord embed: #{inspect(reason)}")
            {:error, reason}
        end
      {:error, reason} ->
        Logger.error("Failed to encode Discord payload: #{inspect(reason)}")
        {:error, reason}
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
      # Fully enrich the kill data first
      enriched_kill = fully_enrich_kill_data(enriched_kill)

      # First check if the data is in the kill_data structure directly
      victim = Map.get(enriched_kill, "victim") || Map.get(enriched_kill, :victim) || %{}

      # Extract victim information with proper fallbacks
      victim_name = get_in(victim, ["character_name"]) ||
                    get_in(victim, [:character_name]) ||
                    "Unknown Pilot"

      victim_ship = get_in(victim, ["ship_type_name"]) ||
                    get_in(victim, [:ship_type_name]) ||
                    "Unknown Ship"

      # Extract system information with proper fallbacks
      system_name = Map.get(enriched_kill, "solar_system_name") ||
                    Map.get(enriched_kill, :solar_system_name) ||
                    "Unknown System"

      # Check license status - only send rich embeds if license is valid
      license_status = WandererNotifier.License.status()

      if license_status.valid do
        # Create and send rich embed
        create_and_send_kill_embed(enriched_kill, kill_id, victim_name, victim_ship, system_name)
      else
        # Create and send plain text message
        Logger.info("License not valid, sending plain text kill notification instead of rich embed")
        message = "Kill Alert: #{victim_name} lost a #{victim_ship} in #{system_name}."
        send_message(message)
      end
    end
  end

  # Helper function to fully enrich kill data
  defp fully_enrich_kill_data(enriched_kill) do
    # Log the raw kill data for debugging
    Logger.debug("Processing kill data: #{inspect(enriched_kill, pretty: true)}")

    # Ensure victim information is present and enriched
    victim = Map.get(enriched_kill, "victim") || Map.get(enriched_kill, :victim) || %{}
    victim = enrich_victim_data(victim)

    # Update enriched_kill with enhanced victim data
    enriched_kill = Map.put(enriched_kill, "victim", victim)

    # Extract and enrich attackers
    attackers = Map.get(enriched_kill, "attackers") || Map.get(enriched_kill, :attackers) || []
    enriched_attackers = Enum.map(attackers, &enrich_attacker_data/1)

    # Update enriched_kill with enhanced attackers data
    Map.put(enriched_kill, "attackers", enriched_attackers)
  end

  # Helper function to enrich victim data
  defp enrich_victim_data(victim) do
    # Ensure character name is present
    victim = if Map.get(victim, "character_name") || Map.get(victim, :character_name) do
      victim
    else
      character_id = Map.get(victim, "character_id") || Map.get(victim, :character_id)

      if character_id do
        case WandererNotifier.ESI.Service.get_character_info(character_id) do
          {:ok, char_data} ->
            char_name = Map.get(char_data, "name", "Unknown Pilot")
            victim = Map.put(victim, "character_name", char_name)

            # Also try to get corporation info
            corporation_id = Map.get(victim, "corporation_id") || Map.get(victim, :corporation_id) ||
                             Map.get(char_data, "corporation_id")

            if corporation_id do
              case WandererNotifier.ESI.Service.get_corporation_info(corporation_id) do
                {:ok, corp_data} ->
                  corp_name = Map.get(corp_data, "name", "Unknown Corp")
                  Map.put(victim, "corporation_name", corp_name)
                _ -> victim
              end
            else
              victim
            end
          _ -> victim
        end
      else
        # Default values if no character ID
        victim = Map.put_new(victim, "character_name", "Unknown Pilot")
        Map.put_new(victim, "corporation_name", "Unknown Corp")
      end
    end

    # Ensure ship type information is present
    victim = if Map.get(victim, "ship_type_name") || Map.get(victim, :ship_type_name) do
      victim
    else
      ship_type_id = Map.get(victim, "ship_type_id") || Map.get(victim, :ship_type_id)

      if ship_type_id do
        case WandererNotifier.ESI.Service.get_ship_type_name(ship_type_id) do
          {:ok, ship_data} ->
            ship_name = Map.get(ship_data, "name", "Unknown Ship")
            Map.put(victim, "ship_type_name", ship_name)
          _ ->
            Map.put_new(victim, "ship_type_name", "Unknown Ship")
        end
      else
        Map.put_new(victim, "ship_type_name", "Unknown Ship")
      end
    end

    # Ensure corporation name is present
    if Map.get(victim, "corporation_name") == "Unknown Corp" || Map.get(victim, :corporation_name) == "Unknown Corp" do
      character_id = Map.get(victim, "character_id") || Map.get(victim, :character_id)

      if character_id do
        case WandererNotifier.ESI.Service.get_character_info(character_id) do
          {:ok, char_data} ->
            corporation_id = Map.get(char_data, "corporation_id")

            if corporation_id do
              case WandererNotifier.ESI.Service.get_corporation_info(corporation_id) do
                {:ok, corp_data} ->
                  corp_name = Map.get(corp_data, "name", "Unknown Corp")
                  Map.put(victim, "corporation_name", corp_name)
                _ ->
                  Map.put_new(victim, "corporation_name", "Unknown Corp")
              end
            else
              victim
            end
          _ -> victim
        end
      else
        victim
      end
    else
      victim
    end
  end

  # Helper function to enrich attacker data
  defp enrich_attacker_data(attacker) do
    # Ensure character name
    attacker = if Map.get(attacker, "character_name") || Map.get(attacker, :character_name) do
      attacker
    else
      character_id = Map.get(attacker, "character_id") || Map.get(attacker, :character_id)

      if character_id do
        case WandererNotifier.ESI.Service.get_character_info(character_id) do
          {:ok, char_data} ->
            char_name = Map.get(char_data, "name", "Unknown Pilot")
            Map.put(attacker, "character_name", char_name)
          _ ->
            Map.put_new(attacker, "character_name", "Unknown Pilot")
        end
      else
        Map.put_new(attacker, "character_name", "Unknown Pilot")
      end
    end

    # Ensure ship type name
    attacker = if Map.get(attacker, "ship_type_name") || Map.get(attacker, :ship_type_name) do
      attacker
    else
      ship_type_id = Map.get(attacker, "ship_type_id") || Map.get(attacker, :ship_type_id)

      if ship_type_id do
        case WandererNotifier.ESI.Service.get_ship_type_name(ship_type_id) do
          {:ok, ship_data} ->
            ship_name = Map.get(ship_data, "name", "Unknown Ship")
            Map.put(attacker, "ship_type_name", ship_name)
          _ ->
            Map.put_new(attacker, "ship_type_name", "Unknown Ship")
        end
      else
        Map.put_new(attacker, "ship_type_name", "Unknown Ship")
      end
    end

    attacker
  end

  # Helper function to create and send kill embed
  defp create_and_send_kill_embed(enriched_kill, kill_id, victim_name, victim_ship, system_name) do
    # Get victim data directly
    victim = Map.get(enriched_kill, "victim") || Map.get(enriched_kill, :victim) || %{}

    # Extract additional information for rich embed
    victim_corp = get_in(victim, ["corporation_name"]) ||
                  get_in(victim, [:corporation_name]) ||
                  "Unknown Corp"
    victim_alliance = get_in(victim, ["alliance_name"]) ||
                      get_in(victim, [:alliance_name])

    # Extract kill value
    kill_value = get_in(enriched_kill, ["zkb", "totalValue"]) ||
                 get_in(enriched_kill, [:zkb, :totalValue]) || 0
    formatted_value = format_isk_value(kill_value)

    # Extract kill time
    kill_time = get_in(enriched_kill, ["killmail_time"]) ||
                get_in(enriched_kill, [:killmail_time])

    # Get attackers
    attackers = Map.get(enriched_kill, "attackers") || Map.get(enriched_kill, :attackers) || []

    # Extract final blow attacker
    final_blow_attacker = Enum.find(attackers, fn attacker ->
      Map.get(attacker, "final_blow") == true || Map.get(attacker, :final_blow) == true
    end)

    # Get final blow details
    final_blow_name = if final_blow_attacker do
      Map.get(final_blow_attacker, "character_name") ||
      Map.get(final_blow_attacker, :character_name) ||
      "Unknown Pilot"
    else
      "Unknown Pilot"
    end

    final_blow_ship = if final_blow_attacker do
      Map.get(final_blow_attacker, "ship_type_name") ||
      Map.get(final_blow_attacker, :ship_type_name) ||
      "Unknown Ship"
    else
      "Unknown Ship"
    end

    # Check if this is an NPC kill from zkb data
    is_npc_kill = get_in(enriched_kill, ["zkb", "npc"]) == true ||
                  get_in(enriched_kill, [:zkb, :npc]) == true

    # Override final blow name if it's an NPC kill
    final_blow_name = if is_npc_kill, do: "NPC", else: final_blow_name

    # Get final blow character ID for zKillboard link
    final_blow_character_id = if final_blow_attacker do
      Map.get(final_blow_attacker, "character_id") ||
      Map.get(final_blow_attacker, :character_id)
    else
      nil
    end

    # Create final blow text with zKillboard link if character ID is available
    final_blow_text = if final_blow_character_id do
      "[#{final_blow_name}](https://zkillboard.com/character/#{final_blow_character_id}/) (#{final_blow_ship})"
    else
      "#{final_blow_name} (#{final_blow_ship})"
    end

    # Count attackers
    attackers_count = length(attackers)

    # Get victim ship type ID for thumbnail
    victim_ship_type_id = get_in(victim, ["ship_type_id"]) ||
                          get_in(victim, [:ship_type_id])

    # Get victim character ID for author icon
    victim_character_id = get_in(victim, ["character_id"]) ||
                          get_in(victim, [:character_id])

    # Create the embed
    embed = %{
      title: "Kill Notification",
      description: "#{victim_name} lost a #{victim_ship} in #{system_name}",
      color: 0xFF0000,  # Red
      url: "https://zkillboard.com/kill/#{kill_id}/",
      timestamp: kill_time,
      footer: %{
        text: "Kill ID: #{kill_id}"
      },
      thumbnail: %{
        url: (if victim_ship_type_id, do: "https://images.evetech.net/types/#{victim_ship_type_id}/render", else: nil)
      },
      author: %{
        name: if victim_name == "Unknown Pilot" && victim_corp == "Unknown Corp" do
          "Kill in #{system_name}"
        else
          "#{victim_name} (#{victim_corp})"
        end,
        icon_url: if victim_name == "Unknown Pilot" && victim_corp == "Unknown Corp" do
          # Use a system icon when victim is unknown
          "https://images.evetech.net/types/30371/icon"  # Generic wormhole icon
        else
          if victim_character_id do
            "https://imageserver.eveonline.com/Character/#{victim_character_id}_64.jpg"
          else
            nil
          end
        end
      },
      fields: [
        %{
          name: "Value",
          value: formatted_value,
          inline: true
        },
        %{
          name: "Attackers",
          value: "#{attackers_count}",
          inline: true
        },
        %{
          name: "Final Blow",
          value: final_blow_text,
          inline: true
        }
      ]
    }

    # Add alliance field if available
    embed = if victim_alliance do
      NotificationHelpers.add_field_if_available(embed, "Alliance", victim_alliance)
    else
      embed
    end

    # Send the embed
    send_discord_embed(embed)
  end

  # Helper function to format ISK value according to requirements
  defp format_isk_value(value) when is_float(value) or is_integer(value) do
    cond do
      value < 1000 -> "<1k ISK"
      value < 1_000_000 -> "#{round(value / 1000)}k ISK"
      true -> "#{round(value / 1_000_000)}M ISK"
    end
  end
  defp format_isk_value(_), do: "0 ISK"

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

      # Enrich character data first
      character = enrich_character_data(character)

      # Extract character information
      character_id = NotificationHelpers.extract_character_id(character)
      character_name = NotificationHelpers.extract_character_name(character)
      corporation_name = NotificationHelpers.extract_corporation_name(character)

      # Check license status
      license_status = WandererNotifier.License.status()

      if license_status.valid do
        # Create and send rich embed
        create_and_send_character_embed(character_id, character_name, corporation_name)
      else
        # Create and send plain text message
        Logger.info("License not valid, sending plain text character notification")
        message = "New Character Tracked: #{character_name}"
        message = if corporation_name, do: "#{message} (#{corporation_name})", else: message
        send_message(message)
      end
    end
  end

  # Helper function to enrich character data
  defp enrich_character_data(character) do
    # Ensure character name is present
    character = if Map.get(character, "character_name") || Map.get(character, :character_name) do
      character
    else
      character_id = Map.get(character, "character_id") || Map.get(character, :character_id) ||
                     Map.get(character, "eve_id") || Map.get(character, :eve_id)
      if character_id do
        case WandererNotifier.ESI.Service.get_character_info(character_id) do
          {:ok, char_data} ->
            char_name = Map.get(char_data, "name", "Unknown Pilot")
            Map.put(character, "character_name", char_name)
          _ ->
            Map.put_new(character, "character_name", "Unknown Pilot")
        end
      else
        Map.put_new(character, "character_name", "Unknown Pilot")
      end
    end

    # Ensure corporation name is present
    character = if Map.get(character, "corporation_name") || Map.get(character, :corporation_name) do
      character
    else
      corporation_id = Map.get(character, "corporation_id") || Map.get(character, :corporation_id)
      if corporation_id do
        case WandererNotifier.ESI.Service.get_corporation_info(corporation_id) do
          {:ok, corp_data} ->
            corp_name = Map.get(corp_data, "name", "Unknown Corp")
            Map.put(character, "corporation_name", corp_name)
          _ ->
            Map.put_new(character, "corporation_name", "Unknown Corp")
        end
      else
        # Try to get corporation ID from character ID
        character_id = Map.get(character, "character_id") || Map.get(character, :character_id) ||
                       Map.get(character, "eve_id") || Map.get(character, :eve_id)
        if character_id do
          case WandererNotifier.ESI.Service.get_character_info(character_id) do
            {:ok, char_data} ->
              corp_id = Map.get(char_data, "corporation_id")
              if corp_id do
                case WandererNotifier.ESI.Service.get_corporation_info(corp_id) do
                  {:ok, corp_data} ->
                    corp_name = Map.get(corp_data, "name", "Unknown Corp")
                    Map.put(character, "corporation_name", corp_name)
                  _ ->
                    Map.put_new(character, "corporation_name", "Unknown Corp")
                end
              else
                Map.put_new(character, "corporation_name", "Unknown Corp")
              end
            _ ->
              Map.put_new(character, "corporation_name", "Unknown Corp")
          end
        else
          Map.put_new(character, "corporation_name", "Unknown Corp")
        end
      end
    end

    character
  end

  # Helper function to create and send character embed
  defp create_and_send_character_embed(character_id, character_name, corporation_name) do
    # Create the embed
    embed = %{
      title: "New Character Tracked",
      description: "A new character has been added to the tracking list.",
      color: @default_embed_color,
      timestamp: DateTime.utc_now() |> DateTime.to_iso8601(),
      thumbnail: %{
        url: "https://imageserver.eveonline.com/Character/#{character_id}_128.jpg"
      },
      fields: [
        %{
          name: "Character",
          value: "[#{character_name}](https://zkillboard.com/character/#{character_id}/)",
          inline: true
        }
      ]
    }

    # Add corporation field if available
    embed = if corporation_name do
      fields = embed.fields ++ [%{name: "Corporation", value: corporation_name, inline: true}]
      Map.put(embed, :fields, fields)
    else
      embed
    end

    # Send the embed
    send_discord_embed(embed)
  end

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

      # Extract data from nested "data" field if present
      system = if Map.has_key?(system, "data") && is_map(system["data"]) do
        Map.merge(system, system["data"])
      else
        system
      end

      # Create and send the system embed
      create_and_send_system_embed(system)
    end
  end

  # Helper function to create and send system embed
  defp create_and_send_system_embed(system) do
    # Extract data from nested "data" field if present
    system = if Map.has_key?(system, "data") && is_map(system["data"]) do
      Map.merge(system, system["data"])
    else
      system
    end

    # Extract system information directly from the API response
    system_id = Map.get(system, "solar_system_id") || Map.get(system, :solar_system_id)
    system_name = Map.get(system, "solar_system_name") || Map.get(system, :solar_system_name) ||
                  Map.get(system, "system_name") || Map.get(system, :system_name) || "Unknown System"

    # Get security status and type description directly
    security = Map.get(system, "security") || Map.get(system, :security) ||
               Map.get(system, "security_status") || Map.get(system, :security_status)
    type_description = Map.get(system, "type_description") || Map.get(system, :type_description)

    # If type_description isn't available, log an error and don't send the notification
    if type_description == nil do
      Logger.error("Cannot send system notification: type_description not available for system #{system_name} (ID: #{system_id})")
      :error
    else
      # Get wormhole specific information
      effect_name = Map.get(system, "effect_name") || Map.get(system, :effect_name)
      is_shattered = Map.get(system, "is_shattered") || Map.get(system, :is_shattered)
      statics = Map.get(system, "statics") || Map.get(system, :statics) || []

      # Get region information
      region_name = Map.get(system, "region_name") || Map.get(system, :region_name)

      # Format security status for display
      security_str = case security do
        sec when is_binary(sec) -> sec
        sec when is_float(sec) -> Float.to_string(sec)
        _ -> ""
      end

      # Create title based on available information
      title = if security_str != "" do
        "New #{security_str} #{type_description} System Mapped"
      else
        "New #{type_description} System Mapped"
      end

      # Create description based on available information
      description = if security_str != "" do
        "A new #{security_str} #{type_description} system has been discovered and added to the map."
      else
        "A new #{type_description} system has been discovered and added to the map."
      end

      # Determine if this is a wormhole based on type_description
      is_wormhole = String.contains?(type_description, "Class")

      # Get system icon URL based on sun_type_id or system type
      sun_type_id = Map.get(system, "sun_type_id") || Map.get(system, :sun_type_id)
      icon_url = if sun_type_id do
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

      # Determine embed color based on system type
      embed_color = cond do
        String.contains?(type_description, "High-sec") -> @highsec_color
        String.contains?(type_description, "Low-sec") -> @lowsec_color
        String.contains?(type_description, "Null-sec") -> @nullsec_color
        is_wormhole -> @wormhole_color
        true -> @default_embed_color
      end

      # Format system display name with proper linking
      display_name = "[#{system_name}](https://zkillboard.com/system/#{system_id}/)"

      # Create the embed
      embed = %{
        title: title,
        description: description,
        color: embed_color,
        timestamp: DateTime.utc_now() |> DateTime.to_iso8601(),
        thumbnail: %{
          url: icon_url
        },
        fields: [
          %{
            name: "System",
            value: display_name,
            inline: true
          }
        ]
      }

      # Add shattered status if available
      embed = if is_wormhole && is_shattered do
        fields = embed.fields ++ [%{
          name: "Shattered",
          value: "Yes",
          inline: true
        }]
        Map.put(embed, :fields, fields)
      else
        embed
      end

      # Add region field for non-wormhole systems or statics for wormhole systems
      embed = cond do
        is_wormhole && is_list(statics) && length(statics) > 0 ->
          # Format statics as a comma-separated list for wormhole systems
          statics_str = Enum.map_join(statics, ", ", fn static ->
            cond do
              is_map(static) && (static["name"] || static[:name]) ->
                static["name"] || static[:name]
              is_binary(static) ->
                static
              true ->
                inspect(static)
            end
          end)
          fields = embed.fields ++ [%{name: "Statics", value: statics_str, inline: true}]
          Map.put(embed, :fields, fields)

        region_name ->
          # Link region name to Dotlan for all non-wormhole systems
          encoded_region_name = URI.encode(region_name)
          region_link = "[#{region_name}](https://evemaps.dotlan.net/region/#{encoded_region_name})"
          fields = embed.fields ++ [%{name: "Region", value: region_link, inline: true}]
          Map.put(embed, :fields, fields)

        true ->
          embed
      end

      # Add recent kills section if available
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

      # Add up to 5 recent kills to the embed
      embed = if length(system_kills) > 0 do
        # Format kills as a list
        kills_text = Enum.map_join(system_kills, "\n", fn kill ->
          # Extract the kill ID
          kill_id = Map.get(kill, "killmail_id")

          # For zKillboard API, we need to extract the hash and use ESI to get complete data
          zkb = Map.get(kill, "zkb") || %{}
          hash = Map.get(zkb, "hash")

          # Only try to enrich if we have both kill_id and hash
          enriched_kill = if kill_id && hash do
            case WandererNotifier.ESI.Service.get_esi_kill_mail(kill_id, hash) do
              {:ok, killmail_data} ->
                # Merge the ESI killmail data with the zKillboard data
                Map.merge(kill, killmail_data)
              _ ->
                # If ESI lookup fails, use the original kill data
                kill
            end
          else
            kill
          end

          # Now extract victim information using the same approach as in kill notifications
          victim = Map.get(enriched_kill, "victim") || %{}

          # Extract victim name with proper enrichment
          victim_name = if Map.has_key?(victim, "character_id") do
            character_id = Map.get(victim, "character_id")
            case WandererNotifier.ESI.Service.get_character_info(character_id) do
              {:ok, char_info} ->
                Map.get(char_info, "name", "Unknown Pilot")
              _ -> "Unknown Pilot"
            end
          else
            "Unknown Pilot"
          end

          # Extract ship type with proper enrichment
          ship_type = if Map.has_key?(victim, "ship_type_id") do
            ship_type_id = Map.get(victim, "ship_type_id")
            case WandererNotifier.ESI.Service.get_ship_type_name(ship_type_id) do
              {:ok, ship_info} ->
                Map.get(ship_info, "name", "Unknown Ship")
              _ -> "Unknown Ship"
            end
          else
            "Unknown Ship"
          end

          # Extract kill value from zkb data
          zkb = Map.get(kill, "zkb") || %{}
          kill_value = Map.get(zkb, "totalValue")

          # Extract kill time and calculate time since kill
          kill_time = Map.get(kill, "killmail_time") || Map.get(enriched_kill, "killmail_time")
          time_ago = if kill_time do
            case DateTime.from_iso8601(kill_time) do
              {:ok, kill_datetime, _} ->
                now = DateTime.utc_now()
                diff_seconds = DateTime.diff(now, kill_datetime)

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

          # Add time ago to the display if available
          time_display = if time_ago != "", do: " (#{time_ago})", else: ""

          value_text = if kill_value do
            formatted_value =
              cond do
                kill_value < 1000 -> "<1k ISK"
                kill_value < 1_000_000 -> "#{round(kill_value / 1000)}k ISK"
                true -> "#{round(kill_value / 1_000_000)}M ISK"
              end
            " - #{formatted_value}"
          else
            ""
          end

          # Format the kill entry with link just on the character name
          if victim_name == "Unknown Pilot" do
            "#{ship_type}#{value_text}#{time_display}"
          else
            "[#{victim_name}](https://zkillboard.com/kill/#{kill_id}/) - #{ship_type}#{value_text}#{time_display}"
          end
        end)

        # Add a field for recent kills
        fields = embed.fields ++ [%{
          name: "Recent Kills in System",
          value: kills_text,
          inline: false
        }]

        Map.put(embed, :fields, fields)
      else
        # If no kills were found, add a message indicating that
        fields = embed.fields ++ [%{
          name: "Recent Kills in System",
          value: "No recent kills found for this system.",
          inline: false
        }]

        Map.put(embed, :fields, fields)
      end

      # Send the embed
      send_discord_embed(embed)
    end
  end

  # Shared helper for sending notifications with license check
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
