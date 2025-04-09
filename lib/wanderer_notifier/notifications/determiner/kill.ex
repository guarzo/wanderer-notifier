defmodule WandererNotifier.Notifications.Determiner.Kill do
  @moduledoc """
  Determines whether kill notifications should be sent.
  Handles all kill-related notification decision logic.
  """

  alias WandererNotifier.Config.Features
  alias WandererNotifier.Data.Cache.Keys, as: CacheKeys
  alias WandererNotifier.Data.Cache.Repository, as: CacheRepo
  alias WandererNotifier.Helpers.DeduplicationHelper
  alias WandererNotifier.Resources.Killmail
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
      Logger.warning("[KillDeterminer] Invalid killmail format", %{
        killmail_type: if(is_nil(killmail), do: "nil", else: inspect(killmail))
      })

      return_no_notification("Invalid killmail format")
    else
      try do
        # Extract key identifiers safely
        system_id = get_kill_system_id(killmail)
        kill_id = get_kill_id(killmail)

        Logger.debug("[KillDeterminer] Evaluating killmail", %{
          kill_id: kill_id,
          system_id: system_id,
          killmail_type: if(is_struct(killmail), do: inspect(killmail.__struct__), else: "map"),
          has_esi_data: has_esi_data?(killmail)
        })

        # Run through notification checks
        with true <- check_notifications_enabled(kill_id),
             true <- check_tracking(system_id, killmail) do
          check_deduplication_and_decide(kill_id)
        else
          false -> return_no_notification("Not tracked by any character or system")
          _ -> return_no_notification("Notifications disabled")
        end
      rescue
        e ->
          Logger.warning("[KillDeterminer] Exception determining notification status", %{
            error: Exception.message(e),
            stacktrace: Exception.format_stacktrace(__STACKTRACE__)
          })

          return_no_notification("Error processing killmail")
      end
    end
  end

  # Helper to create standard "no notification" response
  defp return_no_notification(reason) do
    {:ok, %{should_notify: false, reason: reason}}
  end

  defp check_notifications_enabled(_kill_id) do
    notifications_enabled = Features.notifications_enabled?()
    system_notifications_enabled = Features.system_notifications_enabled?()
    notifications_enabled && system_notifications_enabled
  end

  defp check_tracking(system_id, killmail) do
    kill_id = get_kill_id(killmail)
    is_tracked_system = tracked_system?(system_id)
    has_tracked_char = has_tracked_character?(killmail)

    # Enhanced logging for debugging
    Logger.debug("[KillDeterminer] Tracking check results", %{
      kill_id: kill_id,
      system_id: system_id,
      is_tracked_system: is_tracked_system,
      has_tracked_character: has_tracked_char,
      killmail_type: inspect(killmail.__struct__),
      has_esi_data: not is_nil(Map.get(killmail, :esi_data))
    })

    # For notifications, we consider both tracked systems and tracked characters
    # For persistence, we'll check has_tracked_char separately in the persistence module
    is_tracked_system || has_tracked_char
  end

  defp check_deduplication_and_decide(kill_id) do
    case DeduplicationHelper.duplicate?(:kill, kill_id) do
      {:ok, :new} -> {:ok, %{should_notify: true, reason: nil}}
      {:ok, :duplicate} -> {:ok, %{should_notify: false, reason: "Duplicate kill"}}
      {:error, _reason} -> {:ok, %{should_notify: true, reason: nil}}
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

  @doc """
  Gets the system ID from a kill.
  """
  def get_kill_system_id(kill) do
    extract_system_id(kill)
  end

  # Private helper functions to extract system ID from different data structures
  defp extract_system_id(kill) when is_struct(kill, Killmail) do
    case kill.esi_data do
      nil ->
        "unknown"

      esi_data ->
        case Map.get(esi_data, "solar_system_id") do
          nil -> "unknown"
          id when is_integer(id) -> to_string(id)
          id when is_binary(id) -> id
          _ -> "unknown"
        end
    end
  end

  defp extract_system_id(kill) when is_map(kill) do
    extract_system_id_from_map(kill)
  end

  defp extract_system_id(_), do: "unknown"

  defp extract_system_id_from_map(kill) do
    cond do
      # Check if esi_data exists AND has a solar_system_id
      esi_data = Map.get(kill, :esi_data) ->
        system_id = Map.get(esi_data, "solar_system_id")
        if is_nil(system_id), do: "unknown", else: system_id

      # Check if esi_data exists (different key format) AND has a solar_system_id
      esi_data = Map.get(kill, "esi_data") ->
        system_id = Map.get(esi_data, "solar_system_id")
        if is_nil(system_id), do: "unknown", else: system_id

      # Try to get from system key
      system = Map.get(kill, "system") ->
        system_id = Map.get(system, "id")
        if is_nil(system_id), do: "unknown", else: system_id

      # Try to get from solar_system key
      solar_system = Map.get(kill, "solar_system") ->
        system_id = Map.get(solar_system, "id")
        if is_nil(system_id), do: "unknown", else: system_id

      # Direct keys
      system_id = Map.get(kill, "solar_system_id") ->
        if is_nil(system_id), do: "unknown", else: system_id

      system_id = Map.get(kill, :solar_system_id) ->
        if is_nil(system_id), do: "unknown", else: system_id

      # Default case - no system ID found
      true ->
        "unknown"
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
    all_character_ids = get_all_tracked_character_ids()
    kill_id = get_kill_id(killmail)

    # Log the extracted data for debugging
    Logger.debug("[KillDeterminer] Checking for tracked characters", %{
      kill_id: kill_id,
      victim_data_keys: kill_data |> Map.get("victim", %{}) |> Map.keys(),
      attacker_count: kill_data |> Map.get("attackers", []) |> length(),
      tracked_character_ids: all_character_ids
    })

    # Check if victim is tracked
    victim_tracked = check_victim_tracked(kill_data, all_character_ids)

    if victim_tracked do
      Logger.debug("[KillDeterminer] Found victim is tracked", %{
        kill_id: kill_id,
        victim_id: extract_victim_id(kill_data)
      })

      true
    else
      attacker_tracked = check_attackers_tracked(kill_data, all_character_ids)

      if attacker_tracked do
        Logger.debug("[KillDeterminer] Found attacker is tracked", %{
          kill_id: kill_id
        })
      end

      attacker_tracked
    end
  end

  # Extract kill data to get useful information
  defp extract_kill_data(killmail) do
    case killmail do
      %Killmail{} -> extract_from_killmail_struct(killmail)
      %{} -> extract_from_map(killmail)
      _ -> %{}
    end
  end

  defp extract_from_killmail_struct(killmail) do
    %{
      "solar_system_id" => killmail.solar_system_id,
      "solar_system_name" => killmail.solar_system_name,
      "victim" => killmail.full_victim_data || %{},
      "attackers" => killmail.full_attacker_data || []
    }
  end

  defp extract_from_map(killmail) do
    if has_esi_data?(killmail) do
      get_esi_data(killmail)
    else
      killmail
    end
  end

  defp has_esi_data?(killmail) do
    Map.has_key?(killmail, :esi_data) || Map.has_key?(killmail, "esi_data")
  end

  defp get_esi_data(killmail) do
    Map.get(killmail, :esi_data) || Map.get(killmail, "esi_data") || %{}
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
    victim_tracked = victim_id_str && Enum.member?(all_character_ids, victim_id_str)

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
    attackers
    |> Enum.map(&extract_attacker_id/1)
    |> Enum.reject(&is_nil/1)
    |> Enum.any?(fn attacker_id -> Enum.member?(all_character_ids, attacker_id) end)
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
    system_id = get_kill_system_id(killmail)
    tracked_system?(system_id)
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
    esi_data = Map.get(killmail, :esi_data, %{})
    victim = Map.get(esi_data, "victim", %{})
    Map.get(victim, "character_id")
  end

  # Helper function to get attacker character IDs
  defp get_attacker_character_ids(killmail) do
    esi_data = Map.get(killmail, :esi_data, %{})
    attackers = Map.get(esi_data, "attackers", [])

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
