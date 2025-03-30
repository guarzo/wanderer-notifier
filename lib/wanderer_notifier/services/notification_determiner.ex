defmodule WandererNotifier.Services.NotificationDeterminer do
  @moduledoc """
  Central module for determining whether notifications should be sent based on tracking criteria.
  This module handles the logic for deciding if a kill, system, or character event should trigger
  a notification based on configured tracking rules.
  """
  require Logger
  alias WandererNotifier.Api.ESI.Service, as: ESIService
  alias WandererNotifier.Config.Features
  alias WandererNotifier.Data.Cache.Repository, as: CacheRepository
  alias WandererNotifier.Data.Killmail
  alias WandererNotifier.Helpers.CacheHelpers
  alias WandererNotifier.Helpers.DeduplicationHelper
  alias WandererNotifier.Logger, as: AppLogger
  alias WandererNotifier.Logger.BatchLogger

  @doc """
  Determines if a notification should be sent for a kill.

  ## Parameters
    - killmail: The killmail to check

  ## Returns
    - true if a notification should be sent
    - false otherwise
  """
  def should_send_kill_notification?(killmail) do
    # Only continue if kill notifications are enabled
    if !Features.kill_notifications_enabled?() do
      # Skip notification if kill notifications are disabled
      return(false)
    end

    # Extract basic information about the killmail
    kill_details = extract_kill_notification_details(killmail)

    # Log kill tracking status
    log_kill_tracking_status(kill_details)

    # Check if kill meets tracking criteria (system or character tracked)
    meets_tracking_criteria = kill_details.is_tracked_system || kill_details.has_tracked_character

    if !meets_tracking_criteria do
      # Kill does not meet tracking criteria
      log_kill_not_qualifying(kill_details)
      return(false)
    end

    # Kill meets tracking criteria, check deduplication
    should_send = check_deduplication_and_decide(kill_details.kill_id)

    # Log final decision
    log_kill_notification_decision(kill_details, should_send)

    should_send
  end

  # Extract all details needed for kill notification determination
  defp extract_kill_notification_details(killmail) do
    kill_id = get_kill_id(killmail)
    system_id = get_kill_system_id(killmail)
    system_name = get_kill_system_name(killmail)
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

  # Log kill tracking status to give context for notification decision
  defp log_kill_tracking_status(kill_details) do
    AppLogger.kill_info(
      "🔍 KILL TRACKING STATUS: Kill #{kill_details.kill_id} in system #{kill_details.system_id} (#{kill_details.system_name}): system_tracked=#{kill_details.is_tracked_system}, character_tracked=#{kill_details.has_tracked_character}",
      %{
        kill_id: kill_details.kill_id,
        system_id: kill_details.system_id,
        system_name: kill_details.system_name,
        system_tracked: kill_details.is_tracked_system,
        character_tracked: kill_details.has_tracked_character
      }
    )
  end

  # Log when a kill does not qualify for notifications
  defp log_kill_not_qualifying(kill_details) do
    AppLogger.kill_info(
      "❌ NOTIFICATION DECISION: Kill #{kill_details.kill_id} in system #{kill_details.system_id} (#{kill_details.system_name}) - not sending notification",
      %{
        kill_id: kill_details.kill_id,
        system_id: kill_details.system_id,
        system_name: kill_details.system_name,
        reason: "Does not meet tracking criteria"
      }
    )
  end

  # Log final notification decision
  defp log_kill_notification_decision(kill_details, should_send) do
    if should_send do
      AppLogger.kill_info(
        "✅ NOTIFICATION DECISION: Kill #{kill_details.kill_id} in system #{kill_details.system_id} (#{kill_details.system_name}) - sending notification",
        %{
          kill_id: kill_details.kill_id,
          system_id: kill_details.system_id,
          system_name: kill_details.system_name,
          reason: "Tracked system or character"
        }
      )
    else
      AppLogger.kill_info(
        "❌ NOTIFICATION DECISION: Kill #{kill_details.kill_id} in system #{kill_details.system_id} (#{kill_details.system_name}) - not sending notification",
        %{
          kill_id: kill_details.kill_id,
          system_id: kill_details.system_id,
          system_name: kill_details.system_name,
          reason: "Duplicate notification"
        }
      )
    end
  end

  # Get kill ID from killmail
  defp get_kill_id(killmail) do
    case killmail do
      %Killmail{killmail_id: id} when not is_nil(id) -> id
      %{killmail_id: id} when not is_nil(id) -> id
      %{"killmail_id" => id} when not is_nil(id) -> id
      _ -> "unknown"
    end
  end

  # Get system ID from killmail
  defp get_kill_system_id(killmail) do
    case killmail do
      %Killmail{esi_data: %{"solar_system_id" => id}} when not is_nil(id) -> id
      %{esi_data: %{"solar_system_id" => id}} when not is_nil(id) -> id
      %{"esi_data" => %{"solar_system_id" => id}} when not is_nil(id) -> id
      %{solar_system_id: id} when not is_nil(id) -> id
      %{"solar_system_id" => id} when not is_nil(id) -> id
      _ -> "unknown"
    end
  end

  # Get system name from killmail
  defp get_kill_system_name(killmail) do
    case killmail do
      %Killmail{esi_data: %{"solar_system_name" => name}} when not is_nil(name) -> name
      %{esi_data: %{"solar_system_name" => name}} when not is_nil(name) -> name
      %{"esi_data" => %{"solar_system_name" => name}} when not is_nil(name) -> name
      %{solar_system_name: name} when not is_nil(name) -> name
      %{"solar_system_name" => name} when not is_nil(name) -> name
      _ -> "unknown"
    end
  end

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
    kill_notifications_enabled = Features.kill_notifications_enabled?()

    AppLogger.kill_info(
      "🔎 NOTIFICATION CHECK: Starting kill notification check, kill_notifications_enabled=#{kill_notifications_enabled}",
      %{kill_notifications_enabled: kill_notifications_enabled}
    )

    if kill_notifications_enabled do
      # Extract kill details for decision making
      kill_details = extract_kill_details(killmail, system_id)

      # Log the decision factors
      log_notification_criteria(kill_details)

      # Check if this kill should be considered for notification
      if kill_meets_tracking_criteria?(kill_details) do
        dedup_result = check_deduplication_and_decide(kill_details.kill_id)

        AppLogger.kill_info(
          "✅ NOTIFICATION DECISION: Kill #{kill_details.kill_id} in system #{kill_details.system_id} (#{kill_details.system_name}) - sending notification=#{dedup_result}",
          %{
            kill_id: kill_details.kill_id,
            system_id: kill_details.system_id,
            system_tracked: kill_details.is_tracked_system,
            character_tracked: kill_details.has_tracked_character,
            notification_sent: dedup_result
          }
        )

        dedup_result
      else
        AppLogger.kill_info(
          "❌ NOTIFICATION DECISION: Kill #{kill_details.kill_id} in system #{kill_details.system_id} (#{kill_details.system_name}) - not sending notification",
          %{
            kill_id: kill_details.kill_id,
            system_id: kill_details.system_id,
            system_tracked: kill_details.is_tracked_system,
            character_tracked: kill_details.has_tracked_character,
            reason: "Does not meet tracking criteria"
          }
        )

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

    # Check tracking criteria - call tracked_system? directly without conditions
    is_tracked_system = tracked_system?(system_id)
    has_tracked_character = has_tracked_character?(killmail)

    AppLogger.kill_info(
      "🔍 KILL TRACKING STATUS: Kill #{kill_id} in system #{system_id} (#{system_name}): system_tracked=#{is_tracked_system}, character_tracked=#{has_tracked_character}",
      %{
        kill_id: kill_id,
        system_id: system_id,
        system_name: system_name,
        system_tracked: is_tracked_system,
        character_tracked: has_tracked_character,
        kill_notifications_enabled: Features.kill_notifications_enabled?()
      }
    )

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
    AppLogger.processor_debug(
      "Evaluating notification criteria",
      %{
        kill_id: kill_details.kill_id,
        system_id: kill_details.system_id,
        system_name: kill_details.system_name,
        is_tracked_system: kill_details.is_tracked_system,
        has_tracked_character: kill_details.has_tracked_character
      }
    )
  end

  # Check if kill meets any tracking criteria
  defp kill_meets_tracking_criteria?(kill_details) do
    kill_details.is_tracked_system || kill_details.has_tracked_character
  end

  # Log that notifications are disabled
  defp log_notifications_disabled do
    AppLogger.processor_debug(
      "Kill notifications are disabled globally",
      %{setting: "ENABLE_KILL_NOTIFICATIONS=false"}
    )
  end

  # Log that kill is not tracked
  defp log_kill_not_tracked(kill_id) do
    AppLogger.processor_debug(
      "Kill not in tracked system or with tracked character",
      %{kill_id: kill_id}
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
        false

      {:error, reason} ->
        # Error during deduplication check - default to allowing
        AppLogger.processor_warn(
          "Deduplication check failed, allowing notification by default",
          %{
            kill_id: kill_id,
            error: inspect(reason)
          }
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
    # Convert system_id to string for consistent comparison
    system_id_str = to_string(system_id)

    # Check if system is tracked through direct tracking or track_all policy
    direct_tracked = directly_tracked?(system_id_str)
    via_track_all = tracked_via_track_all?(system_id_str)
    tracked = direct_tracked || via_track_all

    # Use batch logger for system tracking checks
    BatchLogger.count_event(:system_tracked, %{
      system_id: system_id_str,
      tracked: tracked
    })

    tracked
  end

  def tracked_system?(_), do: false

  # Helper functions for tracked_system?
  defp directly_tracked?(system_id_str) do
    cache_key = "tracked:system:#{system_id_str}"
    cache_value = CacheRepository.get(cache_key)
    cache_value != nil
  end

  defp tracked_via_track_all?(system_id_str) do
    # Check if system exists in main cache and K-Space tracking is enabled
    system_cache_key = "map:system:#{system_id_str}"
    system_in_cache = CacheRepository.get(system_cache_key)
    exists_in_cache = system_in_cache != nil
    track_kspace_enabled = Features.track_kspace_systems?()

    track_kspace_enabled && exists_in_cache
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
      BatchLogger.count_event(:character_tracked, %{
        kill_id: kill_id
      })

      # Get all tracked character IDs for comparison
      all_character_ids = get_all_tracked_character_ids()

      # Check if victim is tracked
      victim_tracked = check_victim_tracked(kill_data, kill_id, all_character_ids)

      if victim_tracked do
        # Early return if victim is tracked
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
    all_characters = CacheRepository.get("map:characters") || []

    Enum.map(all_characters, fn char ->
      # Use character_id for consistency
      character_id = Map.get(char, "character_id") || Map.get(char, :character_id)
      if character_id, do: to_string(character_id), else: nil
    end)
    |> Enum.reject(&is_nil/1)
  end

  # Extract victim ID from kill data
  defp extract_victim_id(kill_data) do
    victim = Map.get(kill_data, "victim") || Map.get(kill_data, :victim) || %{}
    victim_id = Map.get(victim, "character_id") || Map.get(victim, :character_id)
    if victim_id, do: to_string(victim_id), else: nil
  end

  # Check if victim is tracked through direct cache lookup
  defp check_direct_victim_tracking(victim_id_str) do
    direct_cache_key = "tracked:character:#{victim_id_str}"
    CacheRepository.get(direct_cache_key) != nil
  end

  # Check if the victim in this kill is being tracked
  defp check_victim_tracked(kill_data, _kill_id, all_character_ids) do
    # Extract and format victim ID
    victim_id_str = extract_victim_id(kill_data)

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
  defp check_attackers_tracked(kill_data, _kill_id, all_character_ids) do
    # Get attacker data
    attackers = extract_attackers(kill_data)

    # Check if any attacker is in our tracked list
    if attacker_in_tracked_list?(attackers, all_character_ids) do
      true
    else
      # If no attackers in tracked list, check direct cache lookup
      attacker_directly_tracked?(attackers)
    end
  end

  # Check if any attacker is in our tracked characters list
  defp attacker_in_tracked_list?(attackers, all_character_ids) do
    attackers
    |> Enum.map(&extract_attacker_id/1)
    |> Enum.reject(&is_nil/1)
    |> Enum.any?(fn attacker_id -> Enum.member?(all_character_ids, attacker_id) end)
  end

  # Extract attacker ID from attacker data
  defp extract_attacker_id(attacker) do
    attacker_id = Map.get(attacker, "character_id") || Map.get(attacker, :character_id)
    if attacker_id, do: to_string(attacker_id), else: nil
  end

  # Check if any attacker is directly tracked
  defp attacker_directly_tracked?(attackers) do
    attackers
    |> Enum.map(&extract_attacker_id/1)
    |> Enum.reject(&is_nil/1)
    |> Enum.any?(&check_direct_victim_tracking/1)
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
        AppLogger.processor_debug(
          "Extracted system",
          %{
            system_id: system_id,
            system_name: system_name
          }
        )

        system_id

      true ->
        nil
    end
  end

  # Try to get system name from ESI cache
  defp get_system_name(nil), do: nil

  defp get_system_name(system_id) do
    case ESIService.get_system_info(system_id) do
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
      {:ok, :new} ->
        # Not a duplicate, allow sending
        {:ok, :send}

      {:ok, :duplicate} ->
        # Duplicate, skip notification
        {:ok, :skip}

      {:error, reason} ->
        # Error during deduplication check
        AppLogger.processor_error(
          "Deduplication check failed",
          %{
            notification_type: notification_type,
            identifier: identifier,
            error: inspect(reason)
          }
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

      AppLogger.processor_debug(
        "Checking if system notification should be sent",
        %{system_id: system_id_str}
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

      AppLogger.processor_debug(
        "Checking if character notification should be sent",
        %{character_id: character_id_str}
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

  @doc """
  Prints the system tracking status for debugging purposes.
  """
  def print_system_tracking_status do
    # Check environment variables
    enable_track_kspace = System.get_env("ENABLE_TRACK_KSPACE_SYSTEMS")
    wanderer_feature_track_kspace = System.get_env("WANDERER_FEATURE_TRACK_KSPACE")

    # Get feature via direct config
    features_map = Application.get_env(:wanderer_notifier, :features, %{})
    direct_config = Map.get(features_map, :track_kspace_systems)

    # Get feature via Features module
    features_result = Features.track_kspace_systems?()

    # Log all results
    AppLogger.kill_info(
      "📊 SYSTEM TRACKING STATUS SUMMARY",
      %{
        enable_track_kspace: enable_track_kspace,
        wanderer_feature_track_kspace: wanderer_feature_track_kspace,
        direct_config_value: direct_config,
        features_module_result: features_result
      }
    )

    # Also check cached systems
    systems = CacheHelpers.get_tracked_systems()
    system_count = length(systems)

    AppLogger.kill_info(
      "📊 TRACKED SYSTEMS STATUS",
      %{
        tracked_system_count: system_count,
        first_few: Enum.take(systems, 3)
      }
    )
  end
end
