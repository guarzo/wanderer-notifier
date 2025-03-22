defmodule WandererNotifier.Helpers.NotificationHelpers do
  @moduledoc """
  Helper functions for notification formatting and data extraction.
  """
  require Logger

  @doc """
  Extracts a valid EVE character ID from a character map.
  Handles various possible key structures.

  Returns the ID as a string or nil if no valid ID is found.
  """
  @spec extract_character_id(map()) :: String.t() | nil
  def extract_character_id(character) when is_map(character) do
    # Try extracting from different possible locations in order of preference
    character_id =
      check_top_level_id(character) ||
        check_nested_character_id(character)

    # Log error if no valid ID was found
    if is_nil(character_id) do
      Logger.error(
        "No valid numeric EVE ID found for character: #{inspect(character, pretty: true, limit: 500)}"
      )
    end

    character_id
  end

  # Check for valid ID at the top level of the character map
  defp check_top_level_id(character) do
    # Check character_id first, then eve_id
    check_valid_id(character, "character_id") ||
      check_valid_id(character, "eve_id")
  end

  # Check for valid ID in nested character object
  defp check_nested_character_id(character) do
    # Return nil if there's no nested character object
    nested = character["character"]

    if is_map(nested) do
      # Check each possible key in the nested object
      check_valid_id(nested, "eve_id") ||
        check_valid_id(nested, "character_id") ||
        check_valid_id(nested, "id")
    else
      nil
    end
  end

  # Helper to check if a specific key contains a valid numeric ID
  defp check_valid_id(map, key) do
    value = map[key]

    if is_binary(value) && valid_numeric_id?(value) do
      value
    else
      nil
    end
  end

  @doc """
  Extracts a character name from a character map.
  Handles various possible key structures.

  Returns the name as a string or a default value if no name is found.
  """
  @spec extract_character_name(map(), String.t()) :: String.t()
  def extract_character_name(character, default \\ "Unknown Character") when is_map(character) do
    # Try extracting name from different locations in order of preference
    name = check_top_level_name(character) || check_nested_character_name(character)

    if name do
      name
    else
      # Fall back to using character ID if available
      character_id = extract_character_id(character)
      if character_id, do: "Character #{character_id}", else: default
    end
  end

  # Check for name at the top level of the character map
  defp check_top_level_name(character) do
    character["character_name"] || character["name"]
  end

  # Check for name in nested character object
  defp check_nested_character_name(character) do
    nested = character["character"]

    if is_map(nested) do
      nested["name"] || nested["character_name"]
    else
      nil
    end
  end

  @doc """
  Extracts a corporation name from a character map.
  Handles various possible key structures.

  Returns the name as a string or a default value if no name is found.
  """
  @spec extract_corporation_name(map(), String.t()) :: String.t()
  def extract_corporation_name(character, default \\ "Unknown Corporation")
      when is_map(character) do
    cond do
      character["corporation_name"] != nil ->
        character["corporation_name"]

      is_map(character["character"]) && character["character"]["corporation_name"] != nil ->
        character["character"]["corporation_name"]

      true ->
        default
    end
  end

  @doc """
  Adds a field to an embed map if the value is available.

  ## Parameters
  - embed: The embed map to update
  - name: The name of the field
  - value: The value of the field (or nil)
  - inline: Whether the field should be displayed inline

  ## Returns
  The updated embed map with the field added if value is not nil
  """
  @spec add_field_if_available(map(), String.t(), any(), boolean()) :: map()
  def add_field_if_available(embed, name, value, inline \\ true)
  def add_field_if_available(embed, _name, nil, _inline), do: embed
  def add_field_if_available(embed, _name, "", _inline), do: embed

  def add_field_if_available(embed, name, value, inline) do
    # Ensure the fields key exists
    embed = Map.put_new(embed, :fields, [])

    # Add the new field
    Map.update!(embed, :fields, fn fields ->
      fields ++ [%{name: name, value: to_string(value), inline: inline}]
    end)
  end

  @doc """
  Adds a security status field to an embed if the security status is available.

  ## Parameters
  - embed: The embed map to update
  - security_status: The security status value (or nil)

  ## Returns
  The updated embed map with the security status field added if available
  """
  @spec add_security_field(map(), float() | nil) :: map()
  def add_security_field(embed, nil), do: embed

  def add_security_field(embed, security_status) when is_number(security_status) do
    # Format the security status
    formatted_security = format_security_status(security_status)

    # Add the field
    add_field_if_available(embed, "Security", formatted_security)
  end

  @doc """
  Formats a security status value with color coding.

  ## Parameters
  - security_status: The security status value

  ## Returns
  A formatted string with the security status
  """
  @spec format_security_status(float() | String.t()) :: String.t()
  def format_security_status(security_status) when is_number(security_status) do
    # Round to 1 decimal place
    rounded = Float.round(security_status, 1)

    # Format with color based on value
    cond do
      rounded >= 0.5 -> "#{rounded} (High)"
      rounded > 0.0 -> "#{rounded} (Low)"
      true -> "#{rounded} (Null)"
    end
  end

  def format_security_status(security_status) when is_binary(security_status) do
    # Convert string to float and then format
    case Float.parse(security_status) do
      {value, _} -> format_security_status(value)
      :error -> "Unknown"
    end
  end

  @doc """
  Checks if a string is a valid numeric ID.

  ## Parameters
  - id: The string to check

  ## Returns
  true if the string is a valid numeric ID, false otherwise
  """
  @spec valid_numeric_id?(String.t() | any()) :: boolean()
  def valid_numeric_id?(id) when is_binary(id) do
    case Integer.parse(id) do
      {num, ""} when num > 0 -> true
      _ -> false
    end
  end

  def valid_numeric_id?(_), do: false

  @doc """
  Sends a test system notification using a real system from the cache.

  This function retrieves a random wormhole system from the tracked systems and
  sends a system notification for it. It uses the normal notification pathway to ensure
  accurate test behavior.

  ## Returns
  - `{:ok, system_id, system_name}` - The ID and name of the system that was used for the test notification
  """
  @spec send_test_system_notification() :: {:ok, String.t() | integer(), String.t()}
  def send_test_system_notification() do
    require Logger
    Logger.info("TEST NOTIFICATION: Manually triggering a test system notification")

    alias WandererNotifier.Notifiers.Factory, as: NotifierFactory
    alias WandererNotifier.Data.MapSystem

    # Get all tracked systems from cache
    tracked_systems = get_tracked_systems()
    Logger.info("Found #{length(tracked_systems)} tracked systems")

    # Select a random wormhole system if available, or any system if no wormholes
    selected_system =
      tracked_systems
      |> Enum.filter(&wormhole_system?/1)
      |> case do
        [] ->
          # No wormhole systems, just pick any system
          Logger.info("No wormhole systems found, selecting random system")
          Enum.random(tracked_systems)

        wormhole_systems ->
          # Pick a random wormhole system
          Logger.info("Found #{length(wormhole_systems)} wormhole systems")
          Enum.random(wormhole_systems)
      end

    # Convert to MapSystem struct if not already
    map_system =
      if is_struct(selected_system, MapSystem) do
        selected_system
      else
        Logger.info("Converting to MapSystem struct for consistent handling")
        MapSystem.new(selected_system)
      end

    Logger.info(
      "Using system #{map_system.name} (ID: #{map_system.solar_system_id}) for test notification"
    )

    # Enrich the MapSystem with static info
    enriched_system =
      case WandererNotifier.Api.Map.SystemStaticInfo.enrich_system(map_system) do
        {:ok, enriched} ->
          Logger.info("Successfully enriched system with static info")
          enriched

        {:error, reason} ->
          Logger.warning("Failed to enrich system: #{inspect(reason)}")
          # Return the original system if enrichment fails
          map_system
      end

    # Log key fields for debugging
    Logger.info("Enriched system fields:")
    Logger.info("- solar_system_id: #{enriched_system.solar_system_id}")
    Logger.info("- name: #{enriched_system.name}")
    Logger.info("- type_description: #{enriched_system.type_description}")
    Logger.info("- is_wormhole?: #{MapSystem.wormhole?(enriched_system)}")
    Logger.info("- statics: #{inspect(enriched_system.statics)}")

    # Send notification with the enriched system struct directly
    notifier = NotifierFactory.get_notifier()
    notifier.send_new_system_notification(enriched_system)

    {:ok, enriched_system.solar_system_id, enriched_system.name}
  end

  # Helper functions for test system notification

  # Get tracked systems from cache
  defp get_tracked_systems() do
    alias WandererNotifier.Data.Cache.Repository, as: CacheRepo

    # Try to get systems from the "map:systems" cache key
    get_systems_from_main_cache(CacheRepo) || get_systems_from_individual_caches(CacheRepo)
  end

  defp get_systems_from_main_cache(cache_repo) do
    case cache_repo.get("map:systems") do
      systems when is_list(systems) and length(systems) > 0 -> systems
      _ -> nil
    end
  end

  defp get_systems_from_individual_caches(cache_repo) do
    system_ids = get_valid_system_ids(cache_repo)

    if system_ids do
      fetch_individual_systems(cache_repo, system_ids)
    else
      # No systems found
      []
    end
  end

  defp get_valid_system_ids(cache_repo) do
    case cache_repo.get("map:system_ids") do
      ids when is_list(ids) and length(ids) > 0 -> ids
      _ -> nil
    end
  end

  defp fetch_individual_systems(cache_repo, ids) do
    ids
    |> Enum.map(fn id -> fetch_system_by_id(cache_repo, id) end)
    |> Enum.filter(&(&1 != nil))
  end

  defp fetch_system_by_id(cache_repo, id) do
    cache_repo.get("map:system:#{id}")
  end

  # Check if a system is a wormhole system
  defp wormhole_system?(system) when is_map(system) do
    # Check system ID range (31000000-31999999 is J-space)
    system_id = get_system_id(system)
    is_integer(system_id) && system_id >= 31_000_000 && system_id < 32_000_000
  end

  defp wormhole_system?(_), do: false

  # Get system ID from either a MapSystem struct or a map
  defp get_system_id(system) do
    cond do
      is_struct(system, WandererNotifier.Data.MapSystem) ->
        system.solar_system_id

      is_map(system) ->
        # Try various possible keys for system ID
        Map.get(system, "solar_system_id") ||
          Map.get(system, :solar_system_id) ||
          Map.get(system, "system_id") ||
          Map.get(system, :system_id) ||
          Map.get(system, "systemId") ||
          Map.get(system, :systemId)

      true ->
        nil
    end
  end
end
