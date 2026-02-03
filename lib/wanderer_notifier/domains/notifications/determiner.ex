defmodule WandererNotifier.Domains.Notifications.Determiner do
  @moduledoc """
  Notification determiner that handles all notification types.

  Determines whether notifications should be sent for characters, systems,
  and killmails based on feature flags, tracking state, and deduplication.
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
  # Common Helper Functions
  # ══════════════════════════════════════════════════════════════════════════════

  # Checks if notifications are suppressed during startup period
  defp startup_suppressed?, do: Startup.in_suppression_period?()

  # Checks if the feature flag for the given notification type is enabled
  defp feature_enabled?(:character), do: Config.character_notifications_enabled?()
  defp feature_enabled?(:system), do: Config.system_notifications_enabled?()
  defp feature_enabled?(:kill), do: Config.kill_notifications_enabled?()
  defp feature_enabled?(:rally_point), do: Config.rally_notifications_enabled?()

  # Logs startup suppression for a notification type
  defp log_startup_suppression(:character, entity_id) do
    Logger.debug("Character notification suppressed during startup period",
      character_id: entity_id,
      category: :notification
    )
  end

  defp log_startup_suppression(:system, entity_id) do
    Logger.debug("System notification suppressed during startup period",
      system_id: entity_id,
      category: :notification
    )
  end

  # Standard deduplication check returning boolean (for character/rally_point)
  defp check_dedup_boolean(type, entity_id) do
    case Deduplication.check(type, entity_id) do
      {:ok, :new} -> true
      {:ok, :duplicate} -> false
      {:error, _reason} -> true
    end
  end

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
      startup_suppressed?() ->
        log_startup_suppression(:character, character_id)
        false

      not feature_enabled?(:character) ->
        false

      true ->
        check_dedup_boolean(:character, character_id)
    end
  end

  def should_notify?(:system, system_id, system_data) do
    is_priority = priority_system?(system_data)

    cond do
      startup_suppressed?() ->
        log_startup_suppression(:system, system_id)
        false

      not feature_enabled?(:system) and not is_priority ->
        Logger.debug("System notification skipped - notifications disabled and not priority",
          system_id: system_id,
          category: :notification
        )

        false

      true ->
        check_system_deduplication(system_id, is_priority)
    end
  end

  def should_notify?(:kill, _killmail_id, killmail_data) do
    # For killmails, we delegate to the specialized killmail logic
    should_notify_killmail?(killmail_data)
  end

  def should_notify?(:rally_point, rally_id, _rally_data) do
    cond do
      startup_suppressed?() -> false
      not feature_enabled?(:rally_point) -> false
      true -> check_dedup_boolean(:rally_point, rally_id)
    end
  end

  defp check_system_deduplication(system_id, is_priority) do
    case Deduplication.check(:system, system_id) do
      {:ok, :new} ->
        if is_priority,
          do:
            Logger.info("Priority system notification will be sent",
              system_id: system_id,
              category: :notification
            )

        true

      {:ok, :duplicate} ->
        false

      {:error, reason} ->
        Logger.warning("System deduplication check failed",
          system_id: system_id,
          is_priority: is_priority,
          reason: inspect(reason),
          category: :notification
        )

        true
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
  def tracked_character?(character_id) when is_integer(character_id),
    do: tracked_character?(Integer.to_string(character_id))

  def tracked_character?(character_id_str) when is_binary(character_id_str) do
    case WandererNotifier.Domains.Tracking.MapTrackingClient.is_character_tracked?(
           character_id_str
         ) do
      {:ok, tracked} ->
        tracked

      {:error, reason} ->
        require Logger

        Logger.error("Failed to check if character is tracked",
          character_id: character_id_str,
          reason: inspect(reason)
        )

        false
    end
  end

  def tracked_character?(_), do: false

  @doc """
  Checks if a system is being tracked.
  """
  def tracked_system?(system_id) when is_integer(system_id),
    do: tracked_system?(Integer.to_string(system_id))

  def tracked_system?(system_id_str) when is_binary(system_id_str) do
    case WandererNotifier.Domains.Tracking.MapTrackingClient.is_system_tracked?(system_id_str) do
      {:ok, tracked} ->
        tracked

      {:error, reason} ->
        require Logger

        Logger.error("Failed to check if system is tracked",
          system_id: system_id_str,
          reason: inspect(reason)
        )

        false
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
  def changed?(:kill, _, _), do: true

  @doc """
  Checks if a character's data has changed from what's in cache.
  """
  def character_changed?(character_id, new_data)
      when (is_binary(character_id) or is_integer(character_id)) and not is_nil(new_data) do
    check_cache_changed(Cache.get_character(character_id), new_data)
  end

  def character_changed?(_, _), do: false

  @doc """
  Checks if a system's data has changed from what's in cache.
  """
  def system_changed?(system_id, new_data) do
    check_cache_changed(Cache.get_system(system_id), new_data)
  end

  # Common helper for cache change detection
  defp check_cache_changed({:ok, old_data}, new_data) when old_data != nil,
    do: old_data != new_data

  defp check_cache_changed(_, _), do: true

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
    attacker_ids = killmail |> Killmail.get_attacker() |> Enum.map(&Map.get(&1, "character_id"))
    any_tracked_character?(victim_id, attacker_ids)
  end

  def has_tracked_character?(%{"victim" => victim, "attackers" => attackers}) do
    attacker_ids = Enum.map(attackers, &get_in(&1, ["character_id"]))
    any_tracked_character?(get_in(victim, ["character_id"]), attacker_ids)
  end

  def has_tracked_character?(%{victim: victim, attackers: attackers}) do
    attacker_ids = Enum.map(attackers, &Map.get(&1, :character_id))
    any_tracked_character?(Map.get(victim, :character_id), attacker_ids)
  end

  defp any_tracked_character?(victim_id, attacker_ids),
    do: tracked_character?(victim_id) or Enum.any?(attacker_ids, &tracked_character?/1)

  # ══════════════════════════════════════════════════════════════════════════════
  # Private Helper Functions
  # ══════════════════════════════════════════════════════════════════════════════

  # Checks if a system is marked as a priority system.
  defp priority_system?(nil), do: false

  defp priority_system?(system_data) when is_map(system_data) do
    case extract_system_name(system_data) do
      name when is_binary(name) -> :erlang.phash2(name) in PersistentValues.get(:priority_systems)
      _ -> false
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
      startup_suppressed?() ->
        {:ok, %{should_notify: false, reason: :startup_suppression}}

      not feature_enabled?(:kill) ->
        {:ok, %{should_notify: false, reason: :kill_notifications_disabled}}

      tracked_system_for_killmail?(system_id) or tracked_character?(victim_character_id) ->
        check_killmail_deduplication(killmail_id)

      true ->
        {:ok, %{should_notify: false, reason: :no_tracked_entities}}
    end
  end

  defp check_killmail_deduplication(killmail_id) do
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
