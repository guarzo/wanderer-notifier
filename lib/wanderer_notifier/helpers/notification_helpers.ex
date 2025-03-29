defmodule WandererNotifier.Helpers.NotificationHelpers do
  @moduledoc """
  Helper functions for notification formatting and data extraction.
  """
  require Logger
  alias WandererNotifier.Data.Cache.Repository, as: CacheRepo, as: CacheRepo
  alias WandererNotifier.Data.Character
  alias WandererNotifier.Data.MapSystem
  alias WandererNotifier.Logger, as: AppLogger
  alias WandererNotifier.Notifiers.Factory, as: NotifierFactory

  @doc """
  Extracts a valid EVE character ID from a character map.
  Handles various possible key structures.

  Returns the ID as a string or nil if no valid ID is found.
  """
  @spec extract_character_id(map()) :: String.t() | nil
  def extract_character_id(character) when is_map(character) do
    # Handle Character struct specially
    if is_struct(character, Character) do
      character.character_id
    else
      # Try extracting from different possible locations in order of preference
      character_id =
        check_top_level_id(character) ||
          check_nested_character_id(character)

      # Log error if no valid ID was found
      if is_nil(character_id) do
        AppLogger.processor_error(
          "No valid numeric EVE ID found for character",
          character_data: inspect(character, pretty: true, limit: 500)
        )
      end

      character_id
    end
  end

  # Check for valid ID at the top level of the character map
  defp check_top_level_id(character) do
    check_valid_id(character, "character_id")
  end

  # Check for valid ID in nested character object
  defp check_nested_character_id(character) do
    # Return nil if there's no nested character object
    nested = character["character"]

    if is_map(nested) do
      # Check key in the nested object
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
  Sends a test system notification using a real tracked system.
  Returns an error if no systems are being tracked.
  """
  @spec send_test_system_notification() ::
          {:ok, String.t(), String.t()} | {:error, :no_tracked_systems}
  def send_test_system_notification do
    # Get tracked systems
    tracked_systems = get_tracked_systems()
    AppLogger.processor_info("Found tracked systems", count: length(tracked_systems))

    case tracked_systems do
      [] ->
        AppLogger.processor_warn("No systems are currently being tracked")
        {:error, :no_tracked_systems}

      systems ->
        # Use an existing system
        selected_system = Enum.random(systems)
        map_system = MapSystem.new(selected_system)
        notifier = NotifierFactory.get_notifier()
        notifier.send_new_system_notification(map_system)
        {:ok, map_system.solar_system_id, map_system.name}
    end
  end

  @doc """
  Sends a test kill notification using a real recent kill.
  Returns an error if no kills are available.
  """
  @spec send_test_kill_notification() :: {:ok, String.t()} | {:error, :no_recent_kills}
  def send_test_kill_notification do
    case CacheRepo.get("kills:recent") do
      nil ->
        AppLogger.processor_warn("No recent kills available in cache")
        {:error, :no_recent_kills}

      [] ->
        AppLogger.processor_warn("Recent kills cache is empty")
        {:error, :no_recent_kills}

      kills when is_list(kills) ->
        # Use most recent kill
        kill = List.first(kills)
        notifier = NotifierFactory.get_notifier()
        notifier.send_enriched_kill_embed(kill, kill.killmail_id)
        {:ok, kill.killmail_id}
    end
  end

  @doc """
  Sends a test character notification using a real tracked character.
  Returns an error if no characters are being tracked.
  """
  @spec send_test_character_notification() ::
          {:ok, String.t(), String.t()} | {:error, :no_tracked_characters}
  def send_test_character_notification do
    case CacheRepo.get("map:characters") do
      nil ->
        AppLogger.processor_warn("No characters are currently being tracked")
        {:error, :no_tracked_characters}

      [] ->
        AppLogger.processor_warn("No characters are currently being tracked")
        {:error, :no_tracked_characters}

      characters when is_list(characters) ->
        selected = Enum.random(characters)
        character = Character.new(selected)
        notifier = NotifierFactory.get_notifier()
        notifier.send_new_tracked_character_notification(character)
        {:ok, character.character_id, character.name}
    end
  end

  # Helper functions for test system notification

  # Get tracked systems from cache
  defp get_tracked_systems do
    # Try to get systems from the "map:systems" cache key
    get_systems_from_main_cache(CacheRepo) || get_systems_from_individual_caches(CacheRepo)
  end

  defp get_systems_from_main_cache(cache_repo) do
    case cache_repo.get("map:systems") do
      systems when is_list(systems) and length(systems) > 0 ->
        # Filter for wormhole systems only
        Enum.filter(systems, &wormhole_system?/1)

      _ ->
        nil
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
  defp get_system_id(%WandererNotifier.Data.MapSystem{} = system), do: system.solar_system_id

  defp get_system_id(%{} = system) do
    system_id = find_system_id_in_map(system)
    parse_system_id(system_id)
  end

  defp get_system_id(_), do: nil

  # Helper to find system ID in map using various possible keys
  defp find_system_id_in_map(system) do
    possible_keys = [
      "solar_system_id",
      :solar_system_id,
      "system_id",
      :system_id,
      "systemId",
      :systemId
    ]

    Enum.find_value(possible_keys, fn key -> Map.get(system, key) end)
  end

  # Helper to parse system ID from string or integer
  defp parse_system_id(id) when is_binary(id) do
    case Integer.parse(id) do
      {num, ""} -> num
      _ -> nil
    end
  end

  defp parse_system_id(id) when is_integer(id), do: id
  defp parse_system_id(_), do: nil
end
