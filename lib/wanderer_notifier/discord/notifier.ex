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

  # Format ISK values for display - moved from removed code
  defp format_isk_value(value) when is_float(value) or is_integer(value) do
    cond do
      value < 1000 -> "<1k ISK"
      value < 1_000_000 -> "#{round(value / 1000)}k ISK"
      true -> "#{round(value / 1_000_000)}M ISK"
    end
  end

  defp format_isk_value(_), do: "0 ISK"

  # Helper function used by character notification code
  defp enrich_character(data, key, fun) do
    case Map.get(data, key) || Map.get(data, String.to_atom(key)) do
      nil -> data
      value -> fun.(value)
    end
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
  Send an enriched kill embed to Discord.
  """
  @impl WandererNotifier.NotifierBehaviour
  def send_enriched_kill_embed(killmail, kill_id) when is_struct(killmail, Killmail) do
    Logger.debug("📨 FORMATTING: Preparing to format killmail #{kill_id} for Discord")

    # Ensure the killmail has a system name if system_id is present
    enriched_killmail = enrich_with_system_name(killmail)

    formatted_embed = StructuredFormatter.format_kill_notification(enriched_killmail)
    send_to_discord(formatted_embed, "kill")
  end

  def send_enriched_kill_embed(raw_killmail, kill_id) do
    Logger.debug("📨 FORMATTING: Converting raw killmail #{kill_id} to struct")
    killmail = ensure_killmail_struct(raw_killmail)
    send_enriched_kill_embed(killmail, kill_id)
  end

  # Simple helper to ensure we have a Killmail struct
  defp ensure_killmail_struct(data) when is_struct(data, Killmail), do: data
  defp ensure_killmail_struct(data) when is_map(data), do: struct(Killmail, data)

  # Ensure the killmail has a system name if missing
  defp enrich_with_system_name(%Killmail{} = killmail) do
    # Get system_id from the esi_data
    system_id = get_system_id_from_killmail(killmail)

    # Check if we need to get the system name
    if system_id do
      # Get system name using the same approach as in kill_processor
      system_name = get_system_name(system_id)
      Logger.debug("🔍 ENRICHING: Added system name '#{system_name}' to killmail")

      # Add system name to esi_data
      new_esi_data = Map.put(killmail.esi_data || %{}, "solar_system_name", system_name)
      %{killmail | esi_data: new_esi_data}
    else
      killmail
    end
  end

  # Get system ID from killmail
  defp get_system_id_from_killmail(%Killmail{} = killmail) do
    if killmail.esi_data do
      Map.get(killmail.esi_data, "solar_system_id")
    else
      nil
    end
  end

  # Helper function to get system name with caching
  defp get_system_name(nil), do: nil

  defp get_system_name(system_id) do
    case WandererNotifier.Api.ESI.Service.get_system_info(system_id) do
      {:ok, system_info} -> Map.get(system_info, "name")
      _ -> nil
    end
  end

  # Send formatted notification to Discord
  defp send_to_discord(formatted_notification, feature) do
    # Skip actual sending in test mode
    if env() == :test do
      handle_test_mode("DISCORD TEST NOTIFICATION: #{inspect(feature)}")
    else
      # Convert to Discord format
      discord_embed = StructuredFormatter.to_discord_format(formatted_notification)

      # Build and send a standardized payload
      discord_payload = %{"embeds" => [discord_embed]}
      send_payload(discord_payload, feature)
    end
  end

  # -- NEW TRACKED CHARACTER NOTIFICATION --

  @impl WandererNotifier.NotifierBehaviour
  def send_new_tracked_character_notification(character) when is_map(character) do
    if env() == :test do
      character_id = Map.get(character, "character_id") || Map.get(character, "eve_id")
      handle_test_mode("DISCORD TEST CHARACTER NOTIFICATION: Character ID #{character_id}")
    else
      # Extract character ID for deduplication check
      character_id =
        Map.get(character, "character_id") ||
          Map.get(character, :character_id) ||
          Map.get(character, "eve_id") ||
          Map.get(character, :eve_id)

      # Check if this is a duplicate notification
      case character_id do
        nil ->
          Logger.warning(
            "[Discord] Cannot check for duplicate - character ID not found in: #{inspect(character)}"
          )

          # Proceed with notification as we can't deduplicate without an ID
          process_character_notification(character)

        id ->
          # Use the centralized deduplication logic from NotificationDeterminer
          case WandererNotifier.Services.NotificationDeterminer.check_deduplication(
                 :character,
                 id
               ) do
            {:ok, :send} ->
              # This is not a duplicate, proceed with notification
              Logger.info(
                "[Discord] Processing new character notification for character ID: #{id}"
              )

              process_character_notification(character)

            {:ok, :skip} ->
              # This is a duplicate, skip notification
              Logger.info(
                "[Discord] Skipping duplicate character notification for character ID: #{id}"
              )

              :ok

            {:error, reason} ->
              # Error during deduplication check, log it
              Logger.error("[Discord] Error checking character deduplication: #{reason}")
              # Default to sending notification in case of error
              Logger.info("[Discord] Proceeding with notification despite deduplication error")
              process_character_notification(character)
          end
      end
    end
  end

  # Separated the notification processing to its own function
  defp process_character_notification(character) do
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

  @impl WandererNotifier.NotifierBehaviour
  def send_new_system_notification(system) when is_map(system) do
    if env() == :test do
      system_id =
        if is_struct(system, MapSystem),
          do: system.solar_system_id,
          else: Map.get(system, "solar_system_id") || Map.get(system, :solar_system_id)

      handle_test_mode("DISCORD TEST SYSTEM NOTIFICATION: System ID #{system_id}")
    else
      # Extract system ID for deduplication check
      system_id =
        if is_struct(system, MapSystem),
          do: system.solar_system_id,
          else:
            Map.get(system, "solar_system_id") || Map.get(system, :solar_system_id) ||
              Map.get(system, "id")

      # Check if this is a duplicate notification
      case system_id do
        nil ->
          Logger.warning(
            "[Discord] Cannot check for duplicate - system ID not found in: #{inspect(system)}"
          )

          # Proceed with notification as we can't deduplicate without an ID
          process_system_notification(system)

        id ->
          # Use the centralized deduplication logic from NotificationDeterminer
          case WandererNotifier.Services.NotificationDeterminer.check_deduplication(:system, id) do
            {:ok, :send} ->
              # This is not a duplicate, proceed with notification
              Logger.info("[Discord] Processing new system notification for system ID: #{id}")
              process_system_notification(system)

            {:ok, :skip} ->
              # This is a duplicate, skip notification
              Logger.info("[Discord] Skipping duplicate system notification for system ID: #{id}")
              :ok

            {:error, reason} ->
              # Error during deduplication check, log it
              Logger.error("[Discord] Error checking system deduplication: #{reason}")
              # Default to sending notification in case of error
              Logger.info("[Discord] Proceeding with notification despite deduplication error")
              process_system_notification(system)
          end
      end
    end
  end

  # Separated the notification processing to its own function
  defp process_system_notification(system) do
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
        else
          # No recent kills, send the embed as is
          NotifierFactory.notify(:send_discord_embed, [discord_embed, :general])
        end
      else
        # Not a wormhole system or no recent kills, send the embed as is
        NotifierFactory.notify(:send_discord_embed, [discord_embed, :general])
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
end
