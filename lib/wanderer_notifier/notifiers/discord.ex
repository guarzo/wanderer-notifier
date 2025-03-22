defmodule WandererNotifier.Notifiers.Discord do
  @moduledoc """
  Discord notifier for WandererNotifier.
  Handles formatting and sending notifications to Discord.
  """
  use GenServer
  require Logger
  alias WandererNotifier.Core.License
  alias WandererNotifier.Core.Stats
  alias WandererNotifier.Api.Http.Client, as: HttpClient
  alias WandererNotifier.Core.Config
  alias WandererNotifier.Notifiers.StructuredFormatter
  alias WandererNotifier.Data.Character
  alias WandererNotifier.Data.MapSystem
  alias WandererNotifier.Data.Killmail

  @behaviour WandererNotifier.Notifiers.Behaviour

  # Default embed color
  @default_embed_color 0x3498DB

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

  defp channel_id_for_feature(feature) do
    Config.discord_channel_id_for(feature)
  end

  defp bot_token,
    do:
      get_config!(
        :discord_bot_token,
        "Discord bot token not configured. Please set :discord_bot_token in your configuration."
      )

  defp build_url(feature) do
    channel = channel_id_for_feature(feature)
    "#{@base_url}/#{channel}/messages"
  end

  defp headers do
    [
      {"Content-Type", "application/json"},
      {"Authorization", "Bot #{bot_token()}"}
    ]
  end

  # -- HELPER FUNCTIONS --

  # -- MESSAGE SENDING --

  @doc """
  Sends a plain text message to Discord.

  ## Parameters
    - message: The message to send
    - feature: Optional feature to determine the channel to use (defaults to :general)
  """
  @impl WandererNotifier.Notifiers.Behaviour
  def send_message(message, feature \\ :general) when is_binary(message) do
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

  @spec send_embed(any(), any(), any(), any(), atom()) :: :ok | {:error, any()}
  @doc """
  Sends a basic embed message to Discord.

  ## Parameters
    - title: The embed title
    - description: The embed description
    - url: Optional URL for the embed
    - color: Optional color for the embed
    - feature: Optional feature to determine the channel to use
  """
  @impl WandererNotifier.Notifiers.Behaviour
  def send_embed(
        title,
        description,
        url \\ nil,
        color \\ @default_embed_color,
        feature \\ :general
      ) do
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
      send_payload(payload, feature)
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

  ## Parameters
    - embed: The embed to send
    - feature: The feature to use for determining the channel (optional)
  """
  def send_discord_embed(embed, feature \\ :general) do
    if env() == :test do
      handle_test_mode("DISCORD MOCK EMBED (JSON): #{inspect(embed)}")
    else
      payload = %{"embeds" => [embed]}

      # Log the payload for debugging
      Logger.debug(
        "[Discord] Sending Discord embed payload: #{inspect(payload, pretty: true, limit: 5000)}"
      )

      send_payload(payload, feature)
    end
  end

  @doc """
  Sends a rich embed message for an enriched killmail.
  Expects the enriched killmail (and its nested maps) to have string keys.

  The first kill notification after startup is always sent in enriched format
  regardless of license status to demonstrate the premium features.
  """
  @impl WandererNotifier.Notifiers.Behaviour
  def send_enriched_kill_embed(enriched_kill, kill_id) do
    if env() == :test do
      handle_test_mode("TEST MODE: Would send enriched kill embed for kill_id=#{kill_id}")
    else
      # Convert to Killmail struct if it's not already one
      killmail =
        case enriched_kill do
          %Killmail{} ->
            enriched_kill

          _ ->
            # Create a Killmail struct from the enriched data
            Killmail.new(kill_id, Map.get(enriched_kill, "zkb", %{}), enriched_kill)
        end

      # Extract basic info for logging and non-premium fallback
      victim = Killmail.get_victim(killmail) || %{}
      victim_name = Map.get(victim, "character_name", "Unknown Pilot")
      victim_ship = Map.get(victim, "ship_type_name", "Unknown Ship")
      system_name = Map.get(killmail.esi_data || %{}, "solar_system_name", "Unknown System")

      # Check if this is the first kill notification since startup using Stats GenServer
      is_first_notification = Stats.is_first_notification?(:kill)

      # For first notification, use enriched format regardless of license
      if is_first_notification || License.status().valid do
        # Mark that we've sent the first notification if this is it
        if is_first_notification do
          Stats.mark_notification_sent(:kill)
          Logger.info("Sending first kill notification in enriched format (startup message)")
        end

        # Use the structured formatter to create the notification
        generic_notification = StructuredFormatter.format_kill_notification(killmail)
        discord_embed = StructuredFormatter.to_discord_format(generic_notification)
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

  # These functions are deprecated and will be used only as a fallback
  # New code should use the StructuredFormatter with proper domain structs

  # Format ISK values for display
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

  The first character notification after startup is always sent in enriched format
  regardless of license status to demonstrate the premium features.
  """
  @impl WandererNotifier.Notifiers.Behaviour
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

      # Log the original character data for debugging
      Logger.info("[Discord] Processing character notification")

      Logger.debug(
        "[Discord] Raw character data: #{inspect(character, pretty: true, limit: 5000)}"
      )

      # Check if this is the first character notification since startup
      is_first_notification = Stats.is_first_notification?(:character)

      # Mark that we've sent the first notification if this is it
      if is_first_notification do
        Stats.mark_notification_sent(:character)
        Logger.info("[Discord] Sending first character notification in enriched format")
      end

      if is_first_notification || License.status().valid do
        # Convert to Character struct if not already
        character_struct =
          if is_struct(character) && character.__struct__ == Character do
            character
          else
            Character.new(character)
          end

        # Create notification with StructuredFormatter
        generic_notification = StructuredFormatter.format_character_notification(character_struct)
        discord_embed = StructuredFormatter.to_discord_format(generic_notification)

        # Send the notification
        send_discord_embed(discord_embed, :character_tracking)
      else
        # For non-licensed users after first message, send plain text
        Logger.info("[Discord] License not valid, sending plain text character notification")

        # Convert to Character struct if not already for consistent field access
        character_struct =
          if is_struct(character) && character.__struct__ == Character do
            character
          else
            Character.new(character)
          end

        # Create plain text message using struct fields directly
        corporation_info =
          if Character.has_corporation?(character_struct) do
            " (#{character_struct.corporation_ticker})"
          else
            ""
          end

        message = "New Character Tracked: #{character_struct.name}#{corporation_info}"
        send_message(message, :character_tracking)
      end
    end
  end

  # -- NEW SYSTEM NOTIFICATION --

  @impl WandererNotifier.Notifiers.Behaviour
  def send_new_system_notification(system) when is_map(system) do
    if env() == :test do
      system_id = Map.get(system, "system_id") || Map.get(system, :system_id)
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
        # Generate notification with StructuredFormatter
        generic_notification = StructuredFormatter.format_system_notification(system_struct)
        discord_embed = StructuredFormatter.to_discord_format(generic_notification)

        # Add recent kills to the notification
        solar_system_id = system_struct.solar_system_id

        recent_kills =
          WandererNotifier.Services.KillProcessor.get_recent_kills()
          |> Enum.filter(fn kill ->
            kill_system_id = get_in(kill, ["esi_data", "solar_system_id"])
            kill_system_id == solar_system_id
          end)

        discord_embed =
          if recent_kills && recent_kills != [] do
            # We found recent kills in this system, add them to the embed
            recent_kills_field = %{
              "name" => "Recent Kills",
              "value" => format_recent_kills_list(recent_kills),
              "inline" => false
            }

            # Add the field to the existing embed
            Map.update(discord_embed, "fields", [recent_kills_field], fn fields ->
              fields ++ [recent_kills_field]
            end)
          else
            discord_embed
          end

        # Send the notification
        send_discord_embed(discord_embed, :system_tracking)
      else
        # For non-licensed users after first message, send simple text
        Logger.info("[Discord] License not valid, sending plain text system notification")

        # Create plain text message using struct fields directly
        display_name = MapSystem.format_display_name(system_struct)
        type_desc = MapSystem.get_type_description(system_struct)

        message = "New System Discovered: #{display_name} - #{type_desc}"

        # Add statics for wormhole systems
        if MapSystem.wormhole?(system_struct) && length(system_struct.statics) > 0 do
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

  defp send_payload(payload, feature) do
    url = build_url(feature)
    json_payload = Jason.encode!(payload)

    Logger.info("Sending Discord API request to URL: #{url} for feature: #{inspect(feature)}")
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
  Sends a file with an optional title and description.

  Implements the Notifiers.Behaviour callback, converts binary data to a file
  and sends it to Discord using the existing file upload functionality.

  ## Parameters
    - filename: The filename to use
    - file_data: The file content as binary data
    - title: Optional title for the message
    - description: Optional description for the message
    - feature: Optional feature to determine the channel to use
  """
  @impl WandererNotifier.Notifiers.Behaviour
  def send_file(filename, file_data, title \\ nil, description \\ nil, feature \\ :general) do
    Logger.info("Discord.Notifier.send_file called with filename: #{filename}")

    if env() == :test do
      handle_test_mode("DISCORD MOCK FILE: #{filename} - #{title || "No title"}")
      :ok
    else
      # Create a temporary file to hold the binary data
      temp_file =
        Path.join(
          System.tmp_dir!(),
          "#{:crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)}-#{filename}"
        )

      try do
        # Write the file data to the temp file
        File.write!(temp_file, file_data)

        # Use the existing file sending method
        send_file_path(temp_file, title, description, feature)
      after
        # Clean up the temp file
        File.rm(temp_file)
      end
    end
  end

  # Rename the existing send_file function to send_file_path to avoid conflicts
  def send_file_path(file_path, title \\ nil, description \\ nil, feature \\ :general) do
    Logger.info("Discord.Notifier.send_file_path called with file: #{file_path}")

    if env() == :test do
      handle_test_mode("DISCORD MOCK FILE: #{file_path} - #{title || "No title"}")
    else
      # Build the form data for the file upload
      send_real_file(file_path, title, description, feature)
    end
  end

  # Helper function to send a real file in production mode
  defp send_real_file(file_path, title, description, feature) do
    file_content = File.read!(file_path)
    filename = Path.basename(file_path)

    # Prepare the payload and other components
    payload_json = prepare_file_payload(title, description)

    {url, headers, body} =
      prepare_multipart_request(file_path, filename, file_content, payload_json, feature)

    # Send the request
    case HTTPoison.post(url, body, headers) do
      {:ok, %{status_code: status}} when status in 200..299 ->
        Logger.info("Discord file sent successfully with status #{status}")

        # Use the increment/1 function with a specific key instead of the undefined increment_file_sent/0
        Stats.increment("discord_files_sent")
        {:ok, Jason.decode!(body)}

      {:ok, %{status_code: status, body: body}} ->
        Logger.error("Discord file send failed with status #{status}: #{body}")
        {:error, "HTTP #{status}: #{body}"}

      {:error, reason} ->
        Logger.error("Discord file request failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  # Prepare payload JSON for file upload
  defp prepare_file_payload(title, description) do
    if title || description do
      content =
        case {title, description} do
          {nil, nil} -> ""
          {title, nil} -> title
          {nil, description} -> description
          {title, description} -> "#{title}\n#{description}"
        end

      Jason.encode!(%{"content" => content})
    else
      Jason.encode!(%{})
    end
  end

  # Prepare multipart request components
  defp prepare_multipart_request(_file_path, filename, file_content, payload_json, feature) do
    # Create unique boundary
    boundary = "------------------------#{:rand.uniform(999_999_999_999)}"

    # Prepare the URL and headers
    channel = channel_id_for_feature(feature)
    url = "#{@base_url}/#{channel}/messages"

    # Generate boundary and headers
    headers = [
      {"Authorization", "Bot #{bot_token()}"},
      {"User-Agent", "WandererNotifier/1.0"},
      {"Content-Type", "multipart/form-data; boundary=#{boundary}"}
    ]

    # Create multipart body manually
    body =
      "--#{boundary}\r\n" <>
        "Content-Disposition: form-data; name=\"file\"; filename=\"#{filename}\"\r\n" <>
        "Content-Type: application/octet-stream\r\n\r\n" <>
        file_content <>
        "\r\n--#{boundary}\r\n" <>
        "Content-Disposition: form-data; name=\"payload_json\"\r\n\r\n" <>
        payload_json <>
        "\r\n--#{boundary}--\r\n"

    {url, headers, body}
  end

  @doc """
  Sends an embed with an image to Discord.

  ## Parameters
    - title: The title of the embed
    - description: The description content
    - image_url: URL of the image to display
    - color: Optional color for the embed
    - feature: Optional feature to determine which channel to use
  """
  @impl WandererNotifier.Notifiers.Behaviour
  def send_image_embed(
        title,
        description,
        image_url,
        color \\ @default_embed_color,
        feature \\ :general
      ) do
    Logger.info(
      "Discord.Notifier.send_image_embed called with title: #{title}, image_url: #{image_url || "nil"}, feature: #{feature}"
    )

    if env() == :test do
      handle_test_mode(
        "DISCORD MOCK IMAGE EMBED: #{title} - #{description} with image: #{image_url} (feature: #{feature})"
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

      Logger.info(
        "Discord image embed payload built, sending to Discord API with feature: #{feature}"
      )

      send_payload(payload, feature)
    end
  end

  def send_new_mapped_system_notification(system) when is_map(system) do
    if env() == :test do
      system_id = Map.get(system, "id") || Map.get(system, "solar_system_id")
      handle_test_mode("DISCORD TEST SYSTEM NOTIFICATION: System ID #{system_id}")
    else
      try do
        Stats.increment(:systems)
      rescue
        _ -> :ok
      end

      # Log the original system data for debugging
      Logger.info("[Discord] Processing system notification")
      Logger.debug("[Discord] Raw system data: #{inspect(system, pretty: true, limit: 5000)}")

      # Check if this is the first system notification since startup
      is_first_notification = Stats.is_first_notification?(:system)

      # Mark that we've sent the first notification if this is it
      if is_first_notification do
        Stats.mark_notification_sent(:system)
        Logger.info("[Discord] Sending first system notification in enriched format")
      end

      # Convert to MapSystem struct if not already
      system_struct =
        if is_struct(system) && system.__struct__ == MapSystem do
          system
        else
          # Create MapSystem struct from the provided data
          MapSystem.new(system)
        end

      # Enrich with system static info for wormhole systems
      Logger.info("[Discord] Checking system for wormhole enrichment")
      Logger.info("[Discord] - is_wormhole?: #{MapSystem.wormhole?(system_struct)}")
      Logger.info("[Discord] - solar_system_id: #{inspect(system_struct.solar_system_id)}")
      Logger.info("[Discord] - type_description: #{inspect(system_struct.type_description)}")
      Logger.info("[Discord] - system_type: #{inspect(system_struct.system_type)}")

      system_struct =
        if MapSystem.wormhole?(system_struct) && system_struct.solar_system_id do
          Logger.info(
            "[Discord] Enriching wormhole system with static info: #{system_struct.solar_system_id}"
          )

          # Use the existing enrich_system function instead of duplicating the logic
          Logger.info("[Discord] Calling SystemStaticInfo.enrich_system")

          enrichment_result =
            WandererNotifier.Api.Map.SystemStaticInfo.enrich_system(system_struct)

          Logger.info("[Discord] Enrichment result: #{inspect(enrichment_result)}")

          case enrichment_result do
            {:ok, enriched_system} ->
              Logger.info("[Discord] Successfully enriched system with static info")
              Logger.info("[Discord] Enriched statics: #{inspect(enriched_system.statics)}")

              Logger.info(
                "[Discord] Enriched static_details: #{inspect(enriched_system.static_details)}"
              )

              Logger.info(
                "[Discord] Enriched class_title: #{inspect(enriched_system.class_title)}"
              )

              enriched_system

            {:error, reason} ->
              Logger.warning(
                "[Discord] Failed to enrich system with static info: #{inspect(reason)}"
              )

              system_struct
          end
        else
          Logger.info(
            "[Discord] System not a wormhole or missing solar_system_id, skipping enrichment"
          )

          system_struct
        end

      # Log the enriched MapSystem struct for debugging
      Logger.info("[Discord] Enriched MapSystem struct:")
      Logger.info("[Discord] - name: #{inspect(system_struct.name)}")
      Logger.info("[Discord] - original_name: #{inspect(system_struct.original_name)}")
      Logger.info("[Discord] - temporary_name: #{inspect(system_struct.temporary_name)}")
      Logger.info("[Discord] - solar_system_id: #{inspect(system_struct.solar_system_id)}")
      Logger.info("[Discord] - type_description: #{inspect(system_struct.type_description)}")
      Logger.info("[Discord] - statics: #{inspect(system_struct.statics)}")
      Logger.info("[Discord] - static_details: #{inspect(system_struct.static_details)}")
      Logger.info("[Discord] - system_type: #{inspect(system_struct.system_type)}")
      Logger.info("[Discord] - class_title: #{inspect(system_struct.class_title)}")
      Logger.info("[Discord] - effect_name: #{inspect(system_struct.effect_name)}")
      Logger.info("[Discord] - region_name: #{inspect(system_struct.region_name)}")

      if is_first_notification || License.status().valid do
        # Create notification with StructuredFormatter
        generic_notification = StructuredFormatter.format_system_notification(system_struct)
        discord_embed = StructuredFormatter.to_discord_format(generic_notification)

        # Add recent kills to the embed if available
        solar_system_id = system_struct.solar_system_id

        recent_kills =
          WandererNotifier.Services.KillProcessor.get_recent_kills()
          |> Enum.filter(fn kill ->
            kill_system_id = get_in(kill, ["esi_data", "solar_system_id"])
            kill_system_id == solar_system_id
          end)

        discord_embed =
          if recent_kills && recent_kills != [] do
            # We found recent kills in this system, add them to the embed
            recent_kills_field = %{
              "name" => "Recent Kills",
              "value" => format_recent_kills_list(recent_kills),
              "inline" => false
            }

            # Add the field to the existing embed
            Map.update(discord_embed, "fields", [recent_kills_field], fn fields ->
              fields ++ [recent_kills_field]
            end)
          else
            discord_embed
          end

        # Send the notification
        send_discord_embed(discord_embed, :system_mapping)
      else
        # For non-licensed users after first message, send plain text
        Logger.info("[Discord] License not valid, sending plain text system notification")

        # Create plain text message using struct fields directly
        formatted_name = MapSystem.format_display_name(system_struct)
        type_desc = MapSystem.get_type_description(system_struct)

        message = "New System Mapped: #{formatted_name} - #{type_desc}"

        # Add statics for wormhole systems
        if MapSystem.wormhole?(system_struct) && length(system_struct.statics) > 0 do
          statics = Enum.map_join(system_struct.statics, ", ", &(&1["name"] || &1[:name] || ""))
          updated_message = "#{message} - Statics: #{statics}"
          send_message(updated_message, :system_mapping)
        else
          send_message(message, :system_mapping)
        end
      end
    end
  end

  # Format a list of recent kills for system notification
  defp format_recent_kills_list(kills) when is_list(kills) do
    Logger.info("[Discord.format_recent_kills_list] Formatting #{length(kills)} kills")

    Enum.map_join(kills, "\n", fn kill ->
      # Extract kill ID using various possible keys
      kill_id =
        Map.get(kill, "killmail_id") ||
          Map.get(kill, :killmail_id) ||
          get_in(kill, ["data", "killmail_id"]) ||
          get_in(kill, [:data, :killmail_id])

      # Log the kill ID for debugging
      Logger.debug("[Discord.format_recent_kills_list] Processing kill ID: #{kill_id}")

      # Get victim data, handling different formats
      victim =
        Map.get(kill, "victim") ||
          Map.get(kill, :victim) ||
          get_in(kill, ["data", "victim"]) ||
          get_in(kill, [:data, :victim]) ||
          %{}

      # Extract victim name, checking multiple possible key formats
      victim_name =
        Map.get(victim, "character_name") ||
          Map.get(victim, :character_name) ||
          "Unknown Pilot"

      # Extract ship name
      ship_name =
        Map.get(victim, "ship_type_name") ||
          Map.get(victim, :ship_type_name) ||
          "Unknown Ship"

      # Get zkb data to extract value
      zkb =
        Map.get(kill, "zkb") ||
          Map.get(kill, :zkb) ||
          get_in(kill, ["data", "zkb"]) ||
          get_in(kill, [:data, :zkb]) ||
          %{}

      # Extract value from zkb data
      value =
        Map.get(zkb, "totalValue") ||
          Map.get(zkb, :totalValue)

      formatted_value =
        if value,
          do: " - #{format_isk_value(value)}",
          else: ""

      # Create formatted string with zkillboard link
      "[#{victim_name}](https://zkillboard.com/kill/#{kill_id}/) - #{ship_name}#{formatted_value}"
    end)
  end

  defp format_recent_kills_list(_), do: "No recent kills"

  # -- GenServer callback for behaviour --
  @impl GenServer
  def init(init_arg) do
    {:ok, init_arg}
  end
end
