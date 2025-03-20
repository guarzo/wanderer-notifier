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
    # Extract character ID - only accept numeric IDs
    cond do
      # Check top level character_id
      is_binary(character["character_id"]) && is_valid_numeric_id?(character["character_id"]) ->
        character["character_id"]

      # Check top level eve_id
      is_binary(character["eve_id"]) && is_valid_numeric_id?(character["eve_id"]) ->
        character["eve_id"]

      # Check nested character object
      is_map(character["character"]) && is_binary(character["character"]["eve_id"]) &&
          is_valid_numeric_id?(character["character"]["eve_id"]) ->
        character["character"]["eve_id"]

      is_map(character["character"]) && is_binary(character["character"]["character_id"]) &&
          is_valid_numeric_id?(character["character"]["character_id"]) ->
        character["character"]["character_id"]

      is_map(character["character"]) && is_binary(character["character"]["id"]) &&
          is_valid_numeric_id?(character["character"]["id"]) ->
        character["character"]["id"]

      # No valid numeric ID found
      true ->
        Logger.error(
          "No valid numeric EVE ID found for character: #{inspect(character, pretty: true, limit: 500)}"
        )

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
    cond do
      character["character_name"] != nil ->
        character["character_name"]

      character["name"] != nil ->
        character["name"]

      is_map(character["character"]) && character["character"]["name"] != nil ->
        character["character"]["name"]

      is_map(character["character"]) && character["character"]["character_name"] != nil ->
        character["character"]["character_name"]

      true ->
        character_id = extract_character_id(character)
        if character_id, do: "Character #{character_id}", else: default
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
  @spec is_valid_numeric_id?(String.t() | any()) :: boolean()
  def is_valid_numeric_id?(id) when is_binary(id) do
    case Integer.parse(id) do
      {num, ""} when num > 0 -> true
      _ -> false
    end
  end

  def is_valid_numeric_id?(_), do: false

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

    # Get all tracked systems from cache
    tracked_systems = get_tracked_systems()
    Logger.info("Found #{length(tracked_systems)} tracked systems")

    # Select a random wormhole system if available, or any system if no wormholes
    selected_system =
      tracked_systems
      |> Enum.filter(&is_wormhole_system?/1)
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

    # Extract system ID and name
    system_id = get_system_id(selected_system)
    system_name = get_system_name(selected_system)

    Logger.info("Using system #{system_name} (ID: #{system_id}) for test notification")

    # Use the API's built-in enrichment function if it's a MapSystem struct
    enriched_system = if is_struct(selected_system, WandererNotifier.Data.MapSystem) do
      Logger.info("MapSystem struct detected, using API's enrich_system function")

      # Use the built-in enrichment function that knows how to handle MapSystem structs
      case WandererNotifier.Api.Map.SystemStaticInfo.enrich_system(selected_system) do
        {:ok, enriched} ->
          Logger.info("Successfully enriched system with static info")
          enriched
        {:error, reason} ->
          Logger.warning("Failed to enrich system: #{inspect(reason)}")
          # Return the original system if enrichment fails
          selected_system
      end
    else
      # Not a MapSystem struct, just use it as-is
      selected_system
    end

    # Send the enriched system through the normal notification flow
    Logger.info("Sending notification with enriched system")

    # Create a notification payload with the enriched system
    system_data = %{
      "id" => get_system_id(enriched_system),
      "name" => get_system_name(enriched_system),
      "url" => "https://zkillboard.com/system/#{get_system_id(enriched_system)}/",
      "system" => enriched_system
    }

    # Send notification with the system data
    notifier = NotifierFactory.get_notifier()
    notifier.send_new_system_notification(system_data)

    {:ok, get_system_id(enriched_system), get_system_name(enriched_system)}
  end

  # Helper functions for test system notification

  # Get tracked systems from cache
  defp get_tracked_systems() do
    alias WandererNotifier.Data.Cache.Repository, as: CacheRepo

    # Try to get systems from the "map:systems" cache key
    case CacheRepo.get("map:systems") do
      systems when is_list(systems) and length(systems) > 0 ->
        systems
      _ ->
        # Try to get system IDs and then fetch individual systems
        case CacheRepo.get("map:system_ids") do
          ids when is_list(ids) and length(ids) > 0 ->
            # Get all systems by ID
            ids
            |> Enum.map(fn id ->
              case CacheRepo.get("map:system:#{id}") do
                nil -> nil
                system -> system
              end
            end)
            |> Enum.filter(&(&1 != nil))
          _ ->
            # No systems found
            []
        end
    end
  end

  # Check if a system is a wormhole system
  defp is_wormhole_system?(system) when is_map(system) do
    # Check system ID range (31000000-31999999 is J-space)
    system_id = get_system_id(system)
    is_integer(system_id) && system_id >= 31000000 && system_id < 32000000
  end
  defp is_wormhole_system?(_), do: false

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

  # Get system name from either a MapSystem struct or a map
  defp get_system_name(system) do
    cond do
      is_struct(system, WandererNotifier.Data.MapSystem) ->
        system.name

      is_map(system) ->
        # Try various possible keys for system name
        Map.get(system, "name") ||
        Map.get(system, :name) ||
        Map.get(system, "system_name") ||
        Map.get(system, :system_name) ||
        Map.get(system, "systemName") ||
        Map.get(system, :systemName) ||
        "Unknown System"

      true ->
        "Unknown System"
    end
  end
end
