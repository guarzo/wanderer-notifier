defmodule WandererNotifier.Services.NotificationDeterminer do
  @moduledoc """
  Central module for determining whether notifications should be sent based on tracking criteria.
  This module handles the logic for deciding if a kill, system, or character event should trigger
  a notification based on configured tracking rules.
  """
  require Logger
  alias WandererNotifier.Core.Features
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
      Logger.debug(
        "🔕 NOTIFICATION BLOCKED: Kill notifications are disabled globally (ENABLE_KILL_NOTIFICATIONS=false)"
      )

      false
    else
      # Extract system ID if not provided
      system_id = system_id || extract_system_id(killmail)

      # Get system name for better logging
      system_name = get_system_name(system_id)
      system_info = if system_name, do: "#{system_id} (#{system_name})", else: system_id

      kill_id =
        if is_map(killmail),
          do: Map.get(killmail, :killmail_id) || Map.get(killmail, "killmail_id"),
          else: "unknown"

      # Check if the kill is in a tracked system
      is_tracked_system = is_tracked_system?(system_id)

      # Check if the kill involves a tracked character
      has_tracked_character = has_tracked_character?(killmail)

      # Log the decision factors
      Logger.debug(
        "NOTIFICATION CRITERIA: Kill #{kill_id} - System #{system_info} tracked? #{is_tracked_system}"
      )

      Logger.debug(
        "NOTIFICATION CRITERIA: Kill #{kill_id} - Has tracked character? #{has_tracked_character}"
      )

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
  def is_tracked_system?(system_id) when is_integer(system_id) or is_binary(system_id) do
    # Convert system_id to string for consistent comparison
    system_id_str = to_string(system_id)

    # Get system name for better logging
    system_name = get_system_name(system_id)
    system_info = if system_name, do: "#{system_id} (#{system_name})", else: system_id

    # Direct check in tracked systems cache
    cache_key = "tracked:system:#{system_id_str}"
    is_tracked = WandererNotifier.Data.Cache.Repository.get(cache_key) != nil

    # Also check if system exists in main cache
    system_cache_key = "map:system:#{system_id_str}"
    exists_in_cache = WandererNotifier.Data.Cache.Repository.get(system_cache_key) != nil

    # Track all systems if configured
    track_all = Features.track_all_systems?()

    # System is tracked if it's explicitly tracked or if track_all is enabled and system exists
    tracked = is_tracked || (track_all && exists_in_cache)

    # Add detailed logging
    if tracked do
      Logger.debug("TRACKING: System #{system_info} is tracked ✅")

      if is_tracked do
        Logger.debug("TRACKING DETAIL: System is explicitly tracked (#{cache_key}=true)")
      else
        Logger.debug(
          "TRACKING DETAIL: System is tracked due to TRACK_ALL_SYSTEMS=true and exists in #{system_cache_key}"
        )
      end
    else
      Logger.debug("TRACKING: System #{system_info} is NOT tracked ❌")

      Logger.debug(
        "TRACKING DETAIL: Not found in #{cache_key} and either TRACK_ALL_SYSTEMS=false or not in #{system_cache_key}"
      )
    end

    tracked
  end

  def is_tracked_system?(_), do: false

  @doc """
  Checks if a killmail involves a tracked character (as victim or attacker).

  ## Parameters
    - killmail: The killmail data to check

  ## Returns
    - true if the killmail involves a tracked character
    - false otherwise
  """
  def has_tracked_character?(killmail) do
    # Handle different killmail formats
    kill_data =
      case killmail do
        %Killmail{esi_data: esi_data} when is_map(esi_data) -> esi_data
        kill when is_map(kill) -> kill
        _ -> %{}
      end

    kill_id =
      if is_map(killmail),
        do: Map.get(killmail, :killmail_id) || Map.get(killmail, "killmail_id"),
        else: "unknown"

    # Check victim
    victim = Map.get(kill_data, "victim") || Map.get(kill_data, :victim) || %{}
    victim_id = Map.get(victim, "character_id") || Map.get(victim, :character_id)
    victim_id_str = if victim_id, do: to_string(victim_id), else: nil

    # Check if victim is tracked using direct cache lookup
    victim_tracked =
      if victim_id_str do
        cache_key = "tracked:character:#{victim_id_str}"
        is_tracked = WandererNotifier.Data.Cache.Repository.get(cache_key) != nil

        if is_tracked do
          Logger.debug("CHARACTER TRACKING: Victim character cache hit: #{cache_key}")
        end

        is_tracked
      else
        false
      end

    if victim_tracked do
      Logger.debug(
        "CHARACTER TRACKING: Victim with ID #{victim_id_str} in kill #{kill_id} is tracked"
      )

      true
    else
      # Check attackers
      attackers = Map.get(kill_data, "attackers") || Map.get(kill_data, :attackers) || []

      # Extract all attacker character IDs
      attacker_ids =
        attackers
        |> Enum.map(fn attacker ->
          char_id = Map.get(attacker, "character_id") || Map.get(attacker, :character_id)
          if char_id, do: to_string(char_id), else: nil
        end)
        |> Enum.reject(&is_nil/1)

      # Find tracked attackers using direct cache lookup
      tracked_attacker_ids =
        Enum.filter(attacker_ids, fn id ->
          cache_key = "tracked:character:#{id}"
          is_tracked = WandererNotifier.Data.Cache.Repository.get(cache_key) != nil

          if is_tracked do
            Logger.debug("CHARACTER TRACKING: Attacker character cache hit: #{cache_key}")
          end

          is_tracked
        end)

      tracked_count = length(tracked_attacker_ids)

      if tracked_count > 0 do
        Logger.debug(
          "CHARACTER TRACKING: Found #{tracked_count} tracked attackers in kill #{kill_id}: #{inspect(tracked_attacker_ids)}"
        )

        true
      else
        Logger.debug("CHARACTER TRACKING: No tracked characters found in kill #{kill_id}")
        false
      end
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
      # Convert to string for consistent comparison
      character_id_str = to_string(character_id)

      # Direct check in tracked characters cache
      cache_key = "tracked:character:#{character_id_str}"
      is_tracked = WandererNotifier.Data.Cache.Repository.get(cache_key) != nil

      if is_tracked do
        Logger.debug(
          "NOTIFICATION DECISION: Character #{character_id} is tracked (#{cache_key}=true)"
        )

        true
      else
        Logger.debug(
          "NOTIFICATION DECISION: Character #{character_id} is not tracked (#{cache_key} not found)"
        )

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

      # Get system name for better logging
      system_name = get_system_name(system_id)
      system_info = if system_name, do: "#{system_id} (#{system_name})", else: system_id

      if is_tracked do
        Logger.debug("NOTIFICATION DECISION: System #{system_info} is tracked")
        true
      else
        Logger.debug("NOTIFICATION DECISION: System #{system_info} is not tracked")
        false
      end
    end
  end

  # Helper function to get system name
  defp get_system_name(nil), do: nil

  defp get_system_name(system_id) do
    case WandererNotifier.Api.ESI.Service.get_system_info(system_id) do
      {:ok, system_info} -> Map.get(system_info, "name")
      _ -> nil
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
