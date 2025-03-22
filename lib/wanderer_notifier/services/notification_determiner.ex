defmodule WandererNotifier.Services.NotificationDeterminer do
  @moduledoc """
  Central module for determining whether notifications should be sent based on tracking criteria.
  This module handles the logic for deciding if a kill, system, or character event should trigger
  a notification based on configured tracking rules.
  """
  require Logger
  alias WandererNotifier.Core.Features
  alias WandererNotifier.Data.Killmail
  alias WandererNotifier.Helpers.DeduplicationHelper

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
    if Features.kill_notifications_enabled?() do
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
      is_tracked_system = tracked_system?(system_id)

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
    else
      Logger.debug(
        "🔕 NOTIFICATION BLOCKED: Kill notifications are disabled globally (ENABLE_KILL_NOTIFICATIONS=false)"
      )

      false
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
  def tracked_system?(system_id) when is_integer(system_id) or is_binary(system_id) do
    # Convert system_id to string for consistent comparison
    system_id_str = to_string(system_id)

    # Get system information for logging
    system_info = format_system_info(system_id)

    # Check if system is tracked through direct tracking or track_all policy
    tracked = directly_tracked?(system_id_str) || tracked_via_track_all?(system_id_str)

    # Log the tracking status with appropriate details
    log_tracking_status(tracked, system_info, system_id_str)

    tracked
  end

  def tracked_system?(_), do: false

  # Helper functions for tracked_system?
  defp format_system_info(system_id) do
    system_name = get_system_name(system_id)
    if system_name, do: "#{system_id} (#{system_name})", else: system_id
  end

  defp directly_tracked?(system_id_str) do
    cache_key = "tracked:system:#{system_id_str}"
    WandererNotifier.Data.Cache.Repository.get(cache_key) != nil
  end

  defp tracked_via_track_all?(system_id_str) do
    # Check if system exists in main cache and track_all is enabled
    system_cache_key = "map:system:#{system_id_str}"
    exists_in_cache = WandererNotifier.Data.Cache.Repository.get(system_cache_key) != nil
    Features.track_all_systems?() && exists_in_cache
  end

  defp log_tracking_status(tracked, system_info, system_id_str) do
    if tracked do
      Logger.debug("TRACKING: System #{system_info} is tracked ✅")

      if directly_tracked?(system_id_str) do
        Logger.debug(
          "TRACKING DETAIL: System is explicitly tracked (tracked:system:#{system_id_str}=true)"
        )
      else
        Logger.debug(
          "TRACKING DETAIL: System is tracked due to TRACK_ALL_SYSTEMS=true and exists in map:system:#{system_id_str}"
        )
      end
    else
      Logger.debug("TRACKING: System #{system_info} is NOT tracked ❌")

      Logger.debug(
        "TRACKING DETAIL: Not found in tracked:system:#{system_id_str} and either TRACK_ALL_SYSTEMS=false or not in map:system:#{system_id_str}"
      )
    end
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
    # Handle different killmail formats
    kill_data = extract_kill_data(killmail)
    kill_id = extract_kill_id(killmail)

    Logger.debug("CHARACTER TRACKING: Checking kill #{kill_id} for tracked characters")

    # Get all tracked character IDs for comparison
    all_character_ids = get_all_tracked_character_ids()

    # For debugging, log sample character IDs
    log_sample_character_ids(all_character_ids)

    # Check if victim is tracked
    victim_tracked = check_victim_tracked(kill_data, kill_id, all_character_ids)

    if victim_tracked do
      # Early return if victim is tracked
      Logger.info("CHARACTER TRACKING: Found tracked victim in kill #{kill_id}")
      true
    else
      # Check if any attacker is tracked
      check_attackers_tracked(kill_data, kill_id, all_character_ids)
    end
  end

  # Extract kill data from various killmail formats
  defp extract_kill_data(killmail) do
    case killmail do
      %Killmail{esi_data: esi_data} when is_map(esi_data) -> esi_data
      kill when is_map(kill) -> kill
      _ -> %{}
    end
  end

  # Extract kill ID from killmail
  defp extract_kill_id(killmail) do
    if is_map(killmail),
      do: Map.get(killmail, :killmail_id) || Map.get(killmail, "killmail_id"),
      else: "unknown"
  end

  # Get all tracked character IDs
  defp get_all_tracked_character_ids do
    all_characters = WandererNotifier.Data.Cache.Repository.get("map:characters") || []

    Enum.map(all_characters, fn char ->
      # Only use eve_id for consistency
      eve_id = Map.get(char, "eve_id") || Map.get(char, :eve_id)
      if eve_id, do: to_string(eve_id), else: nil
    end)
    |> Enum.reject(&is_nil/1)
  end

  # Log a sample of character IDs for debugging
  defp log_sample_character_ids(all_character_ids) do
    sample_character_ids = Enum.take(all_character_ids, min(5, length(all_character_ids)))

    Logger.info(
      "CHARACTER TRACKING: Using #{length(all_character_ids)} tracked characters. Sample: #{inspect(sample_character_ids)}"
    )
  end

  # Extract victim ID from kill data
  defp extract_victim_id(kill_data) do
    victim = Map.get(kill_data, "victim") || Map.get(kill_data, :victim) || %{}
    victim_id = Map.get(victim, "character_id") || Map.get(victim, :character_id)
    if victim_id, do: to_string(victim_id), else: nil
  end

  # Log victim information for debugging
  defp log_victim_info(victim_id_str, kill_id) do
    if victim_id_str do
      Logger.debug("CHARACTER TRACKING: Victim ID in kill #{kill_id} is #{victim_id_str}")
    else
      Logger.debug("CHARACTER TRACKING: No victim character ID found in kill #{kill_id}")
    end
  end

  # Check if victim is tracked through direct cache lookup
  defp check_direct_victim_tracking(victim_id_str) do
    direct_cache_key = "tracked:character:#{victim_id_str}"
    direct_tracked = WandererNotifier.Data.Cache.Repository.get(direct_cache_key) != nil

    if direct_tracked do
      Logger.info(
        "CHARACTER TRACKING: Victim #{victim_id_str} found via direct cache key #{direct_cache_key}"
      )
      true
    else
      false
    end
  end

  # Check if the victim in this kill is being tracked
  defp check_victim_tracked(kill_data, kill_id, all_character_ids) do
    # Extract and format victim ID
    victim_id_str = extract_victim_id(kill_data)
    
    # Log victim information
    log_victim_info(victim_id_str, kill_id)

    # Check if victim is tracked against eve_id list
    victim_tracked = victim_id_str && Enum.member?(all_character_ids, victim_id_str)

    # Also try direct cache lookup for victim if not already tracked
    if !victim_tracked && victim_id_str do
      check_direct_victim_tracking(victim_id_str)
    else
      victim_tracked
    end
  end

  # Check if any attacker in this kill is being tracked
  defp check_attackers_tracked(kill_data, kill_id, all_character_ids) do
    # Check attackers
    attackers = Map.get(kill_data, "attackers") || Map.get(kill_data, :attackers) || []

    # Log attackers count for debugging
    Logger.debug("CHARACTER TRACKING: Kill #{kill_id} has #{length(attackers)} attackers")

    # Now extract all attacker IDs for checking
    attacker_ids =
      attackers
      |> Enum.map(fn attacker ->
        char_id = Map.get(attacker, "character_id") || Map.get(attacker, :character_id)
        if char_id, do: to_string(char_id), else: nil
      end)
      |> Enum.reject(&is_nil/1)

    Logger.debug(
      "CHARACTER TRACKING: Found #{length(attacker_ids)} attacker IDs in kill #{kill_id}: #{inspect(attacker_ids)}"
    )

    # Check if any attacker is in our tracked characters
    any_attacker_tracked_by_id =
      Enum.any?(attacker_ids, fn id ->
        is_tracked = Enum.member?(all_character_ids, id)

        if is_tracked do
          Logger.info("CHARACTER TRACKING: Found tracked attacker #{id} in kill #{kill_id}")
        end

        is_tracked
      end)

    # Also try direct cache lookup for additional safety
    any_attacker_tracked_by_cache =
      Enum.any?(attacker_ids, fn id ->
        cache_key = "tracked:character:#{id}"
        is_tracked = WandererNotifier.Data.Cache.Repository.get(cache_key) != nil

        if is_tracked do
          Logger.info(
            "CHARACTER TRACKING: Attacker #{id} found via direct cache key #{cache_key}"
          )
        end

        is_tracked
      end)

    # Return true if any attacker is tracked by either method
    any_attacker_tracked_by_id || any_attacker_tracked_by_cache
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
    if Features.enabled?(:tracked_characters_notifications) do
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
    else
      Logger.debug("NOTIFICATION DECISION: Character notifications are disabled globally")
      false
    end
  end

  @doc """
  Determines if we should send a notification for a system.

  ## Parameters
    - system_id: The system ID to check

  ## Returns
    - true if we should notify, false otherwise
  """
  def should_notify_system?(system_id) do
    # Check if system notifications are enabled globally
    if Features.enabled?(:tracked_systems_notifications) do
      is_tracked = tracked_system?(system_id)
      system_name = get_system_name(system_id)
      system_info = if system_name, do: "#{system_id} (#{system_name})", else: system_id

      if is_tracked do
        Logger.debug("NOTIFICATION DECISION: System #{system_info} is tracked")
        true
      else
        Logger.debug("NOTIFICATION DECISION: System #{system_info} is not tracked")
        false
      end
    else
      Logger.debug("NOTIFICATION DECISION: System notifications are disabled globally")
      false
    end
  end

  # Helper function to get system name
  defp get_system_name(nil), do: nil

  defp get_system_name(system_id) do
    case WandererNotifier.Api.ESI.Service.get_system_info(system_id) do
      {:ok, system_info} -> Map.get(system_info, "name")
      {:error, :not_found} -> "Unknown-#{system_id}"
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

  @doc """
  Centralized deduplication check for notifications.
  Uses a day-based global key approach for consistent deduplication across service restarts.

  ## Parameters
    - type: The notification type (:kill, :system, :character)
    - id: The ID of the entity

  ## Returns
    - {:ok, :send} if notification should be sent (not a duplicate)
    - {:ok, :skip} if notification should be skipped (duplicate)
    - {:error, reason} if there was an error in the check
  """
  def check_deduplication(type, id)
      when type in [:kill, :system, :character] and (is_binary(id) or is_integer(id)) do
    id_str = to_string(id)
    day_str = Date.utc_today() |> Date.to_string()
    global_key = "global:#{type}:#{day_str}:#{id_str}"

    Logger.info("DEDUPLICATION: Checking for #{type} #{id_str}")

    # Delegate deduplication check to helper and translate the response
    case DeduplicationHelper.check_and_mark(global_key) do
      {:ok, :new} ->
        Logger.info("DEDUPLICATION: #{type} #{id_str} is new, sending notification")
        {:ok, :send}

      {:ok, :duplicate} ->
        Logger.info("DEDUPLICATION: #{type} #{id_str} is a duplicate, skipping notification")
        {:ok, :skip}

      error ->
        Logger.error("DEDUPLICATION: Error checking #{type} #{id_str}: #{inspect(error)}")
        # Default to allowing notification in case of errors
        {:error, "Deduplication check failed: #{inspect(error)}"}
    end
  end

  def check_deduplication(_type, id) do
    Logger.warning("DEDUPLICATION: Invalid type or ID (#{inspect(id)}) for deduplication check")
    # Default to sending notification if we can't properly check
    {:ok, :send}
  end
end
