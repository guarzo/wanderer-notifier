defmodule WandererNotifier.Services.NotificationDeterminer do
  @moduledoc """
  Central module for determining whether notifications should be sent based on tracking criteria.
  This module handles the logic for deciding if a kill, system, or character event should trigger
  a notification based on configured tracking rules.
  """
  require Logger
  alias WandererNotifier.Core.Features
  alias WandererNotifier.Helpers.CacheHelpers
  alias WandererNotifier.Data.Killmail

  @doc """
  Determines if a killmail should trigger a notification.
  Checks against tracked systems and characters.

  ## Parameters
    - killmail: The killmail data (as Killmail struct or map)
    - system_id: Optional system ID override (useful when extracted earlier)

  ## Returns
    - true if notification should be sent
    - false otherwise with reason logged
  """
  def should_notify_kill?(killmail, system_id \\ nil) do
    # Check if kill notifications are enabled globally
    if !Features.kill_notifications_enabled?() do
      Logger.debug("NOTIFICATION DECISION: Kill notifications are disabled globally")
      false
    else
      # Extract system ID if not provided
      system_id = system_id || extract_system_id(killmail)

      # Check if the kill is in a tracked system
      is_tracked_system = is_tracked_system?(system_id)

      # Check if the kill involves a tracked character
      has_tracked_character = has_tracked_character?(killmail)

      # Log the decision factors
      Logger.debug("NOTIFICATION CRITERIA: System #{system_id} tracked? #{is_tracked_system}")
      Logger.debug("NOTIFICATION CRITERIA: Has tracked character? #{has_tracked_character}")

      # Return true if either condition is met
      is_tracked_system || has_tracked_character
    end
  end

  @doc """
  Checks if a system is being tracked.

  ## Parameters
    - system_id: The ID of the system to check

  ## Returns
    - true if the system is tracked
    - false otherwise
  """
  def is_tracked_system?(nil), do: false

  def is_tracked_system?(system_id) do
    # Get all tracked systems from cache
    tracked_systems = CacheHelpers.get_tracked_systems()

    # Convert system ID to string for consistent comparison
    system_id_str = to_string(system_id)

    # Extract system IDs from tracked systems
    tracked_ids =
      Enum.map(tracked_systems, fn system ->
        case system do
          %{solar_system_id: id} when not is_nil(id) -> to_string(id)
          %{"solar_system_id" => id} when not is_nil(id) -> to_string(id)
          %{system_id: id} when not is_nil(id) -> to_string(id)
          %{"system_id" => id} when not is_nil(id) -> to_string(id)
          _ -> nil
        end
      end)
      |> Enum.filter(&(&1 != nil))

    # Check if this system ID is in the tracked systems list
    system_id_str in tracked_ids
  end

  @doc """
  Checks if a killmail involves a tracked character (as victim or attacker).

  ## Parameters
    - killmail: The killmail data to check

  ## Returns
    - true if the killmail involves a tracked character
    - false otherwise
  """
  def has_tracked_character?(killmail) do
    # Get all tracked characters
    tracked_characters = CacheHelpers.get_tracked_characters()

    # Extract character IDs from tracked characters list (handle different data formats)
    tracked_char_ids =
      Enum.map(tracked_characters, fn char ->
        case char do
          %{character_id: id} when not is_nil(id) -> to_string(id)
          %{"character_id" => id} when not is_nil(id) -> to_string(id)
          id when is_integer(id) or is_binary(id) -> to_string(id)
          _ -> nil
        end
      end)
      |> Enum.filter(&(&1 != nil))

    # Handle different killmail formats
    kill_data =
      case killmail do
        %Killmail{esi_data: esi_data} when is_map(esi_data) -> esi_data
        kill when is_map(kill) -> kill
        _ -> %{}
      end

    # Check victim
    victim = Map.get(kill_data, "victim") || Map.get(kill_data, :victim) || %{}
    victim_id = Map.get(victim, "character_id") || Map.get(victim, :character_id)
    victim_id_str = if victim_id, do: to_string(victim_id), else: nil
    victim_tracked = victim_id_str && victim_id_str in tracked_char_ids

    if victim_tracked do
      Logger.debug("TRACKED CHARACTER: Victim with ID #{victim_id_str} is tracked")
      true
    else
      # Check attackers
      attackers = Map.get(kill_data, "attackers") || Map.get(kill_data, :attackers) || []

      Enum.any?(attackers, fn attacker ->
        attacker_id = Map.get(attacker, "character_id") || Map.get(attacker, :character_id)
        attacker_id_str = if attacker_id, do: to_string(attacker_id), else: nil
        is_tracked = attacker_id_str && attacker_id_str in tracked_char_ids

        if is_tracked do
          Logger.debug("TRACKED CHARACTER: Attacker with ID #{attacker_id_str} is tracked")
        end

        is_tracked
      end)
    end
  end

  @doc """
  Determines if a character event should trigger a notification.

  ## Parameters
    - character_id: The ID of the character

  ## Returns
    - true if the character is tracked
    - false otherwise
  """
  def should_notify_character?(character_id)
      when is_integer(character_id) or is_binary(character_id) do
    # Check if character notifications are enabled globally
    if !Features.enabled?(:tracked_characters_notifications) do
      Logger.debug("NOTIFICATION DECISION: Character notifications are disabled globally")
      false
    else
      # Get all tracked characters
      tracked_characters = CacheHelpers.get_tracked_characters()

      # Convert to string for consistent comparison
      character_id_str = to_string(character_id)

      # Check if this character ID is in the tracked characters list
      is_tracked =
        Enum.any?(tracked_characters, fn char ->
          case char do
            %{character_id: id} when not is_nil(id) -> to_string(id) == character_id_str
            %{"character_id" => id} when not is_nil(id) -> to_string(id) == character_id_str
            id when is_integer(id) or is_binary(id) -> to_string(id) == character_id_str
            _ -> false
          end
        end)

      if is_tracked do
        Logger.debug("NOTIFICATION DECISION: Character #{character_id} is tracked")
        true
      else
        Logger.debug("NOTIFICATION DECISION: Character #{character_id} is not tracked")
        false
      end
    end
  end

  @doc """
  Determines if a system event should trigger a notification.

  ## Parameters
    - system_id: The ID of the system

  ## Returns
    - true if the system is tracked
    - false otherwise
  """
  def should_notify_system?(system_id) do
    # Check if system notifications are enabled globally
    if !Features.enabled?(:tracked_systems_notifications) do
      Logger.debug("NOTIFICATION DECISION: System notifications are disabled globally")
      false
    else
      is_tracked = is_tracked_system?(system_id)

      if is_tracked do
        Logger.debug("NOTIFICATION DECISION: System #{system_id} is tracked")
        true
      else
        Logger.debug("NOTIFICATION DECISION: System #{system_id} is not tracked")
        false
      end
    end
  end

  # Helper function to extract system ID from a killmail
  defp extract_system_id(%Killmail{} = killmail) do
    case killmail do
      %Killmail{esi_data: esi_data} when is_map(esi_data) ->
        Map.get(esi_data, "solar_system_id")

      _ ->
        nil
    end
  end

  defp extract_system_id(killmail) when is_map(killmail) do
    # Try to get system ID from various possible locations
    Map.get(killmail, "solar_system_id") ||
      Map.get(killmail, :solar_system_id) ||
      get_in(killmail, ["esi_data", "solar_system_id"]) ||
      get_in(killmail, [:esi_data, "solar_system_id"])
  end

  defp extract_system_id(_), do: nil
end
