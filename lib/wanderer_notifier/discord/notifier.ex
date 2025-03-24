defmodule WandererNotifier.Discord.Notifier do
  @moduledoc """
  Discord notification service.
  Handles sending notifications to Discord.
  """
  require Logger
  alias WandererNotifier.Logger, as: AppLogger
  alias WandererNotifier.Api.Http.Client, as: HttpClient
  alias WandererNotifier.Core.Stats
  alias WandererNotifier.Core.License
  alias WandererNotifier.Notifiers.StructuredFormatter
  alias WandererNotifier.Data.Killmail
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
    # Always log in test mode for test assertions
    Logger.info(log_message)
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

  # Format ISK values for display - moved from removed code
  defp format_isk_value(value) when is_float(value) or is_integer(value) do
    cond do
      value < 1000 -> "<1k ISK"
      value < 1_000_000 -> "#{round(value / 1000)}k ISK"
      value < 1_000_000_000 -> "#{round(value / 1_000_000)}M ISK"
      true -> "#{Float.round(value / 1_000_000_000, 2)}B ISK"
    end
  end

  defp format_isk_value(_), do: "0 ISK"

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
    process_kills_for_notification(recent_kills, message)
  end

  # Process kills list for test notification
  defp process_kills_for_notification([], message) do
    # No recent kills available
    %{"content" => message, "embeds" => []}
  end

  defp process_kills_for_notification(recent_kills, message) do
    recent_kill = List.first(recent_kills)
    kill_id = Map.get(recent_kill, "killmail_id") || Map.get(recent_kill, :killmail_id)

    if kill_id do
      process_kill_with_id(recent_kill, kill_id)
    else
      %{"content" => message, "embeds" => []}
    end
  end

  # Process a kill that has a valid ID
  defp process_kill_with_id(recent_kill, kill_id) do
    # Convert to Killmail struct if needed
    killmail = convert_to_killmail(recent_kill, kill_id)
    send_enriched_kill_embed(killmail, kill_id)
  end

  # Convert kill data to a Killmail struct
  defp convert_to_killmail(kill_data, kill_id) do
    if is_struct(kill_data, Killmail) do
      kill_data
    else
      Killmail.new(kill_id, Map.get(kill_data, "zkb", %{}))
    end
  end

  @spec send_embed(any(), any()) :: :ok | {:error, any()}
  @doc """
  Sends a basic embed message to Discord.
  """
  @impl WandererNotifier.NotifierBehaviour
  def send_embed(title, description, url \\ nil, color \\ @default_embed_color) do
    AppLogger.processor_info("Discord embed requested",
      title: title,
      url: url || "nil"
    )

    if env() == :test do
      handle_test_mode("DISCORD MOCK EMBED: #{title} - #{description}")
    else
      payload =
        if title == "Test Kill" do
          process_test_embed(title, description, url, color)
        else
          build_embed_payload(title, description, url, color)
        end

      AppLogger.processor_info("Discord embed payload built, sending to Discord API")
      send_payload(payload)
    end
  end

  defp process_test_embed(title, description, url, color) do
    recent_kills = WandererNotifier.Services.KillProcessor.get_recent_kills() || []

    if recent_kills == [] do
      build_embed_payload(title, description, url, color)
    else
      process_embed_with_kill(title, description, url, color, recent_kills)
    end
  end

  # Helper function to process an embed with kill data
  defp process_embed_with_kill(title, description, url, color, recent_kills) do
    recent_kill = List.first(recent_kills)
    kill_id = Map.get(recent_kill, "killmail_id") || Map.get(recent_kill, :killmail_id)

    if kill_id do
      # Convert to Killmail struct if needed
      killmail = convert_to_killmail_struct(recent_kill)
      send_enriched_kill_embed(killmail, kill_id)
    else
      build_embed_payload(title, description, url, color)
    end
  end

  # Helper function to convert a kill to a Killmail struct if needed
  defp convert_to_killmail_struct(recent_kill) do
    if is_struct(recent_kill, Killmail) do
      recent_kill
    else
      Killmail.new(recent_kill["killmail_id"], recent_kill["zkb"])
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
    AppLogger.processor_debug("Preparing to format killmail for Discord", kill_id: kill_id)

    # Ensure the killmail has a system name if system_id is present
    enriched_killmail = enrich_with_system_name(killmail)

    formatted_embed = StructuredFormatter.format_kill_notification(enriched_killmail)
    send_to_discord(formatted_embed, "kill")
  end

  # Ensure the killmail has a system name if missing
  defp enrich_with_system_name(%Killmail{} = killmail) do
    # Get system_id from the esi_data
    system_id = get_system_id_from_killmail(killmail)

    # Check if we need to get the system name
    if system_id do
      # Get system name using the same approach as in kill_processor
      system_name = get_system_name(system_id)

      AppLogger.processor_debug("Enriching killmail with system name",
        system_id: system_id,
        system_name: system_name
      )

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
      {:error, :not_found} -> "Unknown-#{system_id}"
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
  def send_new_tracked_character_notification(character)
      when is_struct(character, WandererNotifier.Data.Character) do
    if env() == :test do
      handle_test_mode(
        "DISCORD TEST CHARACTER NOTIFICATION: Character ID #{character.character_id}"
      )
    else
      # Extract character ID for deduplication check
      character_id = character.character_id

      # Check if this is a duplicate notification
      case WandererNotifier.Services.NotificationDeterminer.check_deduplication(
             :character,
             character_id
           ) do
        {:ok, :send} ->
          # This is not a duplicate, proceed with notification
          AppLogger.processor_info("Processing new character notification",
            character_name: character.name,
            character_id: character.character_id
          )

          # Create notification with StructuredFormatter
          generic_notification = StructuredFormatter.format_character_notification(character)
          send_to_discord(generic_notification, :character_tracking)

        {:ok, :skip} ->
          # This is a duplicate, skip notification
          AppLogger.processor_info("Skipping duplicate character notification",
            character_name: character.name,
            character_id: character.character_id
          )

          :ok

        {:error, reason} ->
          # Error during deduplication check, log it
          AppLogger.processor_error("Error checking character deduplication",
            character_id: character_id,
            character_name: character.name,
            error: inspect(reason)
          )

          # Default to sending notification in case of error
          AppLogger.processor_info("Proceeding with notification despite deduplication error",
            character_id: character_id,
            character_name: character.name
          )

          # Create notification with StructuredFormatter
          generic_notification = StructuredFormatter.format_character_notification(character)
          send_to_discord(generic_notification, :character_tracking)
      end
    end
  end

  # -- NEW SYSTEM NOTIFICATION --

  @impl WandererNotifier.NotifierBehaviour
  def send_new_system_notification(system)
      when is_struct(system, WandererNotifier.Data.MapSystem) do
    if env() == :test do
      handle_test_mode("DISCORD TEST SYSTEM NOTIFICATION: System ID #{system.solar_system_id}")
    else
      # Extract system ID for deduplication check
      system_id = system.solar_system_id

      # Check if this is a duplicate notification
      case WandererNotifier.Services.NotificationDeterminer.check_deduplication(
             :system,
             system_id
           ) do
        {:ok, :send} ->
          # This is not a duplicate, proceed with notification
          handle_new_system_notification(system, system_id)

        {:ok, :skip} ->
          # This is a duplicate, skip notification
          AppLogger.processor_info("Skipping duplicate system notification",
            system_id: system_id,
            system_name: system.name
          )

          :ok

        {:error, reason} ->
          # Error during deduplication check, log it
          AppLogger.processor_error("Error checking system deduplication",
            system_id: system_id,
            system_name: system.name,
            error: inspect(reason)
          )

          # Default to sending notification in case of error
          AppLogger.processor_info("Proceeding with notification despite deduplication error",
            system_id: system_id,
            system_name: system.name
          )

          # Recursively call self with same system data
          send_new_system_notification(system)
      end
    end
  end

  # Handle sending a new system notification after deduplication check
  defp handle_new_system_notification(system, system_id) do
    AppLogger.processor_info("Processing new system notification",
      system_id: system_id,
      system_name: system.name
    )

    try do
      Stats.increment(:systems)
    rescue
      _ -> :ok
    end

    # Check if this is the first system notification since startup
    is_first_notification = Stats.is_first_notification?(:system)

    # Mark that we've sent the first notification if this is it
    if is_first_notification do
      Stats.mark_notification_sent(:system)
      AppLogger.processor_info("Sending first system notification in enriched format")
    end

    # For first notification or with valid license, use enriched format
    if is_first_notification || License.status().valid do
      send_enriched_system_notification(system)
    else
      send_plain_system_notification(system)
    end
  end

  # Send an enriched system notification with full formatting
  defp send_enriched_system_notification(system) do
    # Create notification with StructuredFormatter
    generic_notification = StructuredFormatter.format_system_notification(system)
    discord_embed = StructuredFormatter.to_discord_format(generic_notification)

    # Add recent kills to the embed if available and system is a wormhole
    if WandererNotifier.Data.MapSystem.wormhole?(system) do
      maybe_add_recent_kills_to_embed(discord_embed, system.solar_system_id)
    else
      # Not a wormhole system, send the embed as is
      NotifierFactory.notify(:send_discord_embed, [discord_embed, :general])
    end
  end

  # Check for recent kills in the system and add them to the embed if found
  defp maybe_add_recent_kills_to_embed(discord_embed, solar_system_id) do
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
  end

  # Send a plain text system notification for non-licensed users
  defp send_plain_system_notification(system) do
    AppLogger.processor_info("License not valid, sending plain text system notification",
      system_id: system.solar_system_id,
      system_name: system.name
    )

    # Create plain text message using struct fields directly
    display_name = WandererNotifier.Data.MapSystem.format_display_name(system)
    type_desc = WandererNotifier.Data.MapSystem.get_type_description(system)

    message = "New System Discovered: #{display_name} - #{type_desc}"

    # Add statics for wormhole systems
    if WandererNotifier.Data.MapSystem.wormhole?(system) && length(system.statics) > 0 do
      statics_text = format_statics_list(system.statics)
      updated_message = "#{message} - Statics: #{statics_text}"
      send_message(updated_message, :system_tracking)
    else
      send_message(message, :system_tracking)
    end
  end

  # Helper to format a list of statics in a plain text format
  defp format_statics_list(statics) when is_list(statics) do
    Enum.map_join(statics, ", ", fn static ->
      cond do
        is_map(static) && (Map.has_key?(static, "name") || Map.has_key?(static, :name)) ->
          Map.get(static, "name") || Map.get(static, :name)

        is_binary(static) ->
          static

        true ->
          "Unknown"
      end
    end)
  end

  defp format_statics_list(_), do: "None"

  # -- HELPER FOR SENDING PAYLOAD --

  defp send_payload(payload, feature \\ nil) do
    url = build_url()
    json_payload = Jason.encode!(payload)

    AppLogger.processor_info("Sending Discord API request",
      url: url,
      feature: feature
    )

    AppLogger.processor_debug("Discord API payload details",
      payload_size: byte_size(json_payload)
    )

    case HttpClient.request("POST", url, headers(), json_payload) do
      {:ok, %{status_code: status}} when status in 200..299 ->
        AppLogger.processor_info("Discord API request successful",
          status: status,
          feature: feature
        )

        :ok

      {:ok, %{status_code: status, body: body}} ->
        AppLogger.processor_error("Discord API request failed",
          status: status,
          response: body,
          feature: feature
        )

        {:error, body}

      {:error, err} ->
        AppLogger.processor_error("Discord API request error",
          error: inspect(err),
          feature: feature
        )

        {:error, err}
    end
  end

  # -- FILE SENDING --

  @doc """
  Sends a file to Discord with an optional title and description.
  """
  @impl WandererNotifier.NotifierBehaviour
  def send_file(filename, file_data, title \\ nil, description \\ nil) do
    AppLogger.processor_info("Sending file to Discord",
      filename: filename,
      title: title
    )

    if env() == :test do
      handle_test_mode("DISCORD MOCK FILE: #{filename} - #{title || "No title"}")
    else
      url = build_url()

      {_boundary, body, file_headers} =
        prepare_file_upload(filename, file_data, title, description)

      send_multipart_request(url, file_headers, body)
    end
  end

  # Prepare the multipart data for file upload
  defp prepare_file_upload(filename, file_data, title, description) do
    # Create form data with file and JSON payload
    boundary = "----------------------------#{:rand.uniform(999_999_999)}"

    # Prepare JSON payload
    json_payload = create_file_json_payload(filename, title, description)

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

    {boundary, body, file_headers}
  end

  # Create the JSON payload for file upload
  defp create_file_json_payload(filename, title, description) do
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
  end

  # Send a multipart request
  defp send_multipart_request(url, headers, body) do
    case HttpClient.request("POST", url, headers, body) do
      {:ok, %{status_code: status}} when status in 200..299 ->
        AppLogger.processor_info("Successfully sent file to Discord", status: status)
        :ok

      {:ok, %{status_code: status, body: response_body}} ->
        AppLogger.processor_error("Failed to send file to Discord",
          status: status,
          response: inspect(response_body)
        )

        {:error, "Discord API error: #{status}"}

      {:error, reason} ->
        AppLogger.processor_error("Error sending file to Discord", error: inspect(reason))
        {:error, reason}
    end
  end

  @doc """
  Sends an embed with an image to Discord.
  """
  @impl WandererNotifier.NotifierBehaviour
  def send_image_embed(title, description, image_url, color \\ @default_embed_color) do
    AppLogger.processor_info("Sending image embed to Discord",
      title: title,
      image_url: image_url || "nil"
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

      AppLogger.processor_info("Discord image embed payload built, sending to Discord API")
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
