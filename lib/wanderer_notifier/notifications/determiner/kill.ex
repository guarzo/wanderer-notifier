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

  @doc """
  Determines if a notification should be sent for a kill.

  ## Parameters
    - killmail: The killmail to check

  ## Returns
    - true if a notification should be sent
    - false otherwise
  """
  def should_notify?(killmail) do
    system_id = get_kill_system_id(killmail)
    kill_id = get_kill_id(killmail)

    AppLogger.processor_debug("🔍 Starting kill notification check",
      kill_id: kill_id,
      system_id: system_id
    )

    # First check if notifications are enabled at all
    if check_notifications_enabled(kill_id) do
      AppLogger.processor_debug("🔍 Notifications enabled, checking tracking",
        kill_id: kill_id
      )

      # Check both system and character tracking
      is_tracked_system = tracked_system?(system_id)

      AppLogger.processor_debug("🔍 System tracking result",
        kill_id: kill_id,
        is_tracked_system: is_tracked_system
      )

      has_tracked_char = has_tracked_character?(killmail)

      AppLogger.processor_debug("🔍 Character tracking result",
        kill_id: kill_id,
        has_tracked_char: has_tracked_char
      )

      if is_tracked_system || has_tracked_char do
        # Only check deduplication if we have a tracked system or character
        check_deduplication_and_decide(kill_id)
      else
        AppLogger.processor_debug("🔍 Kill not in tracked system or involving tracked character",
          kill_id: kill_id,
          system_id: system_id
        )

        false
      end
    else
      AppLogger.processor_debug("🔍 Notifications disabled",
        kill_id: kill_id
      )

      false
    end
  end

  defp check_notifications_enabled(kill_id) do
    notifications_enabled = Features.notifications_enabled?()
    system_notifications_enabled = Features.system_notifications_enabled?()
    enabled = notifications_enabled && system_notifications_enabled

    AppLogger.processor_debug("🔍 Checking kill notification settings",
      kill_id: kill_id,
      enabled: enabled
    )

    enabled
  end

  defp check_deduplication_and_decide(kill_id) do
    case DeduplicationHelper.duplicate?(:kill, kill_id) do
      {:ok, :new} ->
        AppLogger.processor_debug("[Determiner] Deduplication check - kill is new",
          kill_id: kill_id,
          is_new: true
        )

        true

      {:ok, :duplicate} ->
        AppLogger.processor_debug("[Determiner] Deduplication check - kill is duplicate",
          kill_id: kill_id,
          is_new: false
        )

        false

      {:error, reason} ->
        AppLogger.processor_warn("[Determiner] Deduplication check failed, allowing by default",
          kill_id: kill_id,
          error: inspect(reason)
        )

        true
    end
  end

  # # Extract all details needed for kill notification determination
  # defp extract_kill_notification_details(killmail) do
  #   kill_id = get_kill_id(killmail)
  #   system_id = get_kill_system_id(killmail)
  #   system_name = get_kill_system_name(killmail)
  #   is_tracked_system = tracked_system?(system_id)
  #   has_tracked_character = has_tracked_character?(killmail)

  #   %{
  #     kill_id: kill_id,
  #     system_id: system_id,
  #     system_name: system_name,
  #     is_tracked_system: is_tracked_system,
  #     has_tracked_character: has_tracked_character
  #   }
  # end

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
      system_id = get_in(kill, ["esi_data", "solar_system_id"]) -> system_id
      system_id = Map.get(kill, "system_id") -> system_id
      system_id = Map.get(kill, "solar_system_id") -> system_id
      system_id = get_in(kill, ["system", "id"]) -> system_id
      system_id = get_in(kill, ["solar_system", "id"]) -> system_id
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
    AppLogger.processor_debug("🔍 Checking system tracking status",
      system_id: system_id_str,
      system_id_type: typeof(system_id_str)
    )

    # First check if we have a direct tracking entry for the system
    cache_key = CacheKeys.tracked_system(system_id_str)
    cache_value = CacheRepo.get(cache_key)

    # Log the cache check with actual value
    AppLogger.processor_debug("🔍 Tracked system cache check",
      system_id: system_id_str,
      cache_key: cache_key,
      cache_value: cache_value,
      cache_value_type: typeof(cache_value)
    )

    # Get the system details from cache too
    system_cache_key = CacheKeys.system(system_id_str)
    system_in_cache = CacheRepo.get(system_cache_key)

    AppLogger.processor_debug("🔍 System cache check",
      system_id: system_id_str,
      system_cache_key: system_cache_key,
      system_in_cache: inspect(system_in_cache),
      system_in_cache_type: typeof(system_in_cache)
    )

    # Return tracking status with detailed logging
    tracked = cache_value != nil

    AppLogger.processor_info("🎯 System tracking determination",
      system_id: system_id_str,
      tracked: tracked,
      reason:
        if(tracked,
          do: "System is being tracked",
          else: "System is not tracked"
        )
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
    # Handle different killmail formats
    kill_data = extract_kill_data(killmail)
    kill_id = extract_kill_id(killmail)

    # Get all tracked character IDs for comparison
    all_character_ids = get_all_tracked_character_ids()

    AppLogger.processor_debug("🔍 Starting character tracking check",
      kill_id: kill_id,
      tracked_characters_count: length(all_character_ids)
    )

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
    all_characters = CacheRepo.get(CacheKeys.character_list()) || []

    AppLogger.processor_debug("🔍 Getting tracked characters list",
      characters_count: length(all_characters)
    )

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
    is_tracked = CacheRepo.get(direct_cache_key) != nil

    AppLogger.processor_debug("🔍 Direct character tracking check",
      character_id: victim_id_str,
      tracked: is_tracked
    )

    is_tracked
  end

  # Check if the victim in this kill is being tracked
  defp check_victim_tracked(kill_data, kill_id, all_character_ids) do
    # Extract and format victim ID
    victim_id_str = extract_victim_id(kill_data)

    AppLogger.processor_debug("🔍 Checking victim tracking",
      kill_id: kill_id,
      victim_id: victim_id_str,
      tracked_characters: length(all_character_ids)
    )

    # Check if victim is tracked against character_id list
    victim_tracked = victim_id_str && Enum.member?(all_character_ids, victim_id_str)

    # Also try direct cache lookup for victim if not already tracked
    is_tracked =
      if !victim_tracked && victim_id_str do
        check_direct_victim_tracking(victim_id_str)
      else
        victim_tracked
      end

    if is_tracked do
      AppLogger.processor_info("🎯 Character tracking determination: victim is tracked",
        kill_id: kill_id,
        victim_id: victim_id_str
      )
    else
      AppLogger.processor_debug("🔍 Victim not tracked, checking attackers next",
        kill_id: kill_id,
        victim_id: victim_id_str
      )
    end

    is_tracked
  end

  # Extract attackers from kill data
  defp extract_attackers(kill_data) do
    Map.get(kill_data, "attackers") || Map.get(kill_data, :attackers) || []
  end

  # Check if any attacker is tracked
  defp check_attackers_tracked(kill_data, kill_id, all_character_ids) do
    # Get attacker data
    attackers = extract_attackers(kill_data)

    AppLogger.processor_debug("🔍 Checking attackers tracking",
      kill_id: kill_id,
      attackers_count: length(attackers)
    )

    # Check if any attacker is tracked
    is_tracked =
      if attacker_in_tracked_list?(attackers, all_character_ids) do
        true
      else
        # If no attackers in tracked list, check direct cache lookup
        attacker_directly_tracked?(attackers)
      end

    if is_tracked do
      tracked_attacker =
        Enum.find(attackers, fn attacker ->
          attacker_id = extract_attacker_id(attacker)

          attacker_id &&
            (Enum.member?(all_character_ids, attacker_id) ||
               check_direct_victim_tracking(attacker_id))
        end)

      AppLogger.processor_info("🎯 Character tracking determination: attacker is tracked",
        kill_id: kill_id,
        attacker_id: extract_attacker_id(tracked_attacker)
      )
    else
      AppLogger.processor_info("🎯 Character tracking determination: no tracked characters",
        kill_id: kill_id,
        attackers_count: length(attackers)
      )
    end

    is_tracked
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

  @doc """
  Determines the type of a term.
  """
  def typeof(term) do
    type_from_term(term)
  end

  # Break down type checking into smaller functions for better maintainability
  defp type_from_term(term) when is_binary(term), do: :string
  defp type_from_term(term) when is_boolean(term), do: :boolean
  defp type_from_term(term) when is_integer(term), do: :integer
  defp type_from_term(term) when is_float(term), do: :float
  defp type_from_term(term) when is_list(term), do: :list
  defp type_from_term(term) when is_map(term), do: :map
  defp type_from_term(term) when is_atom(term), do: :atom
  defp type_from_term(term) when is_tuple(term), do: :tuple
  defp type_from_term(term) when is_function(term), do: :function
  defp type_from_term(term) when is_pid(term), do: :pid
  defp type_from_term(term) when is_reference(term), do: :reference
  defp type_from_term(_), do: :unknown
end
