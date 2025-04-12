defmodule WandererNotifier.Killmail.Processing.NotificationDeterminer do
  @moduledoc """
  Determines if a notification should be sent for a killmail.

  This module evaluates various criteria to decide if a killmail should
  trigger a notification, such as:
  - If the kill involves tracked characters or systems
  - If the victim's ship is of sufficient value
  - If deduplication is enabled to prevent notification spam
  """

  alias WandererNotifier.Config.Features
  alias WandererNotifier.Killmail.Core.Data, as: KillmailData
  alias WandererNotifier.Logger.Logger, as: AppLogger

  alias WandererNotifier.Data.Cache.Helpers, as: CacheHelpers
  alias WandererNotifier.Data.Repository

  @doc """
  Determines if a notification should be sent for a killmail.

  ## Parameters
    - killmail: The KillmailData struct to evaluate

  ## Returns
    - {:ok, {true, reason}} if notification should be sent, with reason as string
    - {:ok, {false, reason}} if notification should not be sent, with reason as string
    - {:error, reason} if determination fails
  """
  @spec should_notify?(KillmailData.t()) :: {:ok, {boolean(), String.t()}} | {:error, any()}
  def should_notify?(%KillmailData{} = killmail) do
    # Check if kill notifications are enabled globally
    if not Features.notifications_enabled?() do
      AppLogger.kill_debug("Killmail ##{killmail.killmail_id} - Global notifications disabled")
      {:ok, {false, "Global notifications disabled"}}
    else
      # Perform checks in order of complexity
      # First, check if system notifications are enabled
      determine_by_system_tracking(killmail)
    end
  end

  def should_notify?(other) do
    AppLogger.kill_error("Cannot determine notification for non-KillmailData: #{inspect(other)}")
    {:error, :invalid_data_type}
  end

  # Check system tracking
  defp determine_by_system_tracking(killmail) do
    if not Features.system_notifications_enabled?() do
      AppLogger.kill_debug("Killmail ##{killmail.killmail_id} - System notifications disabled")
      {:ok, {false, "System notifications disabled"}}
    else
      check_system_tracking(killmail)
    end
  end

  # Check if the system is tracked
  defp check_system_tracking(killmail) do
    system_id = killmail.solar_system_id

    case is_system_tracked?(system_id) do
      {:ok, true} ->
        AppLogger.kill_debug("Killmail ##{killmail.killmail_id} - System #{system_id} is tracked")
        {:ok, {true, "System is tracked"}}

      {:ok, false} ->
        AppLogger.kill_debug(
          "Killmail ##{killmail.killmail_id} - System #{system_id} not tracked"
        )

        determine_by_character_tracking(killmail)

      {:error, reason} ->
        AppLogger.kill_error(
          "Error checking system tracking for killmail ##{killmail.killmail_id}: #{inspect(reason)}"
        )

        determine_by_character_tracking(killmail)
    end
  end

  # Check character tracking
  defp determine_by_character_tracking(killmail) do
    if not Features.character_notifications_enabled?() do
      AppLogger.kill_debug("Killmail ##{killmail.killmail_id} - Character notifications disabled")
      {:ok, {false, "Character notifications disabled"}}
    else
      check_character_tracking(killmail)
    end
  end

  # Check if any involved character is tracked
  defp check_character_tracking(killmail) do
    # Check victim first (most common case)
    victim_id = killmail.victim_id

    victim_result =
      if victim_id do
        case is_character_tracked?(victim_id) do
          {:ok, true} -> {:ok, {true, "Victim #{victim_id} is tracked"}}
          _ -> {:ok, false}
        end
      else
        {:ok, false}
      end

    case victim_result do
      {:ok, {true, reason}} ->
        AppLogger.kill_debug("Killmail ##{killmail.killmail_id} - #{reason}")
        {:ok, {true, reason}}

      _ ->
        # Check attackers if victim isn't tracked
        check_attackers_tracking(killmail)
    end
  end

  # Check if any attacker is tracked
  defp check_attackers_tracking(killmail) do
    attackers = killmail.attackers || []

    # Extract character IDs from attackers
    attacker_ids =
      attackers
      |> Enum.map(fn attacker -> Map.get(attacker, "character_id") end)
      |> Enum.reject(&is_nil/1)

    # Check if any attacker is tracked
    if Enum.empty?(attacker_ids) do
      {:ok, {false, "No trackable characters involved"}}
    else
      check_multiple_attackers(attacker_ids, killmail.killmail_id)
    end
  end

  # Check multiple attacker IDs for tracking
  defp check_multiple_attackers(attacker_ids, killmail_id) do
    result =
      Enum.find_value(attacker_ids, fn id ->
        case is_character_tracked?(id) do
          {:ok, true} -> "Attacker #{id} is tracked"
          _ -> nil
        end
      end)

    if result do
      AppLogger.kill_debug("Killmail ##{killmail_id} - #{result}")
      {:ok, {true, result}}
    else
      AppLogger.kill_debug("Killmail ##{killmail_id} - No tracked characters involved")
      {:ok, {false, "No tracked characters involved"}}
    end
  end

  # Helper to check if a character is tracked
  defp is_character_tracked?(character_id) do
    # Check tracking via the repository or cache
    CacheHelpers.is_character_tracked?(character_id)
  end

  # Helper to check if a system is tracked
  defp is_system_tracked?(system_id) do
    # Check tracking via the repository or cache
    CacheHelpers.is_system_tracked?(system_id)
  end

  @doc """
  Helper to check if a killmail is already processed (for deduplication)
  """
  def check_deduplication(kill_id) do
    # Check if killmail is already in database to prevent duplicate notifications
    case Repository.check_killmail_exists_in_database(kill_id) do
      true -> {:ok, {false, "Killmail already processed"}}
      false -> {:ok, {true, "New killmail"}}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Helper to determine the final notification reason when tracking matches
  """
  def determine_reason(true, tracking_reason, true, _dedup_reason) do
    # Both tracking and deduplication passed
    tracking_reason
  end

  def determine_reason(true, _tracking_reason, false, dedup_reason) do
    # Tracking passed but deduplication failed
    dedup_reason
  end

  def determine_reason(false, tracking_reason, _dedup, _) do
    # Tracking failed
    tracking_reason
  end

  @doc """
  Helper to log notification decision
  """
  def log_notification_decision(killmail, should_notify, reason) do
    if should_notify do
      AppLogger.kill_info("Will notify for killmail ##{killmail.killmail_id}: #{reason}")
    else
      AppLogger.kill_debug("Won't notify for killmail ##{killmail.killmail_id}: #{reason}")
    end
  end
end
