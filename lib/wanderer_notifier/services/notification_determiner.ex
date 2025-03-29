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
  alias WandererNotifier.Logger, as: AppLogger
  alias WandererNotifier.Config.Features

  @doc """
  Determine if a kill notification should be sent.

  ## Parameters
    - killmail: The killmail data
    - system_id: Optional system ID (will extract from killmail if not provided)

  ## Returns
    - true if notification should be sent
    - false otherwise with reason logged
  """
  def should_notify_kill?(killmail, system_id \\ nil) do
    # Check if kill notifications are enabled globally
    if Features.kill_notifications_enabled?() do
      # Extract kill details for decision making
      kill_details = extract_kill_details(killmail, system_id)

      # Log the decision factors
      log_notification_criteria(kill_details)

      # Check if this kill should be considered for notification
      if kill_meets_tracking_criteria?(kill_details) do
        check_deduplication_and_decide(kill_details.kill_id)
      else
        log_kill_not_tracked(kill_details.kill_id)
        false
      end
    else
      log_notifications_disabled()
      false
    end
  end

  # Extract all relevant kill details for decision making
  defp extract_kill_details(killmail, provided_system_id) do
    # Extract system ID if not provided
    system_id = provided_system_id || extract_system_id(killmail)
    system_name = get_system_name(system_id)

    kill_id =
      if is_map(killmail),
        do: Map.get(killmail, :killmail_id) || Map.get(killmail, "killmail_id"),
        else: "unknown"

    # Check tracking criteria
    is_tracked_system = tracked_system?(system_id)
    has_tracked_character = has_tracked_character?(killmail)

    %{
      kill_id: kill_id,
      system_id: system_id,
      system_name: system_name,
      is_tracked_system: is_tracked_system,
      has_tracked_character: has_tracked_character
    }
  end

  # Log notification criteria details
  defp log_notification_criteria(kill_details) do
    AppLogger.processor_debug("Evaluating notification criteria",
      kill_id: kill_details.kill_id,
      system_id: kill_details.system_id,
      system_name: kill_details.system_name,
      is_tracked_system: kill_details.is_tracked_system,
      has_tracked_character: kill_details.has_tracked_character
    )
  end

  # Check if kill meets any tracking criteria
  defp kill_meets_tracking_criteria?(kill_details) do
    kill_details.is_tracked_system || kill_details.has_tracked_character
  end

  # Log that notifications are disabled
  defp log_notifications_disabled do
    AppLogger.processor_debug("Kill notifications are disabled globally",
      setting: "ENABLE_KILL_NOTIFICATIONS=false"
    )
  end

  # Log that kill is not tracked
  defp log_kill_not_tracked(kill_id) do
    AppLogger.processor_debug("Kill not in tracked system or with tracked character",
      kill_id: kill_id
    )
  end

  # Apply deduplication check and decide whether to send notification
  defp check_deduplication_and_decide(kill_id) do
    case check_deduplication(:kill, kill_id) do
      {:ok, :send} ->
        # Not a duplicate, allow sending
        true

      {:ok, :skip} ->
        # Duplicate, skip notification
        AppLogger.processor_debug("Skipping duplicate kill notification",
          kill_id: kill_id,
          reason: "Duplicate notification"
        )

        false

      {:error, reason} ->
        # Error during deduplication check - default to allowing
        AppLogger.processor_warn(
          "Deduplication check failed, allowing notification by default",
          kill_id: kill_id,
          error: inspect(reason)
        )

        true
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
    # If system notifications are disabled but kill notifications are enabled,
    # we still want to check if the system is tracked for kill notification purposes
    if !Features.system_notifications_enabled?() &&
         !Features.kill_notifications_enabled?() do
      # System notifications disabled and kill notifications are also disabled, so nothing is tracked
      false
    else
      # Convert system_id to string for consistent comparison
      system_id_str = to_string(system_id)

      # Get system information for logging
      system_info = format_system_info(system_id)

      # Check if system is tracked through direct tracking or track_all policy
      tracked = directly_tracked?(system_id_str) || tracked_via_track_all?(system_id_str)

      # Use batch logger for system tracking checks
      WandererNotifier.Logger.BatchLogger.count_event(:system_tracked, %{
        system_id: system_id_str,
        tracked: tracked
      })

      # Only log detailed info if system is tracked
      if tracked do
        log_tracking_status(tracked, system_info, system_id_str)
      end

      tracked
    end
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
    # Check if system exists in main cache and K-Space tracking is enabled
    system_cache_key = "map:system:#{system_id_str}"
    exists_in_cache = WandererNotifier.Data.Cache.Repository.get(system_cache_key) != nil
    Features.track_kspace_systems?() && exists_in_cache
  end

  defp log_tracking_status(tracked, system_info, system_id_str) do
    # We're going to make system tracking logs extremely minimal
    # Only log notable events (system is tracked) at debug level
    # Tracking failures are too common to log each one

    if tracked do
      # Log basic tracking at debug level
      tracking_method =
        if directly_tracked?(system_id_str) do
          "explicit tracking"
        else
          "ENABLE_TRACK_KSPACE_SYSTEMS setting"
        end

      AppLogger.processor_debug("System is tracked via #{tracking_method}",
        system_info: system_info,
        system_id: system_id_str
      )
    end

    # We no longer log when a system is NOT tracked, as this happens for most systems
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
    # If character notifications are disabled but kill notifications are enabled,
    # we still want to check for tracked characters for kill notification purposes
    if !Features.character_notifications_enabled?() &&
         !Features.kill_notifications_enabled?() do
      # Character notifications disabled and kill notifications are also disabled, nothing is tracked
      false
    else
      # Handle different killmail formats
      kill_data = extract_kill_data(killmail)
      kill_id = extract_kill_id(killmail)

      # Use batch logger for character tracking checks
      WandererNotifier.Logger.BatchLogger.count_event(:character_tracked, %{
        kill_id: kill_id
      })

      # Get all tracked character IDs for comparison
      all_character_ids = get_all_tracked_character_ids()

      # For debugging, log sample character IDs (but less frequently)
      if :rand.uniform(10) == 1 do
        log_sample_character_ids(all_character_ids)
      end

      # Check if victim is tracked
      victim_tracked = check_victim_tracked(kill_data, kill_id, all_character_ids)

      if victim_tracked do
        # Early return if victim is tracked
        AppLogger.processor_info("Found tracked victim", kill_id: kill_id)
        true
      else
        # Check if any attacker is tracked
        check_attackers_tracked(kill_data, kill_id, all_character_ids)
      end
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
      # Use character_id for consistency
      character_id = Map.get(char, "character_id") || Map.get(char, :character_id)
      if character_id, do: to_string(character_id), else: nil
    end)
    |> Enum.reject(&is_nil/1)
  end

  # Log a sample of character IDs for debugging - reduced to debug level
  defp log_sample_character_ids(all_character_ids) do
    # Only log this at debug level - it happens on every kill
    sample_character_ids = Enum.take(all_character_ids, min(3, length(all_character_ids)))

    AppLogger.processor_debug("Character tracking details",
      character_count: length(all_character_ids),
      sample_characters: sample_character_ids
    )
  end

  # Extract victim ID from kill data
  defp extract_victim_id(kill_data) do
    victim = Map.get(kill_data, "victim") || Map.get(kill_data, :victim) || %{}
    victim_id = Map.get(victim, "character_id") || Map.get(victim, :character_id)
    if victim_id, do: to_string(victim_id), else: nil
  end

  # Victim tracking logs removed - these are too verbose
  # and happen on every kill
  defp log_victim_info(_victim_id_str, _kill_id) do
    # No longer logging victim info - too verbose
    :ok
  end

  # Check if victim is tracked through direct cache lookup
  defp check_direct_victim_tracking(victim_id_str) do
    direct_cache_key = "tracked:character:#{victim_id_str}"
    direct_tracked = WandererNotifier.Data.Cache.Repository.get(direct_cache_key) != nil

    if direct_tracked do
      # Keep this info log as it indicates a successful tracking match - useful information
      AppLogger.processor_info("Victim found via direct cache lookup",
        victim_id: victim_id_str,
        cache_key: direct_cache_key
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

    # Check if victim is tracked against character_id list
    victim_tracked = victim_id_str && Enum.member?(all_character_ids, victim_id_str)

    # Also try direct cache lookup for victim if not already tracked
    if !victim_tracked && victim_id_str do
      check_direct_victim_tracking(victim_id_str)
    else
      victim_tracked
    end
  end

  # Extract attackers from kill data
  defp extract_attackers(kill_data) do
    Map.get(kill_data, "attackers") || Map.get(kill_data, :attackers) || []
  end

  # Check if any attacker is tracked
  defp check_attackers_tracked(kill_data, kill_id, all_character_ids) do
    # Get attacker data
    attackers = extract_attackers(kill_data)

    # First check, is any attacker in the list of tracked character IDs
    tracked_attackers =
      attackers
      |> Enum.map(fn attacker ->
        attacker_id = Map.get(attacker, "character_id") || Map.get(attacker, :character_id)
        if attacker_id, do: to_string(attacker_id), else: nil
      end)
      |> Enum.reject(&is_nil/1)
      |> Enum.filter(fn attacker_id -> Enum.member?(all_character_ids, attacker_id) end)

    # Check if we found any tracked attackers by ID list
    has_tracked_attackers = length(tracked_attackers) > 0

    if has_tracked_attackers do
      AppLogger.processor_info("Found tracked attackers",
        kill_id: kill_id,
        tracked_attackers: tracked_attackers
      )

      true
    else
      # Second check, try direct cache lookup for each attacker
      check_direct_attacker_tracking(attackers, kill_id)
    end
  end

  # Check if any attacker is tracked through direct cache lookup
  defp check_direct_attacker_tracking(attackers, kill_id) do
    # Extract attacker IDs
    attacker_ids =
      attackers
      |> Enum.map(fn attacker ->
        attacker_id = Map.get(attacker, "character_id") || Map.get(attacker, :character_id)
        if attacker_id, do: to_string(attacker_id), else: nil
      end)
      |> Enum.reject(&is_nil/1)

    # Check each attacker ID in the cache
    Enum.find_value(attacker_ids, false, fn attacker_id ->
      cache_key = "tracked:character:#{attacker_id}"
      tracked = WandererNotifier.Data.Cache.Repository.get(cache_key) != nil

      if tracked do
        AppLogger.processor_info("Found tracked attacker via direct cache lookup",
          kill_id: kill_id,
          attacker_id: attacker_id,
          cache_key: cache_key
        )

        true
      else
        false
      end
    end)
  end

  # Extract system ID from killmail
  defp extract_system_id(killmail) do
    cond do
      is_binary(killmail) ->
        killmail

      is_map(killmail) ->
        system_id =
          Map.get(killmail, "solar_system_id") ||
            get_in(killmail, ["esi_data", "solar_system_id"])

        system_name =
          Map.get(killmail, "solar_system_name") ||
            get_in(killmail, ["esi_data", "solar_system_name"])

        # Return system_id, but log it with the name if available
        AppLogger.processor_debug("Extracted system",
          system_id: system_id,
          system_name: system_name
        )

        system_id

      true ->
        nil
    end
  end

  # Try to get system name from ESI cache
  defp get_system_name(nil), do: nil

  defp get_system_name(system_id) do
    case WandererNotifier.Api.ESI.Service.get_system_info(system_id) do
      {:ok, system_info} -> Map.get(system_info, "name")
      _ -> nil
    end
  end

  @doc """
  Checks if a notification should be sent after deduplication.
  This is used to prevent duplicate notifications for the same event.

  ## Parameters
    - notification_type: The type of notification (:kill, :system, :character, etc.)
    - identifier: Unique identifier for the notification (such as kill_id)

  ## Returns
    - {:ok, :send} if notification should be sent
    - {:ok, :skip} if notification should be skipped (duplicate)
    - {:error, reason} if an error occurs
  """
  def check_deduplication(notification_type, identifier) do
    # Use the DeduplicationHelper to check if this is a duplicate
    case DeduplicationHelper.duplicate?(notification_type, identifier) do
      {:ok, false} ->
        # Not a duplicate, mark as processed and allow sending
        DeduplicationHelper.mark_as_processed(notification_type, identifier)
        {:ok, :send}

      {:ok, true} ->
        # Duplicate, skip notification
        {:ok, :skip}

      # Handle the direct boolean value returned from duplicate? function
      false ->
        # Not a duplicate, mark as processed and allow sending
        DeduplicationHelper.mark_as_processed(notification_type, identifier)
        {:ok, :send}

      true ->
        # Duplicate, skip notification
        {:ok, :skip}

      {:error, reason} ->
        # Error during deduplication check
        AppLogger.processor_error("Deduplication check failed",
          notification_type: notification_type,
          identifier: identifier,
          error: inspect(reason)
        )

        {:error, reason}
    end
  end

  @doc """
  Determines if a system notification should be sent.
  Checks if system notifications are enabled and applies deduplication.

  ## Parameters
    - system_id: The system ID to check

  ## Returns
    - true if notification should be sent
    - false otherwise
  """
  def should_notify_system?(system_id) do
    # Check if system notifications are enabled globally
    if Features.system_notifications_enabled?() do
      # Log the check
      system_id_str = if system_id, do: to_string(system_id), else: "nil"

      AppLogger.processor_debug("Checking if system notification should be sent",
        system_id: system_id_str
      )

      # Apply deduplication check
      case check_deduplication(:system, system_id || "new") do
        {:ok, :send} -> true
        {:ok, :skip} -> false
        # Default to allowing on error
        {:error, _reason} -> true
      end
    else
      # System notifications disabled
      AppLogger.processor_debug("System notifications disabled")
      false
    end
  end

  @doc """
  Determines if a character notification should be sent.
  Checks if character notifications are enabled and applies deduplication.

  ## Parameters
    - character_id: The character ID to check

  ## Returns
    - true if notification should be sent
    - false otherwise
  """
  def should_notify_character?(character_id) do
    # Check if character notifications are enabled globally
    if Features.character_notifications_enabled?() do
      # Log the check
      character_id_str = if character_id, do: to_string(character_id), else: "nil"

      AppLogger.processor_debug("Checking if character notification should be sent",
        character_id: character_id_str
      )

      # Apply deduplication check
      case check_deduplication(:character, character_id || "new") do
        {:ok, :send} -> true
        {:ok, :skip} -> false
        # Default to allowing on error
        {:error, _reason} -> true
      end
    else
      # Character notifications disabled
      AppLogger.processor_debug("Character notifications disabled")
      false
    end
  end

end
