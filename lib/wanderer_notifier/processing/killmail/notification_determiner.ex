defmodule WandererNotifier.Processing.Killmail.NotificationDeterminer do
  @moduledoc """
  Determines if a notification should be sent for a killmail.

  This module provides a clean interface for determining if a notification should
  be sent for a killmail, based on tracking rules and deduplication.

  @deprecated Use WandererNotifier.Killmail.Processing.NotificationDeterminer instead.
  """

  require Logger

  alias WandererNotifier.Config.Features
  alias WandererNotifier.Data.Cache.Keys, as: CacheKeys
  alias WandererNotifier.Data.Cache.Repository, as: CacheRepo
  alias WandererNotifier.Helpers.DeduplicationHelper
  alias WandererNotifier.KillmailProcessing.KillmailData
  alias WandererNotifier.Logger.Logger, as: AppLogger
  alias WandererNotifier.Killmail.Processing.NotificationDeterminer, as: NewNotificationDeterminer
  alias WandererNotifier.Killmail.Core.Data, as: NewKillmailData

  @type notification_result :: {boolean(), String.t()}

  @doc """
  Determines if a notification should be sent for a killmail.

  ## Parameters
    - killmail: The KillmailData struct to check

  ## Returns
    - {:ok, {should_notify, reason}} with boolean notification decision and reason
    - {:error, reason} on failure

  @deprecated Use WandererNotifier.Killmail.Processing.NotificationDeterminer.should_notify?/1 instead.
  """
  @spec should_notify?(KillmailData.t()) :: {:ok, notification_result()} | {:error, any()}
  def should_notify?(%KillmailData{} = killmail) do
    # Log deprecation warning
    Logger.warning(
      "DEPRECATED: WandererNotifier.Processing.Killmail.NotificationDeterminer is deprecated. " <>
        "Use WandererNotifier.Killmail.Processing.NotificationDeterminer instead."
    )

    # Convert old KillmailData to new KillmailData format
    case convert_to_new_format(killmail) do
      {:ok, new_killmail} ->
        # Delegate to the new module
        new_result = NewNotificationDeterminer.should_notify?(new_killmail)

        # Convert the new result format to the old format if needed
        case new_result do
          {:ok, %{should_notify: should_notify, reason: reason}} ->
            {:ok, {should_notify, reason}}

          {:ok, {should_notify, reason}} ->
            {:ok, {should_notify, reason}}

          other ->
            other
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  def should_notify?(other) do
    # Log deprecation warning
    Logger.warning(
      "DEPRECATED: WandererNotifier.Processing.Killmail.NotificationDeterminer is deprecated. " <>
        "Use WandererNotifier.Killmail.Processing.NotificationDeterminer instead."
    )

    # Delegate to the new module
    case NewNotificationDeterminer.should_notify?(other) do
      {:ok, %{should_notify: should_notify, reason: reason}} ->
        {:ok, {should_notify, reason}}

      {:ok, {should_notify, reason}} ->
        {:ok, {should_notify, reason}}

      other ->
        other
    end
  end

  # Helper function to convert old KillmailData to new KillmailData format
  defp convert_to_new_format(%KillmailData{} = old_killmail) do
    # Check if it's already the new format
    if Map.has_key?(old_killmail, :__struct__) and old_killmail.__struct__ == NewKillmailData do
      {:ok, old_killmail}
    else
      # Extract all fields from the old format to create a new one
      # This assumes the field names are roughly similar
      attrs = Map.from_struct(old_killmail)

      case NewKillmailData.from_map(attrs) do
        {:ok, new_killmail} -> {:ok, new_killmail}
        error -> error
      end
    end
  rescue
    e ->
      Logger.error("Error converting KillmailData: #{inspect(e)}")
      {:error, :conversion_error}
  end

  # Check if notifications are enabled globally
  defp check_notifications_enabled do
    notifications_enabled = Features.notifications_enabled?()
    system_notifications_enabled = Features.system_notifications_enabled?()

    cond do
      !notifications_enabled ->
        {:notifications_disabled, "Global notifications disabled"}

      !system_notifications_enabled ->
        {:notifications_disabled, "System notifications disabled"}

      true ->
        true
    end
  end

  # Check if the killmail is being tracked
  defp check_tracking(killmail) do
    # Check if system is tracked
    system_tracked = is_tracked_system?(killmail.solar_system_id)

    # Check if any character is tracked
    character_tracked = has_tracked_character?(killmail)

    # Determine if tracked and the reason
    cond do
      system_tracked and character_tracked ->
        {true, "Both system and character tracked"}

      system_tracked ->
        {true, "System tracked"}

      character_tracked ->
        {true, "Character tracked"}

      true ->
        {false, "Not tracked by any character or system"}
    end
  end

  # Check if killmail is a duplicate
  defp check_deduplication(kill_id) do
    case DeduplicationHelper.duplicate?(:kill, kill_id) do
      {:ok, :new} ->
        {true, nil}

      {:ok, :duplicate} ->
        {false, "Duplicate kill"}

      {:error, reason} ->
        AppLogger.kill_error("Error checking for duplicate: #{inspect(reason)}")
        # On error, assume it's not a duplicate to avoid missing notifications
        {true, "Error checking deduplication: #{inspect(reason)}"}
    end
  end

  # Determine the combined reason for the notification decision
  defp determine_reason(true, tracking_reason, true, _dedup_reason) do
    # Tracked and not a duplicate - use the tracking reason
    tracking_reason
  end

  defp determine_reason(true, _tracking_reason, false, dedup_reason) do
    # Tracked but duplicate
    dedup_reason
  end

  defp determine_reason(false, tracking_reason, _not_duplicate, _dedup_reason) do
    # Not tracked
    tracking_reason
  end

  # Log the notification decision
  defp log_notification_decision(killmail, should_notify, reason) do
    kill_id = killmail.killmail_id

    if should_notify do
      AppLogger.kill_debug("WILL send notification for killmail ##{kill_id}: #{reason}")
    else
      AppLogger.kill_debug("Will NOT send notification for killmail ##{kill_id}: #{reason}")
    end
  end

  # Check if a system is being tracked
  defp is_tracked_system?(system_id) when is_integer(system_id) do
    system_id_str = Integer.to_string(system_id)
    cache_key = CacheKeys.tracked_system(system_id_str)
    CacheRepo.get(cache_key) != nil
  end

  defp is_tracked_system?(_), do: false

  # Check if killmail involves a tracked character
  defp has_tracked_character?(%KillmailData{} = killmail) do
    # Get all tracked character IDs
    tracked_character_ids = get_all_tracked_character_ids()

    # Check if victim is tracked
    victim_tracked =
      if killmail.victim_id && Enum.member?(tracked_character_ids, to_string(killmail.victim_id)) do
        true
      else
        false
      end

    if victim_tracked do
      true
    else
      # Check if any attacker is tracked
      check_attackers_tracked(killmail.attackers, tracked_character_ids)
    end
  end

  # Get all tracked character IDs
  defp get_all_tracked_character_ids do
    all_characters = CacheRepo.get(CacheKeys.character_list()) || []

    # Map to character IDs as strings
    Enum.map(all_characters, fn char ->
      character_id = Map.get(char, "character_id") || Map.get(char, :character_id)
      if character_id, do: to_string(character_id), else: nil
    end)
    |> Enum.reject(&is_nil/1)
  end

  # Check if any attacker is in the tracked character list
  defp check_attackers_tracked(nil, _), do: false
  defp check_attackers_tracked([], _), do: false

  defp check_attackers_tracked(attackers, tracked_ids) when is_list(attackers) do
    # Extract attacker IDs
    attacker_ids =
      Enum.map(attackers, fn attacker ->
        Map.get(attacker, "character_id")
      end)
      |> Enum.reject(&is_nil/1)
      |> Enum.map(&to_string/1)

    # Check if any attacker is in the tracked list
    Enum.any?(attacker_ids, fn id ->
      Enum.member?(tracked_ids, id)
    end)
  end
end
