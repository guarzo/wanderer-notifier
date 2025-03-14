defmodule WandererNotifier.Discord.Notifier do
  @moduledoc """
  Discord notification service.
  Handles sending notifications to Discord.
  """
  require Logger
  alias WandererNotifier.Cache.Repository, as: CacheRepo
  alias WandererNotifier.Http.Client, as: HttpClient

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
  Sends a rich embed message for an enriched killmail.
  Expects the enriched killmail (and its nested maps) to have string keys.
  """
  def send_enriched_kill_embed(enriched_kill, kill_id) do
    if env() == :test do
      if @verbose_logging, do: Logger.info("DISCORD TEST KILL EMBED: Kill ID #{kill_id}")
      :ok
    else
      try do
        WandererNotifier.Stats.increment(:kills)
      rescue
        _ -> :ok
      end

      normalized = normalize_keys(enriched_kill)

      # Check if this is a properly enriched kill or a raw/non-enriched kill
      is_properly_enriched = is_kill_properly_enriched?(normalized)

      system_name =
        case Map.get(normalized, "system_name") do
          nil ->
            solar_system_id = Map.get(normalized, "solar_system_id")
            resolve_system_name(solar_system_id)
          name ->
            name
        end

      # Only include zkill link and value for properly enriched kills
      kill_url = if is_properly_enriched, do: "https://zkillboard.com/kill/#{kill_id}/", else: nil
      title = "Ship destroyed in #{system_name}"
      description = build_description(normalized)
      total_value = get_total_value(normalized)
      formatted_value = format_isk_value(total_value)

      # Prepare data for both embed and plain text versions
      victim = Map.get(normalized, "victim", %{})
      victim_data = extract_entity(victim)

      # Plain text version (used for invalid license)
      plain_text = "Kill in #{system_name}: #{victim_data.name} lost a #{victim_data.ship}"

      # Rich embed version (used for valid license)
      embed_data = %{
        title: title,
        description: description,
        url: kill_url,
        color: @default_embed_color,
        footer_text: if(is_properly_enriched, do: "Value: #{formatted_value}", else: nil)
      }

      # Additional embed elements for the rich version
      victim_ship_type = Map.get(victim, "ship_type_id")
      thumbnail_url = if victim_ship_type, do: "https://images.evetech.net/types/#{victim_ship_type}/render", else: nil

      attackers = Map.get(normalized, "attackers", [])
      top_attacker = get_top_attacker(attackers)
      corp_id = Map.get(top_attacker, "corporation_id")
      author_icon_url = if corp_id, do: "https://images.evetech.net/corporations/#{corp_id}/logo", else: nil

      # Add these to the embed data
      embed_data = Map.merge(embed_data, %{
        thumbnail_url: thumbnail_url,
        author_name: "Kill",
        author_icon_url: author_icon_url
      })

      # Add security status field if available
      security_status = Map.get(normalized, "security_status") || Map.get(normalized, "security")
      embed_data_with_security = if security_status do
        formatted_security = format_security_status(security_status)
        Map.update!(embed_data, :fields, fn fields ->
          fields ++ [%{
            name: "Security",
            value: formatted_security,
            inline: true
          }]
        end)
      else
        embed_data
      end

      # Send notification with license check
      send_notification_with_license_check(plain_text, embed_data_with_security)
    end
  end

  @doc """
  Sends a notification for a new tracked character.
  Expects a map with keys: "character_id", "character_name", "corporation_id", "corporation_name".
  If names are missing, ESI lookups are performed.
  """
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

      # Log the character data for debugging
      Logger.info("CHARACTER NOTIFICATION DATA: #{inspect(character, pretty: true, limit: 10000)}")
      Logger.info("Character keys: #{inspect(Map.keys(character))}")

      # Extract the EVE ID - only accept numeric IDs
      eve_id = cond do
        # Try to get from the top level first (most common case)
        is_binary(character["character_id"]) && is_valid_numeric_id?(character["character_id"]) ->
          character["character_id"]

        # Try to get from the top level with "eve_id" key
        is_binary(character["eve_id"]) && is_valid_numeric_id?(character["eve_id"]) ->
          character["eve_id"]

        # Try to get from nested "character" object
        is_map(character["character"]) && is_binary(character["character"]["eve_id"]) &&
        is_valid_numeric_id?(character["character"]["eve_id"]) ->
          character["character"]["eve_id"]

        # Try to get from nested "character" object with "character_id" key
        is_map(character["character"]) && is_binary(character["character"]["character_id"]) &&
        is_valid_numeric_id?(character["character"]["character_id"]) ->
          character["character"]["character_id"]

        # Try to get from nested "character" object with "id" key
        is_map(character["character"]) && is_binary(character["character"]["id"]) &&
        is_valid_numeric_id?(character["character"]["id"]) ->
          character["character"]["id"]

        # No valid numeric ID found
        true ->
          Logger.error("No valid numeric EVE ID found for character: #{inspect(character, pretty: true)}")
          nil
      end

      # Log the extracted EVE ID
      Logger.info("Extracted EVE ID: #{eve_id}")

      # If we don't have a valid EVE ID, log an error and return
      if is_nil(eve_id) do
        Logger.error("No valid EVE character ID found for character: #{inspect(character, pretty: true)}")
        Logger.error("This is a critical error - character tracking requires numeric EVE IDs")
        return_value = {:error, :invalid_character_id}
        return_value
      else
        # Use the EVE character ID for the portrait URL
        portrait_url = "https://images.evetech.net/characters/#{eve_id}/portrait"
        Logger.info("Using EVE portrait URL: #{portrait_url}")

        # Extract character name - handle different possible data structures
        name = cond do
          # Try to get from the top level first
          character["character_name"] != nil ->
            character["character_name"]

          # Try to get from the top level with "name" key
          character["name"] != nil ->
            character["name"]

          # Try to get from nested "character" object
          is_map(character["character"]) && character["character"]["name"] != nil ->
            character["character"]["name"]

          # Try to get from nested "character" object with "character_name" key
          is_map(character["character"]) && character["character"]["character_name"] != nil ->
            character["character"]["character_name"]

          # Fallback
          true ->
            "Unknown Character"
        end

        # Log the extracted character name
        Logger.info("Extracted character name: #{name}")

        # Extract corporation name - handle different possible data structures
        corporation_name = cond do
          # Try to get from the top level first
          character["corporation_name"] != nil ->
            character["corporation_name"]

          # Try to get from nested "character" object
          is_map(character["character"]) && character["character"]["corporation_name"] != nil ->
            character["character"]["corporation_name"]

          # Fallback
          true ->
            "Unknown Corporation"
        end

        # Log the extracted corporation name
        Logger.info("Extracted corporation name: #{corporation_name}")

        # Plain text version (used for invalid license)
        plain_text = "#{name} (#{corporation_name}) is now being tracked"

        # Rich embed version (used for valid license)
        url = "https://zkillboard.com/character/#{eve_id}/"

        description = "is now being tracked"

        embed_data = %{
          title: name,
          description: description,
          url: url,
          color: @default_embed_color,
          thumbnail_url: portrait_url,
          fields: [
            %{
              name: "Corporation",
              value: corporation_name,
              inline: true
            }
          ]
        }

        # Send notification with license check
        send_notification_with_license_check(plain_text, embed_data)
      end
    end
  end

  @doc """
  Sends a notification for a new system found.
  Expects a map with keys: "system_id" and optionally "system_name".
  If "system_name" is missing, falls back to a lookup.
  """
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

      # Log the system data for debugging
      Logger.info("SYSTEM NOTIFICATION DATA: #{inspect(system, pretty: true, limit: 10000)}")
      Logger.info("System keys: #{inspect(Map.keys(system))}")

      system_id =
        Map.get(system, "system_id") ||
          Map.get(system, :system_id) ||
          Map.get(system, "solar_system_id")

      # Format the system name according to the requirements
      system_name = format_system_name(system)

      # Determine system type and get the appropriate icon
      system_type = determine_system_type(system)
      icon_url = get_system_icon_url(system_type)

      # Log the system type and icon URL
      Logger.info("System type: #{system_type}, Icon URL: #{icon_url}")

      # Get recent kills in this system
      recent_kills = get_recent_kills_in_system(system_id)

      # Plain text version (used for invalid license)
      plain_text = "#{system_name} (#{system_type}) has been added to the map."

      # Rich embed version (used for valid license)
      url = "https://zkillboard.com/system/#{system_id}/"
      description = "has been added to the map."

      embed_data = %{
        title: system_name,
        description: description,
        url: url,
        color: @default_embed_color,
        thumbnail_url: icon_url,
        fields: [
          %{
            name: "System Type",
            value: system_type,
            inline: true
          }
        ]
      }

      # Add security status field if available
      security_status = Map.get(system, "security_status") || Map.get(system, "security")
      embed_data_with_security = if security_status do
        formatted_security = format_security_status(security_status)
        Map.update!(embed_data, :fields, fn fields ->
          fields ++ [%{
            name: "Security",
            value: formatted_security,
            inline: true
          }]
        end)
      else
        embed_data
      end

      # Add recent kills field if available
      embed_data_with_kills = if recent_kills != [] do
        Map.update!(embed_data_with_security, :fields, fn fields ->
          fields ++ [%{
            name: "Recent Activity",
            value: format_recent_kills(recent_kills),
            inline: false
          }]
        end)
      else
        embed_data_with_security
      end

      # Send notification with license check
      send_notification_with_license_check(plain_text, embed_data_with_kills)
    end
  end

  # Helper to format system name from various data structures
  defp format_system_name(system) do
    # Get original_name and temporary_name from the system data
    original_name = Map.get(system, "original_name")
    temporary_name = Map.get(system, "temporary_name")
    system_name_from_map = Map.get(system, "system_name") || Map.get(system, :alias) || Map.get(system, "name")
    system_id = Map.get(system, "system_id") || Map.get(system, :system_id) || Map.get(system, "solar_system_id")

    # Format the system name according to the requirements
    cond do
      # If we have both original_name and temporary_name, and they're different
      original_name && temporary_name && temporary_name != "" && original_name != temporary_name ->
        "#{original_name} (#{temporary_name})"

      # If we have original_name
      original_name && original_name != "" ->
        original_name

      # If we have system_name from map and original_name, and they're different
      system_name_from_map && original_name && system_name_from_map != original_name ->
        "#{system_name_from_map} (#{original_name})"

      # If we have system_name from map
      system_name_from_map && system_name_from_map != "" ->
        system_name_from_map

      # Fallback to system ID
      true ->
        "Solar System #{system_id}"
    end
  end

  # Get corporation name from ID with caching
  defp get_corporation_name_from_id(corporation_id) do
    if not is_valid_numeric_id?(corporation_id) do
      "Unknown Corporation"
    else
      # Try to get from cache first
      cache_key = "corporation_name:#{corporation_id}"

      case CacheRepo.get(cache_key) do
        name when is_binary(name) and name != "" ->
          Logger.debug("Found corporation name in cache: #{name}")
          name

        _ ->
          # If not in cache, fetch from ESI and cache the result
          Logger.debug("Fetching corporation name from ESI for ID: #{corporation_id}")
          case WandererNotifier.ESI.Service.get_corporation_info(corporation_id) do
            {:ok, %{"name" => corp_name}} ->
              Logger.debug("Found corporation name: #{corp_name}")
              # Cache the result for future use (24 hours TTL)
              CacheRepo.set(cache_key, corp_name, :timer.hours(24) |> div(1000))
              corp_name

            _error ->
              Logger.debug("Failed to get corporation name for ID: #{corporation_id}")
              "Unknown Corporation"
          end
      end
    end
  end

  # Shared helper for sending notifications with license check
  defp send_notification_with_license_check(plain_text, embed_data) do
    # Check if license is valid
    license_valid = WandererNotifier.License.status().valid

    if license_valid do
      # Send rich embed for valid license
      embed = build_embed_from_data(embed_data)
      # Use empty content with the embed to avoid sending both plain text and rich embed
      payload = %{"content" => "", "embeds" => [embed]}
      send_payload(payload)
    else
      # Send plain text for invalid license
      send_message(plain_text)
    end
  end

  # Build a complete embed from embed data
  defp build_embed_from_data(data) do
    # Start with the basic embed
    embed = %{
      "title" => data.title,
      "description" => data.description,
      "color" => data.color,
      "timestamp" => DateTime.utc_now() |> DateTime.to_iso8601()
    }

    # Add optional fields if they exist
    embed = if data.url, do: Map.put(embed, "url", data.url), else: embed

    # Add footer if footer_text exists
    embed = if Map.get(data, :footer_text),
      do: Map.put(embed, "footer", %{"text" => data.footer_text}),
      else: embed

    # Add thumbnail if thumbnail_url exists
    embed = if Map.get(data, :thumbnail_url),
      do: Map.put(embed, "thumbnail", %{"url" => data.thumbnail_url}),
      else: embed

    # Add author if author_name exists
    if Map.get(data, :author_name) do
      author = %{"name" => data.author_name}
      author = if data.url, do: Map.put(author, "url", data.url), else: author
      author = if Map.get(data, :author_icon_url),
        do: Map.put(author, "icon_url", data.author_icon_url),
        else: author

      Map.put(embed, "author", author)
    else
      embed
    end
  end

  defp send_payload(payload) do
    url = build_url()
    json_payload = Jason.encode!(payload)

    case HttpClient.request("POST", url, headers(), json_payload) do
      {:ok, %HTTPoison.Response{status_code: status}} when status in 200..299 ->
        :ok

      {:ok, %HTTPoison.Response{status_code: status, body: body}} ->
        Logger.error("Discord API request failed with status #{status}")
        Logger.error("Discord API error response: Elided for security. Enable debug logs for details.")
        {:error, body}

      {:error, err} ->
        Logger.error("Discord API request error: #{inspect(err)}")
        {:error, err}
    end
  end

  # Recursively normalize keys in a map to strings.
  defp normalize_keys(%WandererNotifier.Killmail{} = killmail) do
    # Convert the Killmail struct to a map and then normalize it
    killmail_map = %{
      "killmail_id" => killmail.killmail_id,
      "zkb" => normalize_keys(killmail.zkb),
      "esi_data" => normalize_keys(killmail.esi_data)
    }

    # Merge ESI data into the top level for easier access
    Map.merge(killmail_map, normalize_keys(killmail.esi_data || %{}))
  end

  defp normalize_keys(value) when is_map(value) do
    for {k, v} <- value, into: %{} do
      key = if is_atom(k), do: Atom.to_string(k), else: k
      {key, normalize_keys(v)}
    end
  end

  defp normalize_keys(value) when is_list(value), do: Enum.map(value, &normalize_keys/1)
  defp normalize_keys(value), do: value

  defp build_description(normalized) do
    victim = Map.get(normalized, "victim", %{})
    attackers = Map.get(normalized, "attackers", [])

    final_attacker = get_final_attacker(attackers)
    top_attacker = get_top_attacker(attackers)

    victim_data = extract_entity(victim)
    final_data = extract_entity(final_attacker)

    base_desc =
      "**[#{victim_data.name}](#{victim_data.zkill_url}) (#{victim_data.corp})** lost their **#{victim_data.ship}** " <>
      "to **[#{final_data.name}](#{final_data.zkill_url}) (#{final_data.corp})** flying a **#{final_data.ship}**"

    if length(attackers) > 1 and top_attacker != %{} do
      top_data = extract_entity(top_attacker)

      base_desc <>
        ", Top Damage was done by **[#{top_data.name}](#{top_data.zkill_url}) (#{top_data.corp})** " <>
        "flying a **#{top_data.ship}**."
    else
      base_desc <> " solo."
    end
  end

  defp get_final_attacker(attackers) when is_list(attackers) do
    valid =
      attackers
      |> Enum.filter(fn a -> Map.has_key?(a, "character_id") end)

    Enum.find(valid, fn a -> Map.get(a, "final_blow", false) end) ||
      if valid != [], do: Enum.max_by(valid, fn a -> Map.get(a, "damage_done", 0) end), else: %{}
  end

  defp get_top_attacker(attackers) when is_list(attackers) do
    valid =
      attackers
      |> Enum.filter(fn a -> Map.has_key?(a, "character_id") end)

    if valid != [] do
      Enum.max_by(valid, fn a -> Map.get(a, "damage_done", 0) end)
    else
      %{}
    end
  end

  defp extract_entity(entity) when is_map(entity) do
    character_id = Map.get(entity, "character_id")

    name =
      case Map.get(entity, "character_name") do
        nil ->
          if is_valid_id?(character_id) do
            get_character_name_from_id(character_id)
          else
            "Unknown Character"
          end

        name ->
          name
      end

    corporation_id = Map.get(entity, "corporation_id")
    corp = get_corporation_name_from_id(corporation_id)

    ship_type_id = Map.get(entity, "ship_type_id")

    ship =
      case Map.get(entity, "ship_name") do
        nil ->
          if is_valid_id?(ship_type_id) do
            get_ship_type_name_from_id(ship_type_id)
          else
            "Unknown Ship"
          end

        ship_name ->
          ship_name
      end

    zkill_url =
      Map.get(entity, "zkill_url") ||
        if is_valid_id?(character_id) do
          "https://zkillboard.com/character/#{character_id}/"
        else
          nil
        end

    %{id: character_id || "unknown", name: name, corp: corp, ship: ship, zkill_url: zkill_url}
  end

  # Get character name from ID with caching
  defp get_character_name_from_id(character_id) do
    if not is_valid_id?(character_id) do
      "Unknown Character"
    else
      # Try to get from cache first
      cache_key = "character_name:#{character_id}"

      case CacheRepo.get(cache_key) do
        name when is_binary(name) and name != "" ->
          Logger.debug("Found character name in cache: #{name}")
          name

        _ ->
          # If not in cache, fetch from ESI and cache the result
          Logger.debug("Fetching character name from ESI for ID: #{character_id}")
          case WandererNotifier.ESI.Service.get_character_info(character_id) do
            {:ok, %{"name" => character_name}} ->
              Logger.debug("Found character name: #{character_name}")
              # Cache the result for future use (24 hours TTL)
              CacheRepo.set(cache_key, character_name, :timer.hours(24) |> div(1000))
              character_name

            _ ->
              fallback = "Character #{character_id}"
              Logger.debug("Failed to get character name, using fallback: #{fallback}")
              fallback
          end
      end
    end
  end

  # Get ship type name from ID with caching
  defp get_ship_type_name_from_id(ship_type_id) do
    if not is_valid_id?(ship_type_id) do
      "Unknown Ship"
    else
      # Try to get from cache first
      cache_key = "ship_type_name:#{ship_type_id}"

      case CacheRepo.get(cache_key) do
        name when is_binary(name) and name != "" ->
          Logger.debug("Found ship type name in cache: #{name}")
          name

        _ ->
          # If not in cache, fetch from ESI and cache the result
          Logger.debug("Fetching ship type name from ESI for ID: #{ship_type_id}")
          case WandererNotifier.ESI.Service.get_ship_type_name(ship_type_id) do
            {:ok, %{"name" => ship_name}} ->
              Logger.debug("Found ship type name: #{ship_name}")
              # Cache the result for future use (7 days TTL - ship types change less frequently)
              CacheRepo.set(cache_key, ship_name, :timer.hours(24 * 7) |> div(1000))
              ship_name

            _ ->
              fallback = "Ship #{ship_type_id}"
              Logger.debug("Failed to get ship type name, using fallback: #{fallback}")
              fallback
          end
      end
    end
  end

  # Helper function to check if an ID is valid for API calls
  def is_valid_id?(nil), do: false
  def is_valid_id?("Unknown"), do: false
  def is_valid_id?("unknown"), do: false
  def is_valid_id?(id) when is_binary(id) do
    case Integer.parse(id) do
      {num, ""} when num > 0 -> true
      _ -> false
    end
  end
  def is_valid_id?(id) when is_integer(id) and id > 0, do: true
  def is_valid_id?(_), do: false

  # Helper function to check if an ID is a valid numeric ID for EVE API calls
  # This function only accepts numeric IDs, not UUIDs
  def is_valid_numeric_id?(nil), do: false
  def is_valid_numeric_id?(""), do: false
  def is_valid_numeric_id?("Unknown"), do: false
  def is_valid_numeric_id?("unknown"), do: false

  # Handle numeric string IDs
  def is_valid_numeric_id?(id) when is_binary(id) do
    case Integer.parse(id) do
      {num, ""} when num > 0 ->
        Logger.debug("ID #{id} parsed as valid numeric ID: #{num}")
        true
      _ ->
        Logger.debug("ID #{id} is not a valid numeric ID")
        false
    end
  end

  # Handle integer IDs
  def is_valid_numeric_id?(id) when is_integer(id) and id > 0, do: true
  def is_valid_numeric_id?(_), do: false

  defp resolve_system_name(nil), do: "Unknown System"

  defp resolve_system_name(solar_system_id) do
    if not is_valid_id?(solar_system_id) do
      "Unknown System"
    else
      tracked = get_tracked_systems()

      case Enum.find(tracked, fn sys ->
             to_string(Map.get(sys, "system_id") || Map.get(sys, :system_id)) ==
               to_string(solar_system_id)
           end) do
        nil ->
          get_solar_system_name_from_id(solar_system_id)

        system ->
          Map.get(system, "system_name") || Map.get(system, :alias) ||
            "Solar System #{solar_system_id}"
      end
    end
  end

  # Get solar system name from ID with caching
  defp get_solar_system_name_from_id(solar_system_id) do
    if not is_valid_id?(solar_system_id) do
      "Unknown System"
    else
      # Try to get from cache first
      cache_key = "solar_system_name:#{solar_system_id}"

      case CacheRepo.get(cache_key) do
        name when is_binary(name) and name != "" ->
          Logger.debug("Found solar system name in cache: #{name}")
          name

        _ ->
          # If not in cache, fetch from ESI and cache the result
          Logger.debug("Fetching solar system name from ESI for ID: #{solar_system_id}")
          case WandererNotifier.ESI.Service.get_solar_system_name(solar_system_id) do
            {:ok, %{"name" => name}} ->
              Logger.debug("Found solar system name: #{name}")
              # Cache the result for future use (7 days TTL - solar systems change very rarely)
              CacheRepo.set(cache_key, name, :timer.hours(24 * 7) |> div(1000))
              name

            _ ->
              fallback = "Solar System #{solar_system_id}"
              Logger.debug("Failed to get solar system name, using fallback: #{fallback}")
              fallback
          end
      end
    end
  end

  defp get_tracked_systems do
    WandererNotifier.Helpers.CacheHelpers.get_tracked_systems()
  end

  defp get_total_value(normalized) do
    case Map.get(normalized, "total_value") do
      nil ->
        get_in(normalized, ["zkb", "totalValue"]) || 0.0
      value ->
        value
    end
  end

  def format_isk_value(amount) when is_number(amount) do
    cond do
      amount < 1_000_000 ->
        "<1 M ISK"

      amount < 1_000_000_000 ->
        millions = amount / 1_000_000
        :io_lib.format("~.2fm ISK", [millions]) |> List.to_string()

      amount < 1_000_000_000_000 ->
        billions = amount / 1_000_000_000
        :io_lib.format("~.2fb ISK", [billions]) |> List.to_string()

      true ->
        trillions = amount / 1_000_000_000_000
        :io_lib.format("~.2ft ISK", [trillions]) |> List.to_string()
    end
  end

  def format_isk_value(_), do: "N/A"

  @doc """
  Closes the notifier (if any cleanup is needed).
  """
  def close do
    :ok
  end

  # Helper function to check if a kill is properly enriched
  defp is_kill_properly_enriched?(kill) do
    # Check for key fields that would indicate proper enrichment
    has_zkb = Map.has_key?(kill, "zkb") && is_map(Map.get(kill, "zkb"))
    has_value = has_zkb && Map.has_key?(Map.get(kill, "zkb"), "totalValue")
    has_victim_details = Map.has_key?(kill, "victim") &&
                         is_map(Map.get(kill, "victim")) &&
                         Map.has_key?(Map.get(kill, "victim"), "character_name")

    # Consider it properly enriched if it has zkb data with value and victim details
    has_zkb && has_value && has_victim_details
  end

  # Helper to determine system type from system data
  defp determine_system_type(system) do
    # Extract relevant data
    class = Map.get(system, "class") || Map.get(system, "wormhole_class")
    security_status = Map.get(system, "security_status") || Map.get(system, "security")
    system_type = Map.get(system, "type") || Map.get(system, "system_type")

    cond do
      # Check for explicit system type first
      is_binary(system_type) && system_type != "" ->
        case String.downcase(system_type) do
          "wormhole" -> determine_wormhole_class(class)
          "triglavian" -> "Triglavian"
          "drifter" -> "Drifter"
          type -> String.capitalize(type)
        end

      # Check for wormhole class
      is_binary(class) || is_integer(class) ->
        determine_wormhole_class(class)

      # Check security status for k-space
      is_number(security_status) || is_binary(security_status) ->
        determine_kspace_type(security_status)

      # Default fallback
      true ->
        "Unknown"
    end
  end

  # Helper to determine wormhole class
  defp determine_wormhole_class(class) when is_binary(class) do
    # Try to parse the class as an integer
    case Integer.parse(class) do
      {num, ""} -> determine_wormhole_class(num)
      _ ->
        # Handle special wormhole types
        case String.downcase(class) do
          "thera" -> "Thera"
          "drifter" -> "Drifter"
          "shattered" -> "Shattered"
          _ -> "Class #{class}"
        end
    end
  end

  defp determine_wormhole_class(class) when is_integer(class) do
    case class do
      1 -> "Class 1"
      2 -> "Class 2"
      3 -> "Class 3"
      4 -> "Class 4"
      5 -> "Class 5"
      6 -> "Class 6"
      13 -> "Shattered"
      _ -> "Class #{class}"
    end
  end

  defp determine_wormhole_class(_), do: "Unknown Class"

  # Helper to determine k-space type based on security status
  defp determine_kspace_type(security_status) when is_binary(security_status) do
    case Float.parse(security_status) do
      {num, ""} -> determine_kspace_type(num)
      _ -> "Unknown"
    end
  end

  defp determine_kspace_type(security_status) when is_number(security_status) do
    cond do
      security_status >= 0.45 -> "High Security"
      security_status > 0.0 -> "Low Security"
      true -> "Null Security"
    end
  end

  defp determine_kspace_type(_), do: "Unknown"

  # Helper to get system icon URL based on system type
  defp get_system_icon_url(system_type) do
    # Use EVE Online official images that are publicly accessible
    case system_type do
      # K-Space (Known Space) systems
      "High Security" -> "https://images.evetech.net/types/3802/icon"  # Amarr Control Tower - gold color for highsec
      "Low Security" -> "https://images.evetech.net/types/16213/icon"  # Caldari Control Tower - blue color for lowsec
      "Null Security" -> "https://images.evetech.net/types/16214/icon"  # Gallente Control Tower - green color for nullsec

      # Special space types
      "Triglavian" -> "https://images.evetech.net/types/47740/icon"  # Triglavian ship
      "Drifter" -> "https://images.evetech.net/types/34495/icon"  # Drifter structure

      # Wormhole classes with more specific icons
      "Class 1" -> "https://images.evetech.net/types/30370/icon"  # Wormhole C1
      "Class 2" -> "https://images.evetech.net/types/30370/icon"  # Wormhole C2
      "Class 3" -> "https://images.evetech.net/types/30371/icon"  # Wormhole C3
      "Class 4" -> "https://images.evetech.net/types/30371/icon"  # Wormhole C4
      "Class 5" -> "https://images.evetech.net/types/30372/icon"  # Wormhole C5
      "Class 6" -> "https://images.evetech.net/types/30372/icon"  # Wormhole C6
      "Shattered" -> "https://images.evetech.net/types/30372/icon"  # Shattered wormhole

      # Default/unknown
      _ -> "https://images.evetech.net/types/30371/icon"  # Generic wormhole icon
    end
  end

  # Helper to format security status for display
  defp format_security_status(security_status) when is_binary(security_status) do
    case Float.parse(security_status) do
      {num, ""} -> format_security_status(num)
      _ -> security_status
    end
  end

  defp format_security_status(security_status) when is_number(security_status) do
    # Format to one decimal place with proper coloring
    formatted = :io_lib.format("~.1f", [security_status]) |> to_string()

    cond do
      security_status >= 0.45 -> "#{formatted} (High)"
      security_status > 0.0 -> "#{formatted} (Low)"
      true -> "#{formatted} (Null)"
    end
  end

  defp format_security_status(security_status), do: "#{security_status}"

  # Helper to get recent kills in a specific system
  defp get_recent_kills_in_system(system_id) do
    # Get recent kills from the KillProcessor
    recent_kills = WandererNotifier.Service.KillProcessor.get_recent_kills()

    # For test notifications, if there are no recent kills, add mock kills
    if recent_kills == [] && String.contains?(inspect(Process.info(self())), "test-system-notification") do
      Logger.info("Adding mock kill data for test notification")

      # Create multiple mock kills with realistic data
      [
        %{
          "killmail_id" => "123456789",
          "solar_system_id" => system_id,
          "timestamp" => DateTime.utc_now() |> DateTime.add(-15 * 60, :second) |> DateTime.to_iso8601(),
          "victim" => %{
            "character_id" => "95465499",
            "character_name" => "Test Victim",
            "ship_type_id" => "17740",
            "ship_type_name" => "Vindicator"
          }
        },
        %{
          "killmail_id" => "123456790",
          "solar_system_id" => system_id,
          "timestamp" => DateTime.utc_now() |> DateTime.add(-45 * 60, :second) |> DateTime.to_iso8601(),
          "victim" => %{
            "character_id" => "95465500",
            "character_name" => "Another Victim",
            "ship_type_id" => "28352",
            "ship_type_name" => "Rorqual"
          }
        },
        %{
          "killmail_id" => "123456791",
          "solar_system_id" => system_id,
          "timestamp" => DateTime.utc_now() |> DateTime.add(-120 * 60, :second) |> DateTime.to_iso8601(),
          "victim" => %{
            "character_id" => "95465501",
            "character_name" => "Third Victim",
            "ship_type_id" => "28659",
            "ship_type_name" => "Nyx"
          }
        },
        %{
          "killmail_id" => "123456792",
          "solar_system_id" => system_id,
          "timestamp" => DateTime.utc_now() |> DateTime.add(-180 * 60, :second) |> DateTime.to_iso8601(),
          "victim" => %{
            "character_id" => "95465502",
            "character_name" => "Fourth Victim",
            "ship_type_id" => "670",
            "ship_type_name" => "Capsule"
          }
        }
      ]
    else
      # Filter to only include kills in the specified system
      system_id_str = to_string(system_id)
      Enum.filter(recent_kills, fn kill ->
        kill_system_id = to_string(Map.get(kill, "solar_system_id", ""))
        kill_system_id == system_id_str
      end)
    end
  end

  # Helper to format recent kills for display in Discord embed
  defp format_recent_kills(kills) do
    case kills do
      [] ->
        "No recent activity"

      [kill | _] when length(kills) == 1 ->
        victim_name = get_in(kill, ["victim", "character_name"]) || "Unknown"
        ship_type = get_in(kill, ["victim", "ship_type_name"]) || "Unknown Ship"
        kill_id = Map.get(kill, "killmail_id")
        kill_time = Map.get(kill, "timestamp")
        formatted_time = if kill_time, do: format_timestamp(kill_time), else: "recently"

        if kill_id do
          "**Recent kill:** [#{victim_name}](https://zkillboard.com/kill/#{kill_id}/) lost a **#{ship_type}** #{formatted_time}"
        else
          "**Recent kill:** #{victim_name} lost a **#{ship_type}** #{formatted_time}"
        end

      _ ->
        # Format multiple kills with emojis and better formatting
        kill_list = Enum.map_join(Enum.take(kills, 3), "\n", fn kill ->
          victim_name = get_in(kill, ["victim", "character_name"]) || "Unknown"
          ship_type = get_in(kill, ["victim", "ship_type_name"]) || "Unknown Ship"
          kill_id = Map.get(kill, "killmail_id")
          kill_time = Map.get(kill, "timestamp")
          formatted_time = if kill_time, do: format_timestamp(kill_time), else: "recently"

          ship_emoji = get_ship_emoji(ship_type)

          if kill_id do
            "#{ship_emoji} [#{victim_name}](https://zkillboard.com/kill/#{kill_id}/) (**#{ship_type}**) #{formatted_time}"
          else
            "#{ship_emoji} #{victim_name} (**#{ship_type}**) #{formatted_time}"
          end
        end)

        total = length(kills)
        remaining = total - 3

        header = "**Recent Activity (#{total} kills)**\n"

        if remaining > 0 do
          "#{header}#{kill_list}\n...and #{remaining} more"
        else
          "#{header}#{kill_list}"
        end
    end
  end

  # Helper to get an appropriate emoji for a ship type
  defp get_ship_emoji(ship_type) do
    cond do
      # Capital ships
      String.contains?(ship_type, "Titan") -> "💥"
      String.contains?(ship_type, "Supercarrier") || ship_type == "Nyx" || ship_type == "Aeon" || ship_type == "Hel" || ship_type == "Wyvern" -> "💥"
      String.contains?(ship_type, "Carrier") || ship_type == "Thanatos" || ship_type == "Archon" || ship_type == "Chimera" || ship_type == "Nidhoggur" -> "🚀"
      String.contains?(ship_type, "Dreadnought") || ship_type == "Moros" || ship_type == "Revelation" || ship_type == "Phoenix" || ship_type == "Naglfar" -> "🚀"
      String.contains?(ship_type, "Rorqual") -> "⛏️"

      # Expensive ships
      String.contains?(ship_type, "Marauder") || ship_type == "Golem" || ship_type == "Kronos" || ship_type == "Paladin" || ship_type == "Vargur" -> "💰"
      String.contains?(ship_type, "Vindicator") || String.contains?(ship_type, "Machariel") || String.contains?(ship_type, "Nightmare") -> "💰"

      # Pods
      String.contains?(ship_type, "Capsule") || String.contains?(ship_type, "Pod") -> "🥚"

      # Default
      true -> "🚢"
    end
  end

  # Helper to format timestamp for display
  defp format_timestamp(timestamp) do
    case DateTime.from_iso8601(timestamp) do
      {:ok, datetime, _} ->
        # Calculate time difference in minutes
        now = DateTime.utc_now()
        diff_seconds = DateTime.diff(now, datetime)

        cond do
          diff_seconds < 60 -> "just now"
          diff_seconds < 3600 -> "#{div(diff_seconds, 60)} minutes ago"
          diff_seconds < 86400 -> "#{div(diff_seconds, 3600)} hours ago"
          true -> "#{div(diff_seconds, 86400)} days ago"
        end
      _ ->
        "recently"
    end
  end
end
