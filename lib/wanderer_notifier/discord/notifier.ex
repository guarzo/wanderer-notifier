defmodule WandererNotifier.Discord.Notifier do
  @moduledoc """
  Discord notification service.
  Handles sending notifications to Discord.
  """
  require Logger
  alias WandererNotifier.Api.Http.Client, as: HttpClient
  alias WandererNotifier.Api.ESI.Service, as: ESIService
  alias WandererNotifier.Core.Stats
  alias WandererNotifier.Core.License
  alias WandererNotifier.Notifiers.StructuredFormatter
  alias WandererNotifier.Data.MapSystem
  alias WandererNotifier.Data.Killmail
  alias WandererNotifier.Helpers.NotificationHelpers
  alias WandererNotifier.Notifiers.Factory, as: NotifierFactory

  @behaviour WandererNotifier.NotifierBehaviour

  # Default embed colors
  @default_embed_color 0x3498DB
  # Blue for Pulsar
  # @wormhole_color 0x428BCA
  # # Green for highsec
  # @highsec_color 0x5CB85C
  # # Yellow/orange for lowsec
  # @lowsec_color 0xE28A0D
  # # Red for nullsec
  # @nullsec_color 0xD9534F

  @base_url "https://discord.com/api/channels"
  # Set to true to enable verbose logging
  @verbose_logging false

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

  # Helper function to handle test mode logging and response
  defp handle_test_mode(log_message) do
    if @verbose_logging, do: Logger.info(log_message)
    :ok
  end

  defp channel_id,
    do:
      get_config!(
        :discord_channel_id,
        "Discord channel ID not configured. Please set :discord_channel_id in your configuration."
      )

  defp bot_token,
    do:
      get_config!(
        :discord_bot_token,
        "Discord bot token not configured. Please set :discord_bot_token in your configuration."
      )

  defp build_url, do: "#{@base_url}/#{channel_id()}/messages"

  defp headers do
    [
      {"Content-Type", "application/json"},
      {"Authorization", "Bot #{bot_token()}"}
    ]
  end

  # -- HELPER FUNCTIONS --

  # Retrieves a value from a map checking both string and atom keys.
  # Tries each key in the provided list until a value is found.
  @spec get_value(map(), [String.t()], any()) :: any()
  defp get_value(map, keys, default) do
    Enum.find_value(keys, default, fn key ->
      Map.get(map, key) || Map.get(map, String.to_atom(key))
    end)
  end

  # -- MESSAGE SENDING --

  @doc """
  Sends a plain text message to Discord.
  """
  @impl WandererNotifier.NotifierBehaviour
  def send_message(message, feature \\ nil) when is_binary(message) do
    if env() == :test do
      handle_test_mode("DISCORD MOCK: #{message}")
    else
      payload =
        if String.contains?(message, "test kill notification") do
          process_test_kill_notification(message)
        else
          %{"content" => message, "embeds" => []}
        end

      send_payload(payload, feature)
    end
  end

  defp process_test_kill_notification(message) do
    recent_kills = WandererNotifier.Services.KillProcessor.get_recent_kills() || []

    if recent_kills != [] do
      recent_kill = List.first(recent_kills)
      kill_id = Map.get(recent_kill, "killmail_id") || Map.get(recent_kill, :killmail_id)

      if kill_id,
        do: send_enriched_kill_embed(recent_kill, kill_id),
        else: %{"content" => message, "embeds" => []}
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
    Logger.info("Discord.Notifier.send_embed called with title: #{title}, url: #{url || "nil"}")

    if env() == :test do
      handle_test_mode("DISCORD MOCK EMBED: #{title} - #{description}")
    else
      payload =
        if title == "Test Kill" do
          process_test_embed(title, description, url, color)
        else
          build_embed_payload(title, description, url, color)
        end

      Logger.info("Discord embed payload built, sending to Discord API")
      send_payload(payload)
    end
  end

  defp process_test_embed(title, description, url, color) do
    recent_kills = WandererNotifier.Services.KillProcessor.get_recent_kills() || []

    if recent_kills != [] do
      recent_kill = List.first(recent_kills)
      kill_id = Map.get(recent_kill, "killmail_id") || Map.get(recent_kill, :killmail_id)

      if kill_id,
        do: send_enriched_kill_embed(recent_kill, kill_id),
        else: build_embed_payload(title, description, url, color)
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
  Sends a Discord embed using the Discord API.
  """
  def send_discord_embed(embed, _feature \\ nil) do
    if env() == :test do
      handle_test_mode("DISCORD MOCK EMBED (JSON): #{inspect(embed)}")
    else
      payload = %{"embeds" => [embed]}
      send_payload(payload)
    end
  end

  @doc """
  Sends a rich embed message for an enriched killmail.
  Expects the killmail data in either map format or as a Killmail struct.
  Converts the data to a proper Killmail struct if needed before formatting.
  """
  @impl WandererNotifier.NotifierBehaviour
  def send_enriched_kill_embed(kill_data, kill_id) do
    if env() == :test do
      handle_test_mode("TEST MODE: Would send enriched kill embed for kill_id=#{kill_id}")
    else
      # Convert to Killmail struct if needed
      killmail = convert_to_killmail_struct(kill_data, kill_id)

      # Extract basic info for logging and non-premium fallback
      victim = Killmail.get_victim(killmail) || %{}
      victim_name = Map.get(victim, "character_name", "Unknown Pilot")
      victim_ship = Map.get(victim, "ship_type_name", "Unknown Ship")
      system_name = Map.get(killmail.esi_data || %{}, "solar_system_name", "Unknown System")

      # Check if this is the first kill notification since startup
      is_first_notification = Stats.is_first_notification?(:kill)

      # For first notification or with valid license, use enriched format
      if is_first_notification || License.status().valid do
        # Mark that we've sent the first notification if this is it
        if is_first_notification do
          Stats.mark_notification_sent(:kill)
          Logger.info("Sending first kill notification in enriched format (startup message)")
        end

        # Use the structured formatter to create a generic notification
        generic_notification = StructuredFormatter.format_kill_notification(killmail)

        # Convert to Discord format
        discord_embed = StructuredFormatter.to_discord_format(generic_notification)

        # Send the notification
        send_discord_embed(discord_embed, :kill_notifications)
      else
        Logger.info(
          "License not valid, sending plain text kill notification instead of rich embed"
        )

        send_message(
          "Kill Alert: #{victim_name} lost a #{victim_ship} in #{system_name}.",
          :kill_notifications
        )
      end
    end
  end

  # -- ENRICHMENT FUNCTIONS --

  # These functions are deprecated and will be removed
  # They were kept temporarily for reference but are no longer used
  # New code uses the StructuredFormatter with proper domain structs

  # Helper function used by character notification code
  defp enrich_character(data, key, fun) do
    case Map.get(data, key) || Map.get(data, String.to_atom(key)) do
      nil -> data
      value -> fun.(value)
    end
  end

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
      handle_test_mode("DISCORD TEST CHARACTER NOTIFICATION: Character ID #{character_id}")
    else
      try do
        Stats.increment(:characters)
      rescue
        _ -> :ok
      end

      character = enrich_character_data(character)
      character_id = NotificationHelpers.extract_character_id(character)
      character_name = NotificationHelpers.extract_character_name(character)
      corporation_name = NotificationHelpers.extract_corporation_name(character)

      if WandererNotifier.Core.License.status().valid do
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
            case ESIService.get_character_info(character_id) do
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
            nil ->
              Map.put_new(character, "corporation_name", "Unknown Corp")

            corp_id ->
              case ESIService.get_corporation_info(corp_id) do
                {:ok, corp_data} ->
                  Map.put(
                    character,
                    "corporation_name",
                    Map.get(corp_data, "name", "Unknown Corp")
                  )

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
        "thumbnail" => %{
          "url" => "https://imageserver.eveonline.com/Character/#{character_id}_128.jpg"
        },
        "fields" => [
          %{
            "name" => "Character",
            "value" => "[#{character_name}](https://zkillboard.com/character/#{character_id}/)",
            "inline" => true
          }
        ]
      }

    embed =
      if corporation_name do
        fields =
          embed["fields"] ++
            [%{"name" => "Corporation", "value" => corporation_name, "inline" => true}]

        Map.put(embed, "fields", fields)
      else
        embed
      end

    send_discord_embed(embed)
  end

  # -- NEW SYSTEM NOTIFICATION --

  @impl true
  def send_new_system_notification(system) when is_map(system) do
    if env() == :test do
      system_id =
        if is_struct(system, MapSystem),
          do: system.solar_system_id,
          else: Map.get(system, "system_id") || Map.get(system, :system_id)

      handle_test_mode("DISCORD TEST SYSTEM NOTIFICATION: System ID #{system_id}")
    else
      try do
        Stats.increment(:systems)
      rescue
        _ -> :ok
      end

      # Log the system data for debugging
      Logger.info("[Discord] Processing system notification")
      Logger.debug("[Discord] Raw system data: #{inspect(system, pretty: true, limit: 5000)}")

      # Convert to MapSystem struct if not already
      system_struct =
        if is_struct(system) && system.__struct__ == MapSystem do
          system
        else
          MapSystem.new(system)
        end

      # Check if this is the first system notification since startup
      is_first_notification = Stats.is_first_notification?(:system)

      # Mark that we've sent the first notification if this is it
      if is_first_notification do
        Stats.mark_notification_sent(:system)
        Logger.info("[Discord] Sending first system notification in enriched format")
      end

      # For first notification or with valid license, use enriched format
      if is_first_notification || License.status().valid do
        # Create notification with StructuredFormatter
        generic_notification = StructuredFormatter.format_system_notification(system_struct)
        discord_embed = StructuredFormatter.to_discord_format(generic_notification)

        # Add recent kills to the embed if available and system is a wormhole
        if MapSystem.is_wormhole?(system_struct) do
          solar_system_id = system_struct.solar_system_id

          recent_kills =
            WandererNotifier.Services.KillProcessor.get_recent_kills()
            |> Enum.filter(fn kill ->
              kill_system_id = get_in(kill, ["esi_data", "solar_system_id"])
              kill_system_id == solar_system_id
            end)

          # Update the embed with recent kills if available
          if recent_kills && recent_kills != [] do
            # We found recent kills in this system, add them to the embed
            recent_kills_field = %{
              "name" => "Recent Kills",
              "value" => format_recent_kills_list(recent_kills),
              "inline" => false
            }

            # Add the field to the existing embed
            updated_embed =
              Map.update(discord_embed, "fields", [recent_kills_field], fn fields ->
                fields ++ [recent_kills_field]
              end)

            # Send the updated embed
            NotifierFactory.notify(:send_discord_embed, [updated_embed, :general])
          end
        end
      else
        # For non-licensed users after first message, send plain text
        Logger.info("[Discord] License not valid, sending plain text system notification")

        # Create plain text message using struct fields directly
        display_name = MapSystem.format_display_name(system_struct)
        type_desc = MapSystem.get_type_description(system_struct)

        message = "New System Discovered: #{display_name} - #{type_desc}"

        # Add statics for wormhole systems
        if MapSystem.is_wormhole?(system_struct) && length(system_struct.statics) > 0 do
          statics = Enum.map_join(system_struct.statics, ", ", &(&1["name"] || &1[:name] || ""))
          updated_message = "#{message} - Statics: #{statics}"
          send_message(updated_message, :system_tracking)
        else
          send_message(message, :system_tracking)
        end
      end
    end
  end

  # -- HELPER FOR SENDING PAYLOAD --

  defp send_payload(payload, _feature \\ nil) do
    url = build_url()
    json_payload = Jason.encode!(payload)

    Logger.info("Sending Discord API request to URL: #{url}")
    Logger.debug("Discord API payload: #{inspect(payload, pretty: true)}")

    case HttpClient.request("POST", url, headers(), json_payload) do
      {:ok, %{status_code: status}} when status in 200..299 ->
        Logger.info("Discord API request successful with status #{status}")
        :ok

      {:ok, %{status_code: status, body: body}} ->
        Logger.error("Discord API request failed with status #{status}")
        Logger.error("Discord API error response: #{body}")
        {:error, body}

      {:error, err} ->
        Logger.error("Discord API request error: #{inspect(err)}")
        {:error, err}
    end
  end

  # -- FILE SENDING --

  @doc """
  Sends a file to Discord with an optional title and description.
  """
  @impl WandererNotifier.NotifierBehaviour
  def send_file(filename, file_data, title \\ nil, description \\ nil) do
    Logger.info("Sending file to Discord: #{filename}")

    if env() == :test do
      handle_test_mode("DISCORD MOCK FILE: #{filename} - #{title || "No title"}")
    else
      url = build_url()

      # Create form data with file and JSON payload
      boundary = "----------------------------#{:rand.uniform(999_999_999)}"

      # Create JSON part with embed if title/description provided
      json_payload =
        if title || description do
          embed = %{
            "title" => title || filename,
            "description" => description || "",
            "color" => @default_embed_color
          }

          Jason.encode!(%{"embeds" => [embed]})
        else
          "{}"
        end

      # Build multipart request body
      body = [
        "--#{boundary}\r\n",
        "Content-Disposition: form-data; name=\"payload_json\"\r\n\r\n",
        json_payload,
        "\r\n--#{boundary}\r\n",
        "Content-Disposition: form-data; name=\"file\"; filename=\"#{filename}\"\r\n",
        "Content-Type: application/octet-stream\r\n\r\n",
        file_data,
        "\r\n--#{boundary}--\r\n"
      ]

      # Custom headers for multipart request
      file_headers = [
        {"Content-Type", "multipart/form-data; boundary=#{boundary}"},
        {"Authorization", "Bot #{bot_token()}"}
      ]

      case HttpClient.request("POST", url, file_headers, body) do
        {:ok, %{status_code: status}} when status in 200..299 ->
          Logger.info("Successfully sent file to Discord, status: #{status}")
          :ok

        {:ok, %{status_code: status, body: response_body}} ->
          Logger.error(
            "Failed to send file to Discord: status=#{status}, body=#{inspect(response_body)}"
          )

          {:error, "Discord API error: #{status}"}

        {:error, reason} ->
          Logger.error("Error sending file to Discord: #{inspect(reason)}")
          {:error, reason}
      end
    end
  end

  @doc """
  Sends an embed with an image to Discord.
  """
  @impl WandererNotifier.NotifierBehaviour
  def send_image_embed(title, description, image_url, color \\ @default_embed_color) do
    Logger.info(
      "Discord.Notifier.send_image_embed called with title: #{title}, image_url: #{image_url || "nil"}"
    )

    if env() == :test do
      handle_test_mode(
        "DISCORD MOCK IMAGE EMBED: #{title} - #{description} with image: #{image_url}"
      )
    else
      embed = %{
        "title" => title,
        "description" => description,
        "color" => color,
        "image" => %{
          "url" => image_url
        }
      }

      payload = %{"embeds" => [embed]}

      Logger.info("Discord image embed payload built, sending to Discord API")
      send_payload(payload)
    end
  end

  # Format recent kills list for notification
  defp format_recent_kills_list(kills) when is_list(kills) do
    Enum.map_join(kills, "\n", fn kill ->
      kill_id = Map.get(kill, "killmail_id")
      zkb = Map.get(kill, "zkb") || %{}
      esi_data = Map.get(kill, "esi_data") || %{}

      victim = Map.get(esi_data, "victim") || %{}
      _ship_type_id = Map.get(victim, "ship_type_id")
      ship_name = Map.get(victim, "ship_type_name", "Unknown Ship")
      character_id = Map.get(victim, "character_id")
      character_name = Map.get(victim, "character_name", "Unknown Pilot")

      kill_value = Map.get(zkb, "totalValue")

      formatted_value =
        if kill_value,
          do: " - #{format_isk_value(kill_value)}",
          else: ""

      if character_id && character_name != "Unknown Pilot" do
        "[#{character_name}](https://zkillboard.com/kill/#{kill_id}/) - #{ship_name}#{formatted_value}"
      else
        "#{ship_name}#{formatted_value}"
      end
    end)
  end

  defp format_recent_kills_list(_), do: "No recent kills found"

  # Helper function to convert various formats to a Killmail struct
  defp convert_to_killmail_struct(kill_data, kill_id) do
    cond do
      # Already a Killmail struct
      is_struct(kill_data) && kill_data.__struct__ == Killmail ->
        kill_data

      # Regular map with expected structure
      is_map(kill_data) ->
        # Extract zkb data if available
        zkb_data = Map.get(kill_data, "zkb") || %{}
        # The rest is treated as ESI data (excluding zkb)
        esi_data = Map.drop(kill_data, ["zkb"])
        # Create a Killmail struct
        Killmail.new(kill_id, zkb_data, esi_data)

      # Other cases (shouldn't happen)
      true ->
        Logger.warning("Unexpected killmail data format: #{inspect(kill_data)}")
        # Create a minimal struct with the ID
        Killmail.new(kill_id, %{}, %{})
    end
  end

  # Format ISK values for display
  defp format_isk_value(value) when is_float(value) or is_integer(value) do
    cond do
      value < 1000 -> "<1k ISK"
      value < 1_000_000 -> "#{round(value / 1000)}k ISK"
      true -> "#{round(value / 1_000_000)}M ISK"
    end
  end

  defp format_isk_value(_), do: "0 ISK"
end
