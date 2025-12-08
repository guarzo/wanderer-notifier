defmodule WandererNotifier.Domains.Notifications.Determiner do
  @moduledoc """
  Unified notification determiner that handles all notification types.

  Consolidates the logic for determining whether notifications should be sent
  for characters, systems, and killmails. Replaces the separate Character,
  System, and Kill determiner modules with a single, cohesive interface.
  """

  require Logger
  alias WandererNotifier.Shared.Config
  alias WandererNotifier.Infrastructure.Cache
  alias WandererNotifier.Domains.Notifications.Deduplication
  alias WandererNotifier.Domains.Killmail.Killmail
  alias WandererNotifier.Shared.Utils.Startup
  alias WandererNotifier.PersistentValues

  @type notification_type :: :character | :system | :kill
  @type entity_id :: String.t() | integer()
  @type entity_data :: map() | struct() | nil
  @type notification_result ::
          {:ok, %{should_notify: boolean(), reason: String.t() | atom() | nil}} | {:error, term()}

  # ══════════════════════════════════════════════════════════════════════════════
  # Main Notification Decision Logic
  # ══════════════════════════════════════════════════════════════════════════════

  @doc """
  Determines if a notification should be sent for the given type and entity.

  ## Parameters
    - type: The notification type (:character, :system, or :kill)
    - entity_id: The ID of the entity
    - entity_data: Optional entity data for additional context

  ## Returns
    - true if a notification should be sent
    - false otherwise
  """
  @spec should_notify?(notification_type(), entity_id()) :: boolean()
  @spec should_notify?(notification_type(), entity_id(), entity_data()) :: boolean()
  def should_notify?(type, entity_id, entity_data \\ nil)

  def should_notify?(:character, character_id, _character_data) do
    cond do
      Startup.in_suppression_period?() ->
        Logger.debug("Character notification suppressed during startup period",
          character_id: character_id,
          category: :notification
        )

        false

      not Config.character_notifications_enabled?() ->
        false

      true ->
        case Deduplication.check(:character, character_id) do
          {:ok, :new} -> true
          {:ok, :duplicate} -> false
          {:error, _reason} -> true
        end
    end
  end

  def should_notify?(:system, system_id, system_data) do
    is_priority = priority_system?(system_data)

    cond do
      Startup.in_suppression_period?() ->
        Logger.debug("System notification suppressed during startup period",
          system_id: system_id,
          category: :notification
        )

        false

      not Config.system_notifications_enabled?() and not is_priority ->
        Logger.debug("System notification skipped - notifications disabled and not priority",
          system_id: system_id,
          category: :notification
        )

        false

      true ->
        check_system_deduplication(system_id, is_priority)
    end
  end

  defp check_system_deduplication(system_id, is_priority) do
    case Deduplication.check(:system, system_id) do
      {:ok, :new} ->
        log_priority_system_notification(system_id, is_priority)
        true

      {:ok, :duplicate} ->
        false

      {:error, _reason} ->
        true
    end
  end

  defp log_priority_system_notification(system_id, true) do
    Logger.info("Priority system notification will be sent",
      system_id: system_id,
      category: :notification
    )
  end

  defp log_priority_system_notification(_system_id, false), do: :ok

  def should_notify?(:kill, _killmail_id, killmail_data) do
    # For killmails, we delegate to the specialized killmail logic
    should_notify_killmail?(killmail_data)
  end

  def should_notify?(:rally_point, rally_id, _rally_data) do
    cond do
      Startup.in_suppression_period?() ->
        false

      not Config.rally_notifications_enabled?() ->
        false

      true ->
        case Deduplication.check(:rally_point, rally_id) do
          {:ok, :new} -> true
          {:ok, :duplicate} -> false
          {:error, _reason} -> true
        end
    end
  end

  # ══════════════════════════════════════════════════════════════════════════════
  # Killmail-Specific Logic (from Kill determiner)
  # ══════════════════════════════════════════════════════════════════════════════

  @doc """
  Determines if a notification should be sent for a killmail.
  Returns {:ok, %{should_notify: boolean, reason: string | atom}} or {:error, atom}
  """
  @spec should_notify_killmail?(Killmail.t() | map()) :: notification_result()
  def should_notify_killmail?(%Killmail{} = killmail) do
    killmail_id = killmail.killmail_id
    system_id = Killmail.get_system_id(killmail)
    victim_character_id = Killmail.get_victim_character_id(killmail)

    check_killmail_notification(killmail_id, system_id, victim_character_id)
  end

  # Handle WebSocket killmail format with atom keys
  def should_notify_killmail?(%{killmail_id: id, system_id: system_id, victim: victim} = _data) do
    victim_character_id = Map.get(victim, :character_id)
    check_killmail_notification(id, system_id, victim_character_id)
  end

  def should_notify_killmail?(%{"killmail_id" => id} = data) do
    system_id = get_in(data, ["solar_system_id"])
    victim_character_id = get_in(data, ["victim", "character_id"])

    check_killmail_notification(id, system_id, victim_character_id)
  end

  def should_notify_killmail?(%{"killID" => id, "killmail" => killmail_data} = _data) do
    # Handle zkillboard format with nested killmail data
    system_id = get_in(killmail_data, ["solar_system_id"])
    victim_character_id = get_in(killmail_data, ["victim", "character_id"])
    killmail_id = get_in(killmail_data, ["killmail_id"]) || id

    check_killmail_notification(killmail_id, system_id, victim_character_id)
  end

  def should_notify_killmail?(%{"solar_system_id" => _} = data) do
    # Generate a unique ID for non-killmail data
    id = :erlang.phash2(data)
    system_id = get_in(data, ["solar_system_id"])
    victim_character_id = get_in(data, ["victim", "character_id"])

    check_killmail_notification(id, system_id, victim_character_id)
  end

  def should_notify_killmail?(%{killmail: killmail}) do
    # Handle special format
    killmail_id = Map.get(killmail, :killmail_id) || Map.get(killmail, "killmail_id")
    system_id = Map.get(killmail, :system_id) || Map.get(killmail, "solar_system_id")

    victim_character_id =
      get_in(killmail, [:victim, :character_id]) || get_in(killmail, ["victim", "character_id"])

    check_killmail_notification(killmail_id, system_id, victim_character_id)
  end

  def should_notify_killmail?(%{esi_data: esi_data} = _data) do
    # Handle ESI data format
    killmail_id = get_in(esi_data, ["killmail_id"])
    system_id = get_in(esi_data, ["solar_system_id"])
    victim_character_id = get_in(esi_data, ["victim", "character_id"])

    check_killmail_notification(killmail_id, system_id, victim_character_id)
  end

  def should_notify_killmail?(data) do
    Logger.warning("Unknown killmail format: #{inspect(data)}")
    {:error, :unknown_format}
  end

  # ══════════════════════════════════════════════════════════════════════════════
  # Tracking Check Functions
  # ══════════════════════════════════════════════════════════════════════════════

  @doc """
  Checks if an entity is being tracked based on its type and ID.

  ## Parameters
    - type: The entity type (:character or :system)
    - entity_id: The ID of the entity to check

  ## Returns
    - true if the entity is tracked
    - false otherwise
  """
  @spec tracked?(notification_type(), entity_id()) :: boolean()
  def tracked?(:character, character_id), do: tracked_character?(character_id)
  def tracked?(:system, system_id), do: tracked_system?(system_id)
  # Killmails don't have a tracking concept
  def tracked?(:kill, _), do: true

  @doc """
  Checks if a character is being tracked.
  """
  def tracked_character?(character_id) when is_integer(character_id) do
    character_id_str = Integer.to_string(character_id)
    tracked_character?(character_id_str)
  end

  def tracked_character?(character_id_str) when is_binary(character_id_str) do
    case WandererNotifier.Domains.Tracking.MapTrackingClient.is_character_tracked?(
           character_id_str
         ) do
      {:ok, tracked} -> tracked
    end
  end

  def tracked_character?(_), do: false

  @doc """
  Checks if a system is being tracked.
  """
  def tracked_system?(system_id) when is_integer(system_id) do
    system_id_str = Integer.to_string(system_id)
    tracked_system?(system_id_str)
  end

  def tracked_system?(system_id_str) when is_binary(system_id_str) do
    case WandererNotifier.Domains.Tracking.MapTrackingClient.is_system_tracked?(system_id_str) do
      {:ok, tracked} -> tracked
    end
  end

  def tracked_system?(_), do: false

  # ══════════════════════════════════════════════════════════════════════════════
  # Change Detection Functions
  # ══════════════════════════════════════════════════════════════════════════════

  @doc """
  Checks if entity data has changed from what's in cache.
  """
  def changed?(:character, character_id, new_data), do: character_changed?(character_id, new_data)
  def changed?(:system, system_id, new_data), do: system_changed?(system_id, new_data)
  # Killmails are always considered "changed"
  def changed?(:kill, _, _), do: true

  @doc """
  Checks if a character's data has changed from what's in cache.
  """
  def character_changed?(character_id, new_data)
      when (is_binary(character_id) or is_integer(character_id)) and not is_nil(new_data) do
    case Cache.get_character(character_id) do
      {:ok, old_data} when old_data != nil ->
        old_data != new_data

      {:error, :not_found} ->
        true

      _ ->
        true
    end
  end

  def character_changed?(_, _), do: false

  @doc """
  Checks if a system's data has changed from what's in cache.
  """
  def system_changed?(system_id, new_data) do
    case Cache.get_system(system_id) do
      {:ok, old_data} when old_data != nil ->
        old_data != new_data

      {:error, :not_found} ->
        true

      _ ->
        true
    end
  end

  # ══════════════════════════════════════════════════════════════════════════════
  # Killmail-Specific Helper Functions (from Kill determiner)
  # ══════════════════════════════════════════════════════════════════════════════

  @doc """
  Checks if a system is tracked for killmail notifications.
  Handles special cases like nil and "unknown" system IDs.
  """
  def tracked_system_for_killmail?(nil), do: false
  def tracked_system_for_killmail?("unknown"), do: false
  def tracked_system_for_killmail?(id), do: tracked?(:system, id)

  @doc """
  Checks if any character in a killmail is being tracked.
  """
  def has_tracked_character?(%Killmail{} = killmail) do
    victim_id = Killmail.get_victim_character_id(killmail)
    attackers = Killmail.get_attacker(killmail)
    attacker_ids = Enum.map(attackers, &Map.get(&1, "character_id"))

    tracked_character?(victim_id) or Enum.any?(attacker_ids, &tracked_character?/1)
  end

  def has_tracked_character?(%{"victim" => victim, "attackers" => attackers}) do
    victim_id = get_in(victim, ["character_id"])
    attacker_ids = Enum.map(attackers, &get_in(&1, ["character_id"]))

    tracked_character?(victim_id) or Enum.any?(attacker_ids, &tracked_character?/1)
  end

  def has_tracked_character?(%{victim: victim, attackers: attackers}) do
    victim_id = Map.get(victim, :character_id)
    attacker_ids = Enum.map(attackers, &Map.get(&1, :character_id))

    tracked_character?(victim_id) or Enum.any?(attacker_ids, &tracked_character?/1)
  end

  # ══════════════════════════════════════════════════════════════════════════════
  # Private Helper Functions
  # ══════════════════════════════════════════════════════════════════════════════

  # Checks if a system is marked as a priority system.
  # Priority systems are identified by hashing the system name and checking against
  # the stored priority system list. This allows priority system notifications to
  # bypass the system_notifications_enabled? check.
  defp priority_system?(nil), do: false

  defp priority_system?(system_data) when is_map(system_data) do
    # Extract system name from various possible structures
    system_name = extract_system_name(system_data)

    case system_name do
      nil ->
        false

      name when is_binary(name) ->
        system_hash = :erlang.phash2(name)
        priority_systems = PersistentValues.get(:priority_systems)
        system_hash in priority_systems
    end
  end

  defp priority_system?(_), do: false

  # Extract system name from various data structures
  defp extract_system_name(%{name: name}) when is_binary(name), do: name
  defp extract_system_name(%{"name" => name}) when is_binary(name), do: name

  defp extract_system_name(%{solar_system_name: name}) when is_binary(name), do: name

  defp extract_system_name(%{"solar_system_name" => name}) when is_binary(name), do: name

  defp extract_system_name(_), do: nil

  defp check_killmail_notification(killmail_id, system_id, victim_character_id) do
    cond do
      Startup.in_suppression_period?() ->
        {:ok, %{should_notify: false, reason: :startup_suppression}}

      not Config.kill_notifications_enabled?() ->
        {:ok, %{should_notify: false, reason: :kill_notifications_disabled}}

      has_tracked_system_or_character?(system_id, victim_character_id) ->
        check_deduplication(killmail_id)

      true ->
        {:ok, %{should_notify: false, reason: :no_tracked_entities}}
    end
  end

  defp has_tracked_system_or_character?(system_id, victim_character_id) do
    tracked_system_for_killmail?(system_id) or tracked_character?(victim_character_id)
  end

  defp check_deduplication(killmail_id) do
    case Deduplication.check(:kill, killmail_id) do
      {:ok, :new} ->
        {:ok, %{should_notify: true, reason: :new_killmail}}

      {:ok, :duplicate} ->
        {:ok, %{should_notify: false, reason: :duplicate_killmail}}

      {:error, reason} ->
        Logger.warning("Deduplication check failed: #{inspect(reason)}")
        {:ok, %{should_notify: true, reason: :deduplication_failed}}
    end
  end
end
