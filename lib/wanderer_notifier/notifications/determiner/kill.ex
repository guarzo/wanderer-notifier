defmodule WandererNotifier.Notifications.Determiner.Kill do
  @moduledoc """
  Determines whether kill notifications should be sent.
  Handles all kill-related notification decision logic.
  """

  @behaviour WandererNotifier.Notifications.Determiner.KillBehaviour

  alias WandererNotifier.Cache.Keys, as: CacheKeys
  alias WandererNotifier.Killmail.Killmail

  # Get the configured cache repo at runtime, not compile time
  defp cache_repo, do: Application.get_env(:wanderer_notifier, :cache_repo)

  # Get the configured deduplication module at runtime, not compile time
  defp deduplication_module do
    Application.get_env(:wanderer_notifier, :deduplication_module) ||
      WandererNotifier.Notifications.Helpers.Deduplication
  end

  @impl true
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

    cond do
      not check_notifications_enabled() ->
        {:ok, %{should_notify: false, reason: "Notifications disabled"}}

      not check_tracking(system_id, killmail) ->
        {:ok, %{should_notify: false, reason: "Not tracked by any character or system"}}

      true ->
        check_deduplication_and_decide(kill_id)
    end
  end

  defp check_notifications_enabled do
    # Get the config module from application environment at runtime
    config_module = Application.get_env(:wanderer_notifier, :config)

    # Check if config_module is nil or is a valid module
    if config_module == nil do
      # Default to enabled if config_module is nil
      true
    else
      # Call the config functions
      notifications_enabled = config_module.notifications_enabled?()
      system_notifications_enabled = config_module.system_notifications_enabled?()

      notifications_enabled && system_notifications_enabled
    end
  end

  defp check_tracking(nil, killmail) do
    # If no system ID, only check for tracked characters
    has_tracked_char = has_tracked_character?(killmail)
    has_tracked_char
  end

  defp check_tracking(system_id, killmail) do
    is_tracked_system = tracked_system?(system_id)
    has_tracked_char = has_tracked_character?(killmail)
    is_tracked_system || has_tracked_char
  end

  defp check_deduplication_and_decide(kill_id) do
    case deduplication_module().check(:kill, kill_id) do
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

  @impl true
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
    case Map.get(kill, "solar_system_id") do
      nil -> nil
      id when is_integer(id) -> id
      id when is_binary(id) -> id
      _ -> nil
    end
  end

  @impl true
  @doc """
  Checks if a system is being tracked.

  ## Parameters
    - system_id: The ID of the system to check

  ## Returns
    - true if the system is tracked
    - false otherwise
  """
  def tracked_system?(nil), do: false

  def tracked_system?(system_id) when is_integer(system_id),
    do: tracked_system?(to_string(system_id))

  def tracked_system?(system_id_str) when is_binary(system_id_str) do
    result = cache_repo().get(CacheKeys.map_systems())

    case result do
      {:ok, systems} when is_list(systems) ->
        Enum.any?(systems, fn system ->
          id = Map.get(system, :solar_system_id) || Map.get(system, "solar_system_id")
          to_string(id) == system_id_str
        end)

      _ ->
        false
    end
  end

  def tracked_system?(_), do: false

  @impl true
  @doc """
  Checks if a killmail involves a tracked character.

  ## Parameters
    - killmail: The killmail data to check

  ## Returns
    - true if the killmail involves a tracked character
    - false otherwise
  """
  def has_tracked_character?(killmail) do
    kill_data = extract_kill_data(killmail)

    # Check victim first
    victim_id_str = extract_victim_id(kill_data)
    victim_tracked = check_character_tracked(victim_id_str)

    if victim_tracked do
      true
    else
      # Then check attackers
      attackers = extract_attackers(kill_data)

      attackers
      |> Enum.map(&extract_attacker_id/1)
      |> Enum.reject(&is_nil/1)
      |> Enum.any?(&check_character_tracked/1)
    end
  end

  # Check if a character is tracked (either in list or direct tracking)
  defp check_character_tracked(nil), do: false

  defp check_character_tracked(character_id) do
    # First check in the list of tracked characters
    all_character_ids = get_all_tracked_character_ids()
    in_list = Enum.member?(all_character_ids, character_id)

    # If not in list, try direct tracking
    if !in_list do
      direct_cache_key = CacheKeys.tracked_character(character_id)

      case cache_repo().get(direct_cache_key) do
        {:ok, _} -> true
        _ -> false
      end
    else
      true
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
    case cache_repo().get(CacheKeys.character_list()) do
      {:ok, all_characters} when is_list(all_characters) ->
        all_characters
        |> Enum.map(&extract_character_id/1)
        |> Enum.reject(&is_nil/1)

      _ ->
        []
    end
  end

  # Extract character ID from character data
  defp extract_character_id(char) do
    character_id = Map.get(char, "character_id") || Map.get(char, :character_id)
    if character_id, do: to_string(character_id), else: nil
  end

  # Extract victim ID from kill data
  defp extract_victim_id(kill_data) do
    victim = Map.get(kill_data, "victim") || Map.get(kill_data, :victim) || %{}
    victim_id = Map.get(victim, "character_id") || Map.get(victim, :character_id)
    if victim_id, do: to_string(victim_id), else: nil
  end

  # Extract attackers from kill data
  defp extract_attackers(kill_data) do
    Map.get(kill_data, "attackers") || Map.get(kill_data, :attackers) || []
  end

  # Extract attacker ID from attacker data
  defp extract_attacker_id(attacker) do
    attacker_id = Map.get(attacker, "character_id") || Map.get(attacker, :character_id)
    if attacker_id, do: to_string(attacker_id), else: nil
  end

  @impl true
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

  @impl true
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

  @impl true
  @doc """
  Checks if a character is being tracked.

  ## Parameters
    - character_id: The ID of the character to check

  ## Returns
    - true if the character is tracked
    - false otherwise
  """
  def tracked_character?(character_id) when is_integer(character_id),
    do: tracked_character?(to_string(character_id))

  def tracked_character?(character_id_str) when is_binary(character_id_str) do
    result = cache_repo().get(CacheKeys.character_list())

    case result do
      {:ok, characters} when is_list(characters) ->
        Enum.any?(characters, fn char ->
          id = Map.get(char, :character_id) || Map.get(char, "character_id")
          to_string(id) == character_id_str
        end)

      _ ->
        false
    end
  end

  def tracked_character?(_), do: false
end
