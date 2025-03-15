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
      payload = %{"content" => message, "embeds" => []}
      send_payload(payload)
    end
  end

  @doc """
  Sends a basic embed message to Discord.
  """
  @impl WandererNotifier.NotifierBehaviour
  def send_embed(title, description, url \\ nil, color \\ @default_embed_color) do
    if env() == :test do
      if @verbose_logging, do: Logger.info("DISCORD MOCK EMBED: #{title} - #{description}")
      :ok
    else
      embed = %{"title" => title, "description" => description, "color" => color}
      embed = if url, do: Map.put(embed, "url", url), else: embed
      payload = %{"embeds" => [embed]}
      send_payload(payload)
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

    headers = [
      {"Authorization", "Bot #{bot_token()}"},
      {"Content-Type", "application/json"}
    ]

    payload = %{
      embeds: [embed]
    }

    case Jason.encode(payload) do
      {:ok, json} ->
        case HttpClient.request("POST", url, headers, json) do
          {:ok, %{status_code: status}} when status in 200..299 ->
            Logger.debug("Successfully sent Discord embed")
            :ok
          {:ok, %{status_code: status, body: body}} ->
            Logger.error("Failed to send Discord embed: status=#{status}, body=#{body}")
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
      # Extract victim information
      victim_name = get_in(enriched_kill, ["victim", "character_name"]) || "Unknown"
      victim_ship = get_in(enriched_kill, ["victim", "ship_type_name"]) || "Unknown Ship"
      victim_corp = get_in(enriched_kill, ["victim", "corporation_name"]) || "Unknown Corp"
      victim_alliance = get_in(enriched_kill, ["victim", "alliance_name"])

      # Extract system information
      system_name = get_in(enriched_kill, ["solar_system_name"]) || "Unknown System"

      # Extract kill value
      kill_value = get_in(enriched_kill, ["zkb", "totalValue"]) || 0
      formatted_value = :erlang.float_to_binary(kill_value, decimals: 2)

      # Extract kill time
      kill_time = get_in(enriched_kill, ["killmail_time"])
      formatted_time = if kill_time, do: format_time(kill_time), else: "Unknown Time"

      # Extract final blow attacker
      final_blow_attacker = Enum.find(Map.get(enriched_kill, "attackers", []), fn attacker ->
        Map.get(attacker, "final_blow") == true
      end)

      # Get final blow details
      final_blow_name = if final_blow_attacker, do: Map.get(final_blow_attacker, "character_name", "Unknown"), else: "Unknown"
      final_blow_ship = if final_blow_attacker, do: Map.get(final_blow_attacker, "ship_type_name", "Unknown Ship"), else: "Unknown Ship"

      # Count attackers
      attackers_count = length(Map.get(enriched_kill, "attackers", []))

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
          url: "https://imageserver.eveonline.com/Type/#{get_in(enriched_kill, ["victim", "ship_type_id"])}_64.png"
        },
        author: %{
          name: "#{victim_name} (#{victim_corp})",
          icon_url: "https://imageserver.eveonline.com/Character/#{get_in(enriched_kill, ["victim", "character_id"])}_64.jpg"
        },
        fields: [
          %{
            name: "Value",
            value: "#{formatted_value} ISK",
            inline: true
          },
          %{
            name: "Time",
            value: formatted_time,
            inline: true
          },
          %{
            name: "Attackers",
            value: "#{attackers_count}",
            inline: true
          },
          %{
            name: "Final Blow",
            value: "#{final_blow_name} (#{final_blow_ship})",
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

      # Add security status field if available
      security_status = get_in(enriched_kill, ["solar_system", "security_status"])
      embed = NotificationHelpers.add_security_field(embed, security_status)

      # Additional thumbnail handling from upstream
      victim_ship_type = get_in(enriched_kill, ["victim", "ship_type_id"])
      embed = if victim_ship_type do
        Map.update!(embed, :thumbnail, fn thumbnail ->
          Map.put(thumbnail, :url, "https://images.evetech.net/types/#{victim_ship_type}/render")
        end)
      else
        embed
      end

      # Get top attacker for author icon (from upstream)
      attackers = Map.get(enriched_kill, "attackers", [])
      top_attacker = Enum.find(attackers, fn attacker -> Map.get(attacker, "final_blow") == true end)
      corp_id = if top_attacker, do: Map.get(top_attacker, "corporation_id"), else: nil

      embed = if corp_id do
        Map.update!(embed, :author, fn author ->
          Map.put(author, :icon_url, "https://images.evetech.net/corporations/#{corp_id}/logo")
        end)
      else
        embed
      end

      # Send the embed
      send_discord_embed(embed)
    end
  end

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

      # Extract character information
      character_id = NotificationHelpers.extract_character_id(character)
      character_name = NotificationHelpers.extract_character_name(character)
      corporation_name = NotificationHelpers.extract_corporation_name(character)

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

      # Extract system information
      system_name = Map.get(system, "system_name") || Map.get(system, :system_name) || "Unknown System"
      system_alias = Map.get(system, "alias") || Map.get(system, :alias)
      security_status = Map.get(system, "security_status") || Map.get(system, :security_status)

      # Determine system type
      system_type = determine_system_type(system)

      # Create the embed
      embed = %{
        title: "New System Tracked",
        description: "A new system has been added to the tracking list.",
        color: @default_embed_color,
        timestamp: DateTime.utc_now() |> DateTime.to_iso8601(),
        fields: [
          %{
            name: "System",
            value: "[#{system_name}](https://evemaps.dotlan.net/system/#{system_name})",
            inline: true
          },
          %{
            name: "Type",
            value: system_type,
            inline: true
          }
        ]
      }

      # Add alias field if available
      embed = if system_alias do
        fields = embed.fields ++ [%{name: "Alias", value: system_alias, inline: true}]
        Map.put(embed, :fields, fields)
      else
        embed
      end

      # Add security status field if available
      embed = if security_status do
        formatted_security = NotificationHelpers.format_security_status(security_status)
        fields = embed.fields ++ [%{name: "Security", value: formatted_security, inline: true}]
        Map.put(embed, :fields, fields)
      else
        embed
      end

      # Send the embed
      send_discord_embed(embed)
    end
  end

  # Helper to determine system type from system data
  defp determine_system_type(system) do
    cond do
      Map.get(system, "home") == true || Map.get(system, :home) == true ->
        "Home System"
      Map.get(system, "staging") == true || Map.get(system, :staging) == true ->
        "Staging System"
      Map.get(system, "recently") == true || Map.get(system, :recently) == true ->
        "Recently Visited"
      true ->
        "Tracked System"
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
