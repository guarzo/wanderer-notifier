defmodule WandererNotifier.Discord.Notifier do
  @moduledoc """
  Sends notifications to Discord as channel messages using a bot token.
  Supports plain text messages and rich embed messages.
  """
  require Logger
  alias WandererNotifier.Http.Client, as: HttpClient
  alias WandererNotifier.Helpers.CacheHelpers
  alias WandererNotifier.Cache.Repository, as: CacheRepo

  # Use a runtime environment check instead of compile-time
  defp env do
    Application.get_env(:wanderer_notifier, :env, :prod)
  end

  @base_url "https://discord.com/api/channels"
  @verbose_logging false  # Set to true to enable verbose logging
  @default_embed_color 0x00FF00

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
      
      # Send notification with license check
      send_notification_with_license_check(plain_text, embed_data)
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

      character_id = Map.get(character, "character_id") || Map.get(character, "eve_id")

      # Extract the EVE character ID from the nested character object if available
      eve_character_id = extract_eve_character_id(character, character_id)

      # Use the EVE character ID for the portrait URL and zkill link
      portrait_url = "https://images.evetech.net/characters/#{eve_character_id}/portrait"

      name =
        Map.get(character, "character_name") ||
        (character["character"] && Map.get(character["character"], "name")) ||
        "Unknown Character"

      # Extract corporation ID from the character data
      corporation_id =
        Map.get(character, "corporation_id") ||
        (character["character"] && Map.get(character["character"], "corporation_id"))

      Logger.debug("CHARACTER NOTIFICATION: Corporation ID from data: #{inspect(corporation_id)}")

      # Extract or fetch corporation name
      corp = get_corporation_name(corporation_id, character)

      # Plain text version (used for invalid license)
      plain_text = "New tracked character: #{name}"
      
      # Rich embed version (used for valid license)
      url = "https://zkillboard.com/character/#{eve_character_id}/"
      description = "[#{name}](#{url}) (#{corp}) is now being tracked"
      
      embed_data = %{
        title: "New Character",
        description: description,
        url: url,
        color: @default_embed_color,
        thumbnail_url: portrait_url
      }
      
      # Send notification with license check
      send_notification_with_license_check(plain_text, embed_data)
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

      system_id =
        Map.get(system, "system_id") ||
          Map.get(system, :system_id) ||
          Map.get(system, "solar_system_id")

      # Format the system name according to the requirements
      system_name = format_system_name(system)

      # Plain text version (used for invalid license)
      plain_text = "New system mapped: #{system_name}"
      
      # Rich embed version (used for valid license)
      url = "https://zkillboard.com/system/#{system_id}/"
      description = "[#{system_name}](#{url}) has been added to the map."
      
      embed_data = %{
        title: "New System Mapped",
        description: description,
        url: url,
        color: @default_embed_color
      }
      
      # Send notification with license check
      send_notification_with_license_check(plain_text, embed_data)
    end
  end

  # Helper to extract EVE character ID from various character data structures
  defp extract_eve_character_id(character, fallback_id) do
    case character do
      %{"character" => %{"eve_id" => eve_id}} when is_binary(eve_id) ->
        eve_id
      %{"eve_id" => eve_id} when is_binary(eve_id) ->
        eve_id
      _ ->
        fallback_id
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

  # Helper to get corporation name with caching
  defp get_corporation_name(corporation_id, character) do
    # First try to get from the character data
    from_data = 
      Map.get(character, "corporation_name") ||
      (character["character"] && Map.get(character["character"], "corporation_name"))
    
    if from_data do
      from_data
    else
      # If not in data, try to get from cache or ESI
      get_corporation_name_from_id(corporation_id)
    end
  end

  # Get corporation name from ID with caching
  defp get_corporation_name_from_id(corporation_id) do
    if not is_valid_id?(corporation_id) do
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
      payload = %{"embeds" => [embed]}
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
  defp is_valid_id?(nil), do: false
  defp is_valid_id?("Unknown"), do: false
  defp is_valid_id?("unknown"), do: false
  defp is_valid_id?(id) when is_binary(id) do
    case Integer.parse(id) do
      {num, ""} when num > 0 -> true
      _ -> false
    end
  end
  defp is_valid_id?(id) when is_integer(id) and id > 0, do: true
  defp is_valid_id?(_), do: false

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
    CacheHelpers.get_tracked_systems()
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
end
