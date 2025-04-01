defmodule WandererNotifier.Notifications.Determiner.Kill do
  @moduledoc """
  Determines whether kill notifications should be sent.
  Handles all kill-related notification decision logic.
  """

  require Logger
  alias WandererNotifier.Config.Features
  alias WandererNotifier.Data.Cache.Keys, as: CacheKeys
  alias WandererNotifier.Data.Cache.Repository, as: CacheRepo
  alias WandererNotifier.Data.Killmail
  alias WandererNotifier.Helpers.DeduplicationHelper
  alias WandererNotifier.Logger.Logger, as: AppLogger
  alias WandererNotifier.Logger.Logger.BatchLogger

  @doc """
  Determines if a notification should be sent for a kill.

  ## Parameters
    - killmail: The killmail to check

  ## Returns
    - true if a notification should be sent
    - false otherwise
  """
  def should_notify?(killmail) do
    # Extract basic information about the killmail for logging
    kill_id = get_kill_id(killmail)

    # Log the start of notification determination
    AppLogger.processor_info("[Determiner] Starting kill notification determination",
      kill_id: kill_id,
      notifications_enabled: Features.kill_notifications_enabled?()
    )

    # Check if kill notifications are enabled
    if Features.kill_notifications_enabled?() do
      # Extract basic information about the killmail
      kill_details = extract_kill_notification_details(killmail)

      # Log extracted details
      AppLogger.processor_debug("[Determiner] Extracted kill details",
        kill_id: kill_details.kill_id,
        system_id: kill_details.system_id,
        system_name: kill_details.system_name,
        is_tracked_system: kill_details.is_tracked_system,
        has_tracked_character: kill_details.has_tracked_character
      )

      # Check if kill meets tracking criteria (system or character tracked)
      meets_tracking_criteria =
        kill_details.is_tracked_system || kill_details.has_tracked_character

      if meets_tracking_criteria do
        # Kill meets tracking criteria, check deduplication
        AppLogger.processor_info("[Determiner] Kill meets tracking criteria",
          kill_id: kill_details.kill_id,
          tracked_system: kill_details.is_tracked_system,
          tracked_character: kill_details.has_tracked_character
        )

        result = check_deduplication_and_decide(kill_details.kill_id)

        # Log the final decision
        AppLogger.processor_info("[Determiner] Kill notification decision",
          kill_id: kill_details.kill_id,
          should_notify: result,
          reason: "Passed tracking and deduplication checks"
        )

        result
      else
        # Log why we're skipping this kill
        AppLogger.processor_info("[Determiner] Skipping kill notification",
          kill_id: kill_details.kill_id,
          reason: "Does not meet tracking criteria",
          tracked_system: kill_details.is_tracked_system,
          tracked_character: kill_details.has_tracked_character
        )

        false
      end
    else
      # Log that notifications are disabled
      AppLogger.processor_info("[Determiner] Skipping kill notification",
        kill_id: kill_id,
        reason: "Kill notifications are disabled"
      )

      false
    end
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
  Checks if a system is being tracked.

  ## Parameters
    - system_id: The ID of the system to check

  ## Returns
    - true if the system is tracked
    - false otherwise
  """
  def tracked_system?(system_id) when is_integer(system_id) do
    system_id_str = Integer.to_string(system_id)
    tracked_system?(system_id_str)
  end

  def tracked_system?(system_id_str) when is_binary(system_id_str) do
    AppLogger.processor_debug("[Determiner] Checking if system #{system_id_str} is tracked")

    # First check if we have a direct tracking entry for the system
    cache_key = CacheKeys.tracked_system(system_id_str)
    cache_value = CacheRepo.get(cache_key)

    # Log the cache check
    AppLogger.processor_debug("[Determiner] Tracked system cache check",
      system_id: system_id_str,
      value: inspect(cache_value)
    )

    # Get the system details from cache too
    system_cache_key = CacheKeys.system(system_id_str)
    system_in_cache = CacheRepo.get(system_cache_key)

    AppLogger.processor_debug("[Determiner] System cache check",
      system_id: system_id_str,
      system: inspect(system_in_cache)
    )

    # Return tracking status with detailed logging
    tracked = cache_value != nil

    AppLogger.processor_debug("[Determiner] System tracking check result",
      system_id: system_id_str,
      tracked: tracked,
      system_cache_key: system_cache_key,
      system_in_cache: system_in_cache != nil
    )

    tracked
  end

  def tracked_system?(_), do: false

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

  # Helper to extract kill_id regardless of struct type
  defp extract_kill_id(kill) do
    cond do
      is_struct(kill, WandererNotifier.Data.Killmail) -> kill.killmail_id
      is_struct(kill, WandererNotifier.Resources.Killmail) -> kill.killmail_id
      is_map(kill) -> Map.get(kill, "killmail_id") || Map.get(kill, :killmail_id)
      true -> nil
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

  # Get all tracked character IDs
  defp get_all_tracked_character_ids do
    all_characters = CacheRepo.get("map:characters") || []

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
    direct_cache_key = CacheKeys.tracked_character(victim_id_str)
    CacheRepo.get(direct_cache_key) != nil
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

  # Apply deduplication check and decide whether to send notification
  defp check_deduplication_and_decide(kill_id) do
    AppLogger.processor_debug("[Determiner] Checking deduplication for kill",
      kill_id: kill_id
    )

    case DeduplicationHelper.duplicate?(:kill, kill_id) do
      {:ok, :new} ->
        # Not a duplicate, allow sending
        AppLogger.processor_info("[Determiner] Kill is not a duplicate",
          kill_id: kill_id,
          decision: :allow
        )

        true

      {:ok, :duplicate} ->
        # Duplicate, skip notification
        AppLogger.processor_info("[Determiner] Kill is a duplicate",
          kill_id: kill_id,
          decision: :skip
        )

        false

      {:error, reason} ->
        # Error during deduplication check - default to allowing
        AppLogger.processor_warn(
          "[Determiner] Deduplication check failed, allowing notification by default",
          kill_id: kill_id,
          error: inspect(reason),
          decision: :allow_with_error
        )

        true
    end
  end
end
