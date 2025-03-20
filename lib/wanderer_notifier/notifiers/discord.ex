defmodule WandererNotifier.Notifiers.Discord do
  @moduledoc """
  Discord notifier for WandererNotifier.
  Handles formatting and sending notifications to Discord.
  """
  require Logger
  alias WandererNotifier.Api.ESI.Service, as: ESIService
  alias WandererNotifier.Core.License
  alias WandererNotifier.Core.Stats
  alias WandererNotifier.Api.Http.Client, as: HttpClient
  alias WandererNotifier.Core.Config
  alias WandererNotifier.Notifiers.Formatter

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
    url = build_url(feature)
    Logger.info("Sending Discord embed to URL: #{url} for feature: #{inspect(feature)}")
    Logger.debug("Embed content: #{inspect(embed)}")

    payload = %{"embeds" => [embed]}

    with {:ok, json} <- Jason.encode(payload),
         {:ok, %{status_code: status}} when status in 200..299 <-
           HttpClient.request("POST", url, headers(), json) do
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

  The first kill notification after startup is always sent in enriched format
  regardless of license status to demonstrate the premium features.
  """
  @impl WandererNotifier.Notifiers.Behaviour
  def send_enriched_kill_embed(enriched_kill, kill_id) do
    if env() == :test do
      handle_test_mode("TEST MODE: Would send enriched kill embed for kill_id=#{kill_id}")
    else
      enriched_kill = fully_enrich_kill_data(enriched_kill)
      victim = Map.get(enriched_kill, "victim") || %{}
      victim_name = get_value(victim, ["character_name"], "Unknown Pilot")
      victim_ship = get_value(victim, ["ship_type_name"], "Unknown Ship")
      system_name = Map.get(enriched_kill, "solar_system_name") || "Unknown System"

      # Check if this is the first kill notification since startup using Stats GenServer
      is_first_notification = Stats.is_first_notification?(:kill)

      # For first notification, use enriched format regardless of license
      if is_first_notification || License.status().valid do
        # Mark that we've sent the first notification if this is it
        if is_first_notification do
          Stats.mark_notification_sent(:kill)
          Logger.info("Sending first kill notification in enriched format (startup message)")
        end

        # Use the formatter to create the notification
        generic_notification = Formatter.format_kill_notification(enriched_kill, kill_id)
        discord_embed = Formatter.to_discord_format(generic_notification)
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
            case ESIService.get_character_info(character_id) do
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
            case ESIService.get_ship_type_name(ship_type_id) do
              {:ok, ship_data} ->
                Map.put(victim, "ship_type_name", Map.get(ship_data, "name", "Unknown Ship"))

              _ ->
                Map.put_new(victim, "ship_type_name", "Unknown Ship")
            end
          end)

        _ ->
          victim
      end

    if get_value(victim, ["corporation_name"], "Unknown Corp") == "Unknown Corp" do
      victim =
        enrich_character(victim, "character_id", fn character_id ->
          case ESIService.get_character_info(character_id) do
            {:ok, char_data} ->
              case Map.get(char_data, "corporation_id") do
                nil ->
                  victim

                corp_id ->
                  case ESIService.get_corporation_info(corp_id) do
                    {:ok, corp_data} ->
                      Map.put(
                        victim,
                        "corporation_name",
                        Map.get(corp_data, "name", "Unknown Corp")
                      )

                    _ ->
                      Map.put_new(victim, "corporation_name", "Unknown Corp")
                  end
              end

            _ ->
              victim
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
    case Map.get(victim, "corporation_id") || Map.get(victim, :corporation_id) ||
           Map.get(char_data, "corporation_id") do
      nil ->
        victim

      corp_id ->
        case ESIService.get_corporation_info(corp_id) do
          {:ok, corp_data} ->
            Map.put(victim, "corporation_name", Map.get(corp_data, "name", "Unknown Corp"))

          _ ->
            Map.put_new(victim, "corporation_name", "Unknown Corp")
        end
    end
  end

  defp enrich_attacker_data(attacker) do
    attacker =
      case get_value(attacker, ["character_name"], nil) do
        nil ->
          enrich_character(attacker, "character_id", fn character_id ->
            case ESIService.get_character_info(character_id) do
              {:ok, char_data} ->
                Map.put(attacker, "character_name", Map.get(char_data, "name", "Unknown Pilot"))

              _ ->
                Map.put_new(attacker, "character_name", "Unknown Pilot")
            end
          end)

        _ ->
          attacker
      end

    case get_value(attacker, ["ship_type_name"], nil) do
      nil ->
        enrich_character(attacker, "ship_type_id", fn ship_type_id ->
          case ESIService.get_ship_type_name(ship_type_id) do
            {:ok, ship_data} ->
              Map.put(attacker, "ship_type_name", Map.get(ship_data, "name", "Unknown Ship"))

            _ ->
              Map.put_new(attacker, "ship_type_name", "Unknown Ship")
          end
        end)

      _ ->
        attacker
    end
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

      # Enrich the character data with ESI lookups if needed
      character = enrich_character_data(character)

      # Log the character data to help with debugging
      character_id = get_value(character, ["character_id", "eve_id"], "Unknown-ID")
      character_name = get_value(character, ["character_name", "name"], "Unknown Character")

      corporation_name =
        get_value(character, ["corporation_name", "corporationName", "corporation_ticker"], nil)

      Logger.debug(
        "Character notification for #{character_name} (#{character_id}), corp: #{corporation_name || "Unknown"}"
      )

      # Check if this is the first character notification since startup using Stats GenServer
      is_first_notification = Stats.is_first_notification?(:character)

      # For first notification, use enriched format regardless of license
      if is_first_notification || License.status().valid do
        # Mark that we've sent the first notification if this is it
        if is_first_notification do
          Stats.mark_notification_sent(:character)
          Logger.info("Sending first character notification in enriched format (startup message)")
        end

        # Use the formatter module to create the notification
        generic_notification = Formatter.format_character_notification(character)
        discord_embed = Formatter.to_discord_format(generic_notification)
        send_discord_embed(discord_embed, :character_tracking)
      else
        Logger.info("License not valid, sending plain text character notification")

        # Improved fallback for corporation name
        message =
          "New Character Tracked: #{character_name}" <>
            if corporation_name, do: " (#{corporation_name})", else: ""

        send_message(message, :character_tracking)
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

  # -- NEW SYSTEM NOTIFICATION --

  @doc """
  Sends a notification for a new system found.
  Expects a map with keys: "system_id" and optionally "system_name".
  If "system_name" is missing, falls back to a lookup.

  The first system notification after startup is always sent in enriched format
  regardless of license status to demonstrate the premium features.
  """
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

      # Normalize the system data
      system = normalize_system_data(system)

      # Extract system ID and name for logging
      system_id =
        Map.get(system, "solar_system_id") ||
          Map.get(system, :solar_system_id) ||
          Map.get(system, "system_id") ||
          Map.get(system, :system_id) ||
          Map.get(system, "systemId") ||
          Map.get(system, "id") ||
          "Unknown-ID"

      system_name =
        Map.get(system, "solar_system_name") ||
          Map.get(system, :solar_system_name) ||
          Map.get(system, "system_name") ||
          Map.get(system, :system_name) ||
          Map.get(system, "systemName") ||
          Map.get(system, "name") ||
          "Unknown System"

      Logger.debug("System notification for #{system_name} (ID: #{system_id})")

      # Check if system data contains the required type description
      system =
        if !has_type_description?(system) do
          # Try to enrich with static info if missing required fields
          enrich_with_static_info(system)
        else
          system
        end

      # Check if this is the first system notification since startup using Stats GenServer
      is_first_notification = Stats.is_first_notification?(:system)

      # Generate generic notification using formatter
      generic_notification = Formatter.format_system_notification(system)

      if generic_notification do
        # For first notification, use enriched format regardless of license or for valid license
        if is_first_notification || License.status().valid do
          # Mark that we've sent the first notification if this is it
          if is_first_notification do
            Stats.mark_notification_sent(:system)
            Logger.info("Sending first system notification in enriched format (startup message)")
          end

          # Convert the generic notification to a Discord-specific format
          discord_embed = Formatter.to_discord_format(generic_notification)

          # Add recent kills to the notification
          discord_embed_with_kills = add_recent_kills_to_embed(discord_embed, system)

          # Send the notification
          send_discord_embed(discord_embed_with_kills, :system_tracking)
        else
          # For non-licensed users after first message, send simple text
          Logger.info("License not valid, sending plain text system notification")
          type_desc = get_system_type_description(system)

          # Check for temporary_name to include in plain text format
          display_name =
            cond do
              # If we have both temporary and original name, combine them
              Map.has_key?(system, "temporary_name") &&
                Map.get(system, "temporary_name") &&
                Map.has_key?(system, "original_name") &&
                  Map.get(system, "original_name") ->
                temp_name = Map.get(system, "temporary_name")
                orig_name = Map.get(system, "original_name")
                "#{temp_name} (#{orig_name})"

              # If we only have temporary name
              Map.has_key?(system, "temporary_name") && Map.get(system, "temporary_name") ->
                Map.get(system, "temporary_name")

              # Check for display_name that might already be formatted correctly
              Map.has_key?(system, "display_name") && Map.get(system, "display_name") ->
                Map.get(system, "display_name")

              # Finally fall back to system_name
              true ->
                system_name
            end

          # Log the name resolution for debugging
          Logger.debug(
            "[Discord] Plain text notification using display_name: #{display_name} (original system_name: #{system_name})"
          )

          message = "New System Discovered: #{display_name} - #{type_desc}"

          # Add statics for wormhole systems
          is_wormhole =
            String.contains?(type_desc, "Class") || String.contains?(type_desc, "Wormhole")

          statics = get_system_statics(system)

          message =
            if is_wormhole && statics && statics != "" do
              "#{message} - Statics: #{statics}"
            else
              message
            end

          send_message(message, :system_tracking)
        end
      else
        Logger.error("Failed to format system notification: #{inspect(system)}")
        :error
      end
    end
  end

  # Helper to check if system has type description in any of the expected formats
  defp has_type_description?(system) do
    type_desc =
      Map.get(system, "type_description") ||
        Map.get(system, :type_description) ||
        get_in(system, ["staticInfo", "typeDescription"]) ||
        get_in(system, [:staticInfo, :typeDescription])

    type_desc != nil
  end

  # Helper to get system type description from any of the possible locations
  defp get_system_type_description(system) do
    type_desc =
      Map.get(system, "type_description") ||
        Map.get(system, :type_description) ||
        get_in(system, ["staticInfo", "typeDescription"]) ||
        get_in(system, [:staticInfo, :typeDescription])

    type_desc || "Unknown Type"
  end

  # Helper to get formatted statics list from system data
  defp get_system_statics(system) do
    # First try to get statics from various possible locations in the data
    statics =
      Map.get(system, "statics") ||
        Map.get(system, :statics) ||
        get_in(system, ["staticInfo", "statics"]) ||
        get_in(system, [:staticInfo, :statics]) ||
        get_in(system, ["data", "statics"]) ||
        get_in(system, [:data, :statics]) ||
        []

    Logger.debug("[get_system_statics] Raw statics: #{inspect(statics)}")

    # If we have a list of statics, format them
    if is_list(statics) && length(statics) > 0 do
      formatted =
        Enum.map_join(statics, ", ", fn static ->
          cond do
            # Handle map with name key (most common format)
            is_map(static) && Map.has_key?(static, "name") ->
              Map.get(static, "name")

            is_map(static) && Map.has_key?(static, :name) ->
              Map.get(static, :name)

            # Handle map with wormhole_code or code
            is_map(static) && Map.has_key?(static, "wormhole_code") ->
              Map.get(static, "wormhole_code")

            is_map(static) && Map.has_key?(static, :wormhole_code) ->
              Map.get(static, :wormhole_code)

            is_map(static) && Map.has_key?(static, "code") ->
              Map.get(static, "code")

            is_map(static) && Map.has_key?(static, :code) ->
              Map.get(static, :code)

            # Handle map with destination_class (can create better formatted output)
            is_map(static) &&
                (Map.has_key?(static, "destination_class") ||
                   Map.has_key?(static, :destination_class)) ->
              dest = Map.get(static, "destination_class") || Map.get(static, :destination_class)

              code =
                Map.get(static, "wormhole_code") ||
                  Map.get(static, :wormhole_code) ||
                  Map.get(static, "code") ||
                  Map.get(static, :code)

              if code && dest do
                "#{code} → #{dest}"
              else
                code || dest || inspect(static)
              end

            # Handle simple string static
            is_binary(static) ->
              static

            # Fallback for anything else
            true ->
              inspect(static)
          end
        end)

      Logger.debug("[get_system_statics] Formatted statics: #{formatted}")
      formatted
    else
      # Try to get statics info by system ID if we don't have it already
      system_id =
        Map.get(system, "system_id") ||
          Map.get(system, :system_id) ||
          Map.get(system, "solar_system_id") ||
          Map.get(system, :solar_system_id) ||
          Map.get(system, "systemId") ||
          Map.get(system, :systemId)

      if system_id && (system_id >= 31_000_000 && system_id < 32_000_000) do
        Logger.debug(
          "[get_system_statics] Attempting to fetch statics for wormhole system ID: #{system_id}"
        )

        try do
          # Use system_static_info module to fetch static info
          case WandererNotifier.Api.Map.SystemStaticInfo.get_system_static_info(system_id) do
            {:ok, static_info} ->
              statics_from_api = get_in(static_info, ["data", "statics"]) || []

              if is_list(statics_from_api) && length(statics_from_api) > 0 do
                # Format the statics from the API
                Enum.map_join(statics_from_api, ", ", fn static ->
                  cond do
                    is_map(static) ->
                      Map.get(static, "name") || Map.get(static, :name) ||
                        Map.get(static, "code") || Map.get(static, :code) ||
                        inspect(static)

                    is_binary(static) ->
                      static

                    true ->
                      ""
                  end
                end)
              else
                ""
              end

            {:error, _reason} ->
              ""
          end
        rescue
          _ -> ""
        end
      else
        ""
      end
    end
  end

  # Helper to enrich system with static information if available
  defp enrich_with_static_info(system) do
    # Extract system ID from any of the common fields where it might be found
    system_id =
      Map.get(system, "solar_system_id") ||
        Map.get(system, :solar_system_id) ||
        Map.get(system, "system_id") ||
        Map.get(system, :system_id) ||
        Map.get(system, "systemId") ||
        Map.get(system, :systemId) ||
        Map.get(system, "id") ||
        Map.get(system, :id)

    system_name =
      Map.get(system, "system_name") ||
        Map.get(system, :system_name) ||
        Map.get(system, "systemName") ||
        Map.get(system, :systemName) ||
        Map.get(system, "name") ||
        Map.get(system, :name) ||
        "Unknown System"

    Logger.info("[enrich_with_static_info] Processing system: #{system_name} (ID: #{system_id})")

    if system_id do
      # Ensure ID is in a format suitable for lookup
      system_id =
        if is_binary(system_id) do
          case Integer.parse(system_id) do
            {num, _} -> num
            :error -> system_id
          end
        else
          system_id
        end

      # Check if system's statics info is complete -
      # this means the system has non-empty statics if it's a wormhole, or has complete staticInfo
      # Has statics and they're not empty?
      # Has staticInfo with statics and they're not empty?
      has_complete_statics =
        (Map.has_key?(system, "statics") && is_list(system["statics"]) &&
           length(system["statics"]) > 0) ||
          (Map.has_key?(system, "staticInfo") &&
             is_map(system["staticInfo"]) &&
             Map.has_key?(system["staticInfo"], "statics") &&
             is_list(system["staticInfo"]["statics"]) &&
             length(system["staticInfo"]["statics"]) > 0)

      # Skip if system is not wormhole (no statics needed) or it already has complete statics
      if !is_wormhole_system_id?(system_id) || has_complete_statics do
        Logger.info(
          "[enrich_with_static_info] System is K-space or already has static info - no enrichment needed"
        )

        # Already has statics info or doesn't need it, no need to enrich
        system
      else
        Logger.info(
          "[enrich_with_static_info] Attempting to enrich wormhole system (ID: #{system_id})"
        )

        # Try to get static information for this system
        case WandererNotifier.Api.Map.SystemStaticInfo.get_system_static_info(system_id) do
          {:ok, static_info} ->
            Logger.info("[enrich_with_static_info] Successfully enriched system with static info")

            # Extract the full static info data if available
            static_info_data = Map.get(static_info, "data") || %{}

            # Get any existing system static info to merge with
            existing_static_info = Map.get(system, "staticInfo") || %{}

            # Create detailed static info map
            static_info_map = %{
              "typeDescription" =>
                static_info_data["type_description"] ||
                  static_info_data["class_title"] ||
                  existing_static_info["typeDescription"] ||
                  classify_system_by_id(system_id),
              "statics" =>
                static_info_data["statics"] ||
                  static_info["statics"] ||
                  [],
              "static_details" =>
                static_info_data["static_details"] ||
                  static_info["static_details"] ||
                  [],
              "effectName" =>
                static_info_data["effect_name"] ||
                  existing_static_info["effectName"],
              "isShattered" =>
                static_info_data["is_shattered"] ||
                  existing_static_info["isShattered"],
              "regionName" =>
                static_info_data["region_name"] ||
                  existing_static_info["regionName"]
            }

            # Add static info map to system
            system = Map.put(system, "staticInfo", static_info_map)

            # Also add main-level statics for easy access
            system =
              if Map.has_key?(static_info_data, "statics") &&
                   is_list(static_info_data["statics"]) &&
                   length(static_info_data["statics"]) > 0 do
                updated_system = Map.put(system, "statics", static_info_data["statics"])

                Logger.info(
                  "[enrich_with_static_info] Added statics to system: #{inspect(static_info_data["statics"])}"
                )

                updated_system
              else
                system
              end

            # Add static_details at the main level if available
            system =
              if Map.has_key?(static_info_data, "static_details") &&
                   is_list(static_info_data["static_details"]) &&
                   length(static_info_data["static_details"]) > 0 do
                updated_system =
                  Map.put(system, "static_details", static_info_data["static_details"])

                Logger.info(
                  "[enrich_with_static_info] Added static_details to system: #{inspect(static_info_data["static_details"])}"
                )

                updated_system
              else
                system
              end

            # Add any other useful fields
            system
            |> Map.put_new(
              "type_description",
              static_info_data["type_description"] || static_info_data["class_title"]
            )
            |> Map.put_new("class_title", static_info_data["class_title"])
            |> Map.put_new("effect_name", static_info_data["effect_name"])
            |> Map.put_new("is_shattered", static_info_data["is_shattered"])
            |> Map.put_new("region_name", static_info_data["region_name"])

          {:error, reason} ->
            Logger.warning(
              "[enrich_with_static_info] Failed to get static info: #{inspect(reason)}"
            )

            # Add minimal type info if lookup fails
            if !Map.has_key?(system, "staticInfo") && !Map.has_key?(system, :staticInfo) do
              type_desc = classify_system_by_id(system_id)
              Map.put(system, "staticInfo", %{"typeDescription" => type_desc, "statics" => []})
            else
              system
            end
        end
      end
    else
      Logger.warning("[enrich_with_static_info] Cannot enrich system without system ID")
      # Can't enrich without a system ID
      if !Map.has_key?(system, "staticInfo") && !Map.has_key?(system, :staticInfo) do
        Map.put(system, "staticInfo", %{"typeDescription" => "Unknown Space", "statics" => []})
      else
        system
      end
    end
  end

  # Helper to determine if a system ID is a wormhole
  defp is_wormhole_system_id?(system_id) when is_integer(system_id) do
    system_id >= 31_000_000 && system_id < 32_000_000
  end

  defp is_wormhole_system_id?(_), do: false

  # Helper to classify system by ID
  defp classify_system_by_id(system_id) when is_integer(system_id) do
    # J-space systems have IDs in the 31xxxxxx range
    cond do
      system_id >= 31_000_000 and system_id < 32_000_000 ->
        # Classify wormhole system based on ID range
        cond do
          system_id < 31_000_006 -> "Thera"
          system_id < 31_001_000 -> "Class 1"
          system_id < 31_002_000 -> "Class 2"
          system_id < 31_003_000 -> "Class 3"
          system_id < 31_004_000 -> "Class 4"
          system_id < 31_005_000 -> "Class 5"
          system_id < 31_006_000 -> "Class 6"
          true -> "Wormhole"
        end

      system_id < 30_000_000 ->
        "Unknown"

      system_id >= 30_000_000 and system_id < 31_000_000 ->
        if rem(system_id, 1000) < 500, do: "Low-sec", else: "Null-sec"

      true ->
        "K-space"
    end
  end

  defp classify_system_by_id(_), do: "Unknown"

  # Helper function to normalize system data by merging nested data if present
  defp normalize_system_data(system) do
    if Map.has_key?(system, "data") and is_map(system["data"]) do
      Map.merge(system, system["data"])
    else
      system
    end
  end

  # Adds recent kills information to a system notification embed
  defp add_recent_kills_to_embed(embed, system) do
    # Log the entire system object for debugging
    Logger.info("[Discord.add_recent_kills] System keys: #{inspect(Map.keys(system))}")

    # First try to get recent_kills that we've already loaded
    recent_kills = Map.get(system, "recent_kills")

    # Log what we found for recent_kills
    Logger.info("[Discord.add_recent_kills] Recent kills found: #{inspect(recent_kills != nil)}")

    if recent_kills != nil do
      Logger.info("[Discord.add_recent_kills] Recent kills count: #{length(recent_kills)}")
    end

    if is_list(recent_kills) && length(recent_kills) > 0 do
      Logger.info(
        "[Discord.add_recent_kills] Using #{length(recent_kills)} preloaded recent kills. First kill ID: #{inspect(Map.get(List.first(recent_kills), "killmail_id"))}"
      )

      process_recent_kills(embed, recent_kills)
    else
      # Fallback to fetching kills directly if not already provided
      # Try to get from the system struct if available
      system_id =
        Map.get(system, "solar_system_id") ||
          Map.get(system, :solar_system_id) ||
          Map.get(system, "system_id") ||
          Map.get(system, :system_id) ||
          get_in(system, ["system", "solar_system_id"])

      if system_id do
        Logger.info("[Discord.add_recent_kills] Trying direct API call for system: #{system_id}")

        case WandererNotifier.Api.ZKill.Service.get_system_kills(system_id, 5) do
          {:ok, zkill_kills} when is_list(zkill_kills) and length(zkill_kills) > 0 ->
            Logger.info(
              "[Discord.add_recent_kills] Direct API call found #{length(zkill_kills)} kills for system #{system_id}. First kill ID: #{inspect(Map.get(List.first(zkill_kills), "killmail_id"))}"
            )

            process_recent_kills(embed, zkill_kills)

          {:ok, []} ->
            Logger.info(
              "[Discord.add_recent_kills] No recent kills found for system #{system_id} from zKillboard"
            )

            # Add a message about no kills
            fields = embed["fields"] || []

            fields =
              fields ++
                [
                  %{
                    "name" => "Recent Kills in System",
                    "value" => "No recent kills found for this system.",
                    "inline" => false
                  }
                ]

            Map.put(embed, "fields", fields)

          {:error, reason} ->
            Logger.error(
              "Failed to fetch kills for system #{system_id} from zKillboard: #{inspect(reason)}"
            )

            embed
        end
      else
        embed
      end
    end
  end

  # Helper function to process recent kills and add them to the embed
  defp process_recent_kills(embed, kills) do
    Logger.info("[Discord.process_recent_kills] Processing #{length(kills)} kills")

    kills_text =
      Enum.map_join(kills, "\n", fn kill ->
        kill_id = Map.get(kill, "killmail_id")
        zkb = Map.get(kill, "zkb") || %{}
        hash = Map.get(zkb, "hash")

        Logger.info(
          "[Discord.process_recent_kills] Processing kill ID: #{kill_id}, has hash: #{hash != nil}"
        )

        enriched_kill =
          if kill_id != nil and hash do
            Logger.info("[Discord.process_recent_kills] Calling ESI API for kill: #{kill_id}")

            case ESIService.get_esi_kill_mail(kill_id, hash) do
              {:ok, killmail_data} ->
                Logger.info(
                  "[Discord.process_recent_kills] Successfully enriched kill #{kill_id}"
                )

                Map.merge(kill, killmail_data)

              {:error, reason} ->
                Logger.warning(
                  "[Discord.process_recent_kills] Failed to enrich kill #{kill_id}: #{inspect(reason)}"
                )

                kill

              other ->
                Logger.warning(
                  "[Discord.process_recent_kills] Unexpected response from ESI: #{inspect(other)}"
                )

                kill
            end
          else
            Logger.info(
              "[Discord.process_recent_kills] Skipping ESI enrichment for kill #{kill_id} (missing data)"
            )

            kill
          end

        victim = Map.get(enriched_kill, "victim") || %{}

        victim_name =
          if Map.has_key?(victim, "character_id") do
            character_id = Map.get(victim, "character_id")

            Logger.info("[Discord.process_recent_kills] Looking up character ID: #{character_id}")

            case ESIService.get_character_info(character_id) do
              {:ok, char_info} ->
                name = Map.get(char_info, "name", "Unknown Pilot")
                Logger.info("[Discord.process_recent_kills] Found character name: #{name}")
                name

              {:error, reason} ->
                Logger.warning(
                  "[Discord.process_recent_kills] Failed to get character info: #{inspect(reason)}"
                )

                "Unknown Pilot"

              _ ->
                Logger.warning(
                  "[Discord.process_recent_kills] Unexpected response from ESI character lookup"
                )

                "Unknown Pilot"
            end
          else
            Logger.info("[Discord.process_recent_kills] No character_id in victim data")
            "Unknown Pilot"
          end

        ship_type =
          if Map.has_key?(victim, "ship_type_id") do
            ship_type_id = Map.get(victim, "ship_type_id")

            Logger.info("[Discord.process_recent_kills] Looking up ship type ID: #{ship_type_id}")

            case ESIService.get_ship_type_name(ship_type_id) do
              {:ok, ship_info} ->
                name = Map.get(ship_info, "name", "Unknown Ship")
                Logger.info("[Discord.process_recent_kills] Found ship name: #{name}")
                name

              {:error, reason} ->
                Logger.warning(
                  "[Discord.process_recent_kills] Failed to get ship info: #{inspect(reason)}"
                )

                "Unknown Ship"

              _ ->
                Logger.warning(
                  "[Discord.process_recent_kills] Unexpected response from ESI ship lookup"
                )

                "Unknown Ship"
            end
          else
            Logger.info("[Discord.process_recent_kills] No ship_type_id in victim data")
            "Unknown Ship"
          end

        zkb = Map.get(kill, "zkb") || %{}
        kill_value = Map.get(zkb, "totalValue")

        kill_time =
          Map.get(kill, "killmail_time") || Map.get(enriched_kill, "killmail_time")

        time_ago =
          if kill_time do
            case DateTime.from_iso8601(kill_time) do
              {:ok, kill_datetime, _} ->
                diff_seconds = DateTime.diff(DateTime.utc_now(), kill_datetime)

                cond do
                  diff_seconds < 60 -> "just now"
                  diff_seconds < 3600 -> "#{div(diff_seconds, 60)}m ago"
                  diff_seconds < 86400 -> "#{div(diff_seconds, 3600)}h ago"
                  diff_seconds < 2_592_000 -> "#{div(diff_seconds, 86400)}d ago"
                  true -> "#{div(diff_seconds, 2_592_000)}mo ago"
                end

              _ ->
                ""
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

    # Add the kills field to the embed
    fields = embed["fields"] || []

    fields =
      fields ++
        [%{"name" => "Recent Kills in System", "value" => kills_text, "inline" => false}]

    Map.put(embed, "fields", fields)
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
      file_content = File.read!(file_path)
      filename = Path.basename(file_path)

      # Prepare the payload with content if title or description is provided
      payload_json =
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

      # Prepare the URL and headers
      channel = channel_id_for_feature(feature)
      url = "#{@base_url}/#{channel}/messages"

      headers = [
        {"Authorization", "Bot #{bot_token()}"},
        {"User-Agent", "WandererNotifier/1.0"}
      ]

      # Use HTTPoison directly for multipart requests
      boundary =
        "------------------------#{:crypto.strong_rand_bytes(12) |> Base.encode16(case: :lower)}"

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

      # Add content-type header with boundary
      headers = [{"Content-Type", "multipart/form-data; boundary=#{boundary}"} | headers]

      # Send the request
      case HTTPoison.post(url, body, headers) do
        {:ok, %{status_code: status_code, body: _response_body}} when status_code in 200..299 ->
          Logger.info("Successfully sent file to Discord")
          :ok

        {:ok, %{status_code: status_code, body: response_body}} ->
          error_msg = "Failed to send file to Discord: HTTP #{status_code}, #{response_body}"
          Logger.error(error_msg)
          {:error, error_msg}

        {:error, %HTTPoison.Error{reason: reason}} ->
          error_msg = "Failed to send file to Discord: #{inspect(reason)}"
          Logger.error(error_msg)
          {:error, error_msg}
      end
    end
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
end
