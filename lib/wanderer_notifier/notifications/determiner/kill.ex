defmodule WandererNotifier.Notifications.Determiner.Kill do
  @moduledoc """
  Determines whether kill notifications should be sent.
  Handles all kill-related notification decision logic.
  """

  alias WandererNotifier.Config.Features
  alias WandererNotifier.Data.Cache.Keys, as: CacheKeys
  alias WandererNotifier.Data.Cache.Repository, as: CacheRepo
  alias WandererNotifier.Data.Killmail
  alias WandererNotifier.Helpers.DeduplicationHelper

  @doc """
  Determines if a notification should be sent for a kill.

  ## Parameters
    - killmail: The killmail to check

  ## Returns
    - {:ok, %{should_notify: boolean(), reason: String.t()}} with tracking information
  """
  def should_notify?(killmail) do
    system_id = get_kill_system_id(killmail)
    kill_id = get_kill_id(killmail)

    with true <- check_notifications_enabled(kill_id),
         true <- check_tracking(system_id, killmail) do
      check_deduplication_and_decide(kill_id)
    else
      false -> {:ok, %{should_notify: false, reason: "Not tracked by any character or system"}}
      _ -> {:ok, %{should_notify: false, reason: "Notifications disabled"}}
    end
  end

  defp check_notifications_enabled(_kill_id) do
    notifications_enabled = Features.notifications_enabled?()
    system_notifications_enabled = Features.system_notifications_enabled?()
    notifications_enabled && system_notifications_enabled
  end

  defp check_tracking(system_id, killmail) do
    is_tracked_system = tracked_system?(system_id)
    has_tracked_char = has_tracked_character?(killmail)
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
      esi_data = Map.get(kill, "esi_data") -> Map.get(esi_data, "solar_system_id")
      system = Map.get(kill, "system") -> Map.get(system, "id")
      solar_system = Map.get(kill, "solar_system") -> Map.get(solar_system, "id")
      true -> "unknown"
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

    # Check if victim is tracked
    victim_tracked = check_victim_tracked(kill_data, all_character_ids)

    if victim_tracked do
      true
    else
      check_attackers_tracked(kill_data, all_character_ids)
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
end
