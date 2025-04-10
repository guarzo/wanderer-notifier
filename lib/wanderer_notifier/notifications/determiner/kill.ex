defmodule WandererNotifier.Notifications.Determiner.Kill do
  @moduledoc """
  Determines whether kill notifications should be sent.
  Handles all kill-related notification decision logic.
  """

  alias WandererNotifier.Config.Features
  alias WandererNotifier.Data.Cache.Keys, as: CacheKeys
  alias WandererNotifier.Data.Cache.Repository, as: CacheRepo
  alias WandererNotifier.Helpers.DeduplicationHelper
  alias WandererNotifier.KillmailProcessing.Extractor
  require Logger

  @doc """
  Determines if a notification should be sent for a kill.

  ## Parameters
    - killmail: The killmail to check

  ## Returns
    - {:ok, %{should_notify: boolean(), reason: String.t()}} with tracking information
  """
  def should_notify?(killmail) do
    # First check if killmail is valid and has minimal required data
    if is_nil(killmail) or not is_map(killmail) do
      Logger.warning(
        "DETERMINER: Invalid killmail format: #{if(is_nil(killmail), do: "nil", else: inspect(killmail))}"
      )

      return_no_notification("Invalid killmail format")
    else
      process_killmail(killmail)
    end
  end

  # Process a valid killmail to determine notification status
  defp process_killmail(killmail) do
    # Extract and log basic killmail information
    {kill_id, system_id_str, _victim_info} = extract_killmail_info(killmail)

    # Run through notification checks with the "with" pipeline
    notification_result = run_notification_checks(kill_id, system_id_str, killmail)

    # Log the final notification decision
    log_notification_decision(kill_id, notification_result)

    # Return the notification result
    notification_result
  rescue
    e ->
      Logger.warning("DETERMINER: Exception processing killmail: #{Exception.message(e)}")
      return_no_notification("Error processing killmail")
  end

  # Extract basic information from the killmail for logging
  defp extract_killmail_info(killmail) do
    kill_id = Extractor.get_killmail_id(killmail) || "unknown"
    system_id = Extractor.get_system_id(killmail)
    system_id_str = if is_nil(system_id), do: "unknown", else: to_string(system_id)

    # Get victim info using Extractor
    victim = Extractor.get_victim(killmail) || %{}
    victim_id = Map.get(victim, "character_id")
    victim_name = Map.get(victim, "character_name") || "Unknown Pilot"

    # Log basic information about the killmail
    Logger.debug(
      "DETERMINER: Kill ##{kill_id} - Checking if #{victim_name} (ID: #{victim_id || "unknown"}) in system #{system_id_str} should trigger notification"
    )

    {kill_id, system_id_str, {victim_id, victim_name}}
  end

  # Run the notification checks pipeline
  defp run_notification_checks(kill_id, system_id_str, killmail) do
    with true <- check_notifications_enabled(kill_id),
         true <- check_tracking(system_id_str, killmail) do
      check_deduplication_and_decide(kill_id)
    else
      {:notifications_disabled, reason} ->
        Logger.debug("DETERMINER: Kill ##{kill_id} - Notifications disabled: #{reason}")
        return_no_notification("Notifications disabled: #{reason}")

      {:not_tracked, details} ->
        Logger.debug("DETERMINER: Kill ##{kill_id} - Not tracked: #{details}")
        return_no_notification("Not tracked by any character or system (#{details})")
    end
  end

  # Log the notification decision
  defp log_notification_decision(kill_id, result) do
    case result do
      {:ok, %{should_notify: true}} ->
        Logger.debug("DETERMINER: Kill ##{kill_id} - WILL send notification")

      {:ok, %{should_notify: false, reason: reason}} ->
        Logger.debug("DETERMINER: Kill ##{kill_id} - Will NOT send notification: #{reason}")

      _ ->
        Logger.debug("DETERMINER: Kill ##{kill_id} - Unexpected result: #{inspect(result)}")
    end
  end

  # Helper to create standard "no notification" response
  defp return_no_notification(reason) do
    {:ok, %{should_notify: false, reason: reason}}
  end

  defp check_notifications_enabled(_kill_id) do
    notifications_enabled = Features.notifications_enabled?()
    system_notifications_enabled = Features.system_notifications_enabled?()

    cond do
      !notifications_enabled ->
        {:notifications_disabled, "global notifications disabled"}

      !system_notifications_enabled ->
        {:notifications_disabled, "system notifications disabled"}

      true ->
        true
    end
  end

  defp check_tracking(system_id, killmail) do
    kill_id = Extractor.get_killmail_id(killmail) || "unknown"
    is_tracked_system = tracked_system?(system_id)
    has_tracked_char = has_tracked_character?(killmail)

    # Get victim info for better logging
    victim = Extractor.get_victim(killmail) || %{}
    victim_id = Map.get(victim, "character_id")

    # Enhanced logging for debugging
    Logger.debug(
      "DETERMINER: Kill ##{kill_id} - System tracked: #{is_tracked_system}, Character tracked: #{has_tracked_char}"
    )

    # For notifications, we consider both tracked systems and tracked characters
    if is_tracked_system || has_tracked_char do
      true
    else
      details =
        if is_nil(victim_id),
          do: "missing victim ID",
          else: "victim ID #{victim_id}, system ID #{system_id}"

      {:not_tracked, details}
    end
  end

  defp check_deduplication_and_decide(kill_id) do
    case DeduplicationHelper.duplicate?(:kill, kill_id) do
      {:ok, :new} -> {:ok, %{should_notify: true, reason: nil}}
      {:ok, :duplicate} -> {:ok, %{should_notify: false, reason: "Duplicate kill"}}
      {:error, _reason} -> {:ok, %{should_notify: true, reason: nil}}
    end
  end

  @doc """
  Gets the system ID from a kill as a string.
  Converts the numeric ID from Extractor to a string format, or returns "unknown".
  """
  def get_kill_system_id(kill) do
    system_id = Extractor.get_system_id(kill)
    if is_nil(system_id), do: "unknown", else: to_string(system_id)
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
    cache_key = CacheKeys.tracked_system(system_id_str)
    CacheRepo.get(cache_key) != nil
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
    kill_data = extract_kill_data(killmail)
    kill_id = Extractor.get_killmail_id(killmail) || "unknown"

    # Get all tracked characters for comparison
    all_character_ids = get_all_tracked_character_ids()

    # Get victim info for better logs
    victim = Map.get(kill_data, "victim") || %{}
    victim_id = Map.get(victim, "character_id")
    victim_name = Map.get(victim, "character_name") || "Unknown Pilot"

    # Log details about our tracked characters
    Logger.debug(
      "DETERMINER: Kill ##{kill_id} - Checking if victim #{victim_name} (ID: #{victim_id || "unknown"}) is tracked"
    )

    Logger.debug(
      "DETERMINER: Kill ##{kill_id} - We have #{length(all_character_ids)} tracked characters"
    )

    # DEBUG: Add detailed structure logs
    Logger.debug("DETERMINER: Kill ##{kill_id} - Victim data: #{inspect(victim)}")

    Logger.debug(
      "DETERMINER: Kill ##{kill_id} - Kill data structure type: #{killmail.__struct__}"
    )

    Logger.debug("DETERMINER: Kill ##{kill_id} - Kill data keys: #{inspect(Map.keys(killmail))}")

    # Check attackers too
    attackers = Map.get(kill_data, "attackers") || []
    Logger.debug("DETERMINER: Kill ##{kill_id} - Found #{length(attackers)} attackers")

    # Check a sample of attackers
    if length(attackers) > 0 do
      sample = Enum.take(attackers, min(3, length(attackers)))
      Logger.debug("DETERMINER: Kill ##{kill_id} - Sample attackers: #{inspect(sample)}")
    end

    if length(all_character_ids) > 0 do
      # Log a sample of tracked characters for debugging
      sample = Enum.take(all_character_ids, min(5, length(all_character_ids)))
      Logger.debug("DETERMINER: Kill ##{kill_id} - Sample of tracked IDs: #{inspect(sample)}")
    end

    # Check if victim is tracked
    victim_tracked = check_victim_tracked(kill_data, all_character_ids)

    if victim_tracked do
      Logger.debug("DETERMINER: Kill ##{kill_id} - Victim #{victim_name} IS tracked")
      true
    else
      Logger.debug(
        "DETERMINER: Kill ##{kill_id} - Victim #{victim_name} is NOT tracked, checking attackers"
      )

      attacker_tracked = check_attackers_tracked(kill_data, all_character_ids)

      if attacker_tracked do
        Logger.debug("DETERMINER: Kill ##{kill_id} - An attacker IS tracked")
      else
        Logger.debug("DETERMINER: Kill ##{kill_id} - No tracked characters found")
      end

      attacker_tracked
    end
  end

  # Extract kill data to get useful information
  defp extract_kill_data(killmail) do
    # DEBUG: Log what we're extracting
    kill_id = Extractor.get_killmail_id(killmail) || "unknown"
    victim = Extractor.get_victim(killmail)
    attackers = Extractor.get_attackers(killmail)
    system_id = Extractor.get_system_id(killmail)

    Logger.debug("DETERMINER: Kill ##{kill_id} - Extracting kill data")
    Logger.debug("DETERMINER: Kill ##{kill_id} - Victim extraction: #{inspect(victim)}")
    Logger.debug("DETERMINER: Kill ##{kill_id} - Got #{length(attackers || [])} attackers")
    Logger.debug("DETERMINER: Kill ##{kill_id} - System ID: #{system_id || "unknown"}")

    %{
      "solar_system_id" => system_id,
      "solar_system_name" => Extractor.get_system_name(killmail),
      "victim" => victim,
      "attackers" => attackers
    }
  end

  # Get all tracked character IDs
  defp get_all_tracked_character_ids do
    all_characters = CacheRepo.get(CacheKeys.character_list()) || []

    Enum.map(all_characters, fn char ->
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
  defp check_victim_tracked(kill_data, all_character_ids) do
    victim_id_str = extract_victim_id(kill_data)

    # Get victim info for better logging
    victim = Map.get(kill_data, "victim") || %{}
    victim_name = Map.get(victim, "character_name") || "Unknown Pilot"

    victim_tracked = victim_id_str && Enum.member?(all_character_ids, victim_id_str)

    if victim_tracked do
      Logger.debug(
        "DETERMINER: Victim #{victim_name} (ID: #{victim_id_str}) is in tracked character list"
      )

      true
    else
      # Try direct tracking if not found in the list
      direct_tracked = victim_id_str && check_direct_victim_tracking(victim_id_str)

      if direct_tracked do
        Logger.debug(
          "DETERMINER: Victim #{victim_name} (ID: #{victim_id_str}) is directly tracked"
        )
      else
        Logger.debug(
          "DETERMINER: Victim #{victim_name} (ID: #{victim_id_str || "unknown"}) is not tracked"
        )
      end

      direct_tracked
    end
  end

  # Extract attackers from kill data
  defp extract_attackers(kill_data) do
    Map.get(kill_data, "attackers") || Map.get(kill_data, :attackers) || []
  end

  # Check if any attacker is tracked
  defp check_attackers_tracked(kill_data, all_character_ids) do
    attackers = extract_attackers(kill_data)

    if attacker_in_tracked_list?(attackers, all_character_ids) do
      true
    else
      attacker_directly_tracked?(attackers)
    end
  end

  # Check if any attacker is in our tracked characters list
  defp attacker_in_tracked_list?(attackers, all_character_ids) do
    # DEBUG: Log attackers being checked
    attacker_ids =
      attackers
      |> Enum.map(&extract_attacker_id/1)
      |> Enum.reject(&is_nil/1)

    Logger.debug(
      "DETERMINER: Checking #{length(attacker_ids)} attacker IDs against #{length(all_character_ids)} tracked IDs"
    )

    if length(attacker_ids) > 0 do
      Logger.debug("DETERMINER: Attacker IDs: #{inspect(attacker_ids)}")
    end

    # Check if any attacker is in the tracked list
    Enum.any?(attacker_ids, fn attacker_id ->
      is_tracked = Enum.member?(all_character_ids, attacker_id)

      if is_tracked do
        Logger.debug("DETERMINER: Attacker with ID #{attacker_id} IS in tracked list")
      end

      is_tracked
    end)
  end

  # Extract attacker ID from attacker data
  defp extract_attacker_id(attacker) when is_map(attacker) do
    attacker_id = Map.get(attacker, "character_id") || Map.get(attacker, :character_id)
    if attacker_id, do: to_string(attacker_id), else: nil
  end

  # Handle non-map attackers safely
  defp extract_attacker_id(_), do: nil

  # Check if any attacker is directly tracked - handle possible nil values safely
  defp attacker_directly_tracked?(attackers) when is_list(attackers) do
    attackers
    |> Enum.map(&extract_attacker_id/1)
    |> Enum.reject(&is_nil/1)
    |> Enum.any?(&check_direct_victim_tracking/1)
  end

  # Handle non-list attackers safely
  defp attacker_directly_tracked?(_), do: false

  @doc """
  Determines if a kill is in a tracked system.

  ## Parameters
    - killmail: The killmail to check

  ## Returns
    - true if the kill happened in a tracked system
    - false otherwise
  """
  def tracked_in_system?(killmail) do
    system_id = Extractor.get_system_id(killmail)
    system_id_str = if is_nil(system_id), do: "unknown", else: to_string(system_id)
    tracked_system?(system_id_str)
  end

  @doc """
  Gets the list of tracked characters involved in a kill.

  ## Parameters
    - killmail: The killmail to check

  ## Returns
    - List of tracked character IDs involved in the kill
  """
  def get_tracked_characters(killmail) do
    # Extract all character IDs from the killmail
    all_character_ids = extract_all_character_ids(killmail)

    # Filter to only include tracked characters
    Enum.filter(all_character_ids, fn char_id -> tracked_character?(char_id) end)
  end

  @doc """
  Determines if tracked characters are victims in a kill.

  ## Parameters
    - killmail: The killmail to check
    - tracked_characters: List of tracked character IDs

  ## Returns
    - true if any tracked character is a victim
    - false if all tracked characters are attackers
  """
  def are_tracked_characters_victims?(killmail, tracked_characters) do
    # Get the victim character ID
    victim_character_id = get_victim_character_id(killmail)

    # Check if any tracked character is the victim
    Enum.member?(tracked_characters, victim_character_id)
  end

  # Helper function to extract all character IDs from a killmail
  defp extract_all_character_ids(killmail) do
    # Get victim character ID
    victim_id = get_victim_character_id(killmail)
    victim_ids = if victim_id, do: [victim_id], else: []

    # Get attacker character IDs
    attacker_ids = get_attacker_character_ids(killmail)

    # Combine and remove duplicates
    (victim_ids ++ attacker_ids) |> Enum.uniq()
  end

  # Helper function to get the victim character ID
  defp get_victim_character_id(killmail) when is_nil(killmail), do: nil

  defp get_victim_character_id(killmail) do
    victim = Extractor.get_victim(killmail)
    Map.get(victim, "character_id")
  end

  # Helper function to get attacker character IDs
  defp get_attacker_character_ids(killmail) do
    attackers = Extractor.get_attackers(killmail)

    Enum.map(attackers, fn attacker ->
      Map.get(attacker, "character_id")
    end)
    |> Enum.filter(fn id -> not is_nil(id) end)
  end

  @doc """
  Checks if a character is being tracked.

  ## Parameters
    - character_id: The ID of the character to check

  ## Returns
    - true if the character is tracked
    - false otherwise
  """
  def tracked_character?(character_id) when is_integer(character_id) do
    character_id_str = Integer.to_string(character_id)
    tracked_character?(character_id_str)
  end

  def tracked_character?(character_id_str) when is_binary(character_id_str) do
    cache_key = CacheKeys.tracked_character(character_id_str)
    CacheRepo.get(cache_key) != nil
  end

  def tracked_character?(_), do: false
end
