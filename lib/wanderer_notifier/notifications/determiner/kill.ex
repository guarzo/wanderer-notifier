defmodule WandererNotifier.Notifications.Determiner.Kill do
  @moduledoc """
  Determines whether a killmail should trigger a notification.
  """

  require Logger
  alias WandererNotifier.Killmail.Killmail

  @doc """
  Determines if a notification should be sent for a killmail.

  ## Parameters
  - killmail: The killmail to check

  ## Returns
  - {:ok, %{should_notify: boolean, reason: String.t() | nil}} on success
  - {:error, reason} on failure
  """
  def should_notify?(%Killmail{} = killmail) do
    # First check if this is a duplicate kill
    case deduplication_module().check(:kill, killmail.killmail_id) do
      {:ok, :duplicate} ->
        {:ok, %{should_notify: false, reason: "Duplicate kill"}}

      {:ok, :new} ->
        # Then check configuration
        config = Application.get_env(:wanderer_notifier, :config_module).get_config()
        handle_config_check(config, killmail)

      {:error, reason} ->
        {:error, reason}
    end
  end

  def should_notify?(%{"killmail_id" => id} = data) do
    killmail = %Killmail{
      killmail_id: id,
      esi_data: data,
      zkb: data["zkb"]
    }

    should_notify?(killmail)
  end

  defp handle_config_check(config, killmail) do
    notifications_enabled = Map.get(config, :notifications_enabled, false)
    kill_notifications_enabled = Map.get(config, :kill_notifications_enabled, false)
    system_notifications_enabled = Map.get(config, :system_notifications_enabled, false)
    character_notifications_enabled = Map.get(config, :character_notifications_enabled, false)

    handle_notifications_status(
      notifications_enabled,
      kill_notifications_enabled,
      system_notifications_enabled,
      character_notifications_enabled,
      killmail,
      config
    )
  end

  defp handle_notifications_status(false, _, _, _, _, _) do
    {:ok, %{should_notify: false, reason: "Notifications disabled"}}
  end

  defp handle_notifications_status(_, false, _, _, _, _) do
    {:ok, %{should_notify: false, reason: "Kill notifications disabled"}}
  end

  defp handle_notifications_status(_, _, false, false, _, _) do
    {:ok, %{should_notify: false, reason: "Both system and character notifications disabled"}}
  end

  defp handle_notifications_status(true, true, system_enabled, character_enabled, killmail, _config) do
    check_tracking_status(killmail, %{
      system_notifications_enabled: system_enabled,
      character_notifications_enabled: character_enabled
    })
  end

  @doc """
  Checks if a system is being tracked.
  """
  def tracked_system?(system_id) do
    case Application.get_env(:wanderer_notifier, :system_module).is_tracked?(system_id) do
      {:ok, result} -> result
      {:error, _} -> false
      false -> false
      true -> true
    end
  end

  @doc """
  Checks if a character is being tracked.
  """
  def tracked_character?(nil), do: false

  def tracked_character?(character_id) do
    case Application.get_env(:wanderer_notifier, :character_module).is_tracked?(character_id) do
      {:ok, result} -> result
      {:error, _} -> false
      false -> false
      true -> true
    end
  end

  @doc """
  Checks if any character in a killmail is being tracked.
  """
  def has_tracked_character?(%Killmail{esi_data: esi_data}) do
    victim_tracked = tracked_character?(esi_data["victim"]["character_id"])
    attacker_tracked = any_attacker_tracked?(esi_data["attackers"])
    victim_tracked or attacker_tracked
  end

  def has_tracked_character?(%{"victim" => victim, "attackers" => attackers}) do
    victim_tracked = tracked_character?(victim["character_id"])
    attacker_tracked = any_attacker_tracked?(attackers)
    victim_tracked or attacker_tracked
  end

  @doc """
  Gets the system ID from a killmail.
  """
  def get_kill_system_id(%Killmail{esi_data: %{"solar_system_id" => id}}), do: id
  def get_kill_system_id(%{"solar_system_id" => id}), do: id
  def get_kill_system_id(_), do: "unknown"

  # Check if character is tracked and character notifications are enabled
  defp check_tracking_status(killmail, %{character_notifications_enabled: true} = config) when is_map(config) do
    if has_tracked_character?(killmail) do
      {:ok, %{should_notify: true, reason: nil}}
    else
      check_system_tracking(killmail, config)
    end
  end

  # Character is tracked but notifications for characters are disabled
  defp check_tracking_status(killmail, %{character_notifications_enabled: false} = config) when is_map(config) do
    if has_tracked_character?(killmail) do
      {:ok, %{should_notify: false, reason: "Character notifications disabled"}}
    else
      check_system_tracking(killmail, config)
    end
  end

  # Check if system is tracked and system notifications are enabled
  defp check_system_tracking(killmail, %{system_notifications_enabled: true}) do
    system_id = get_kill_system_id(killmail)

    if tracked_system?(system_id) do
      {:ok, %{should_notify: true, reason: nil}}
    else
      {:ok, %{should_notify: false, reason: "No tracked systems or characters involved"}}
    end
  end

  # System is tracked but notifications for systems are disabled
  defp check_system_tracking(killmail, %{system_notifications_enabled: false}) do
    system_id = get_kill_system_id(killmail)

    if tracked_system?(system_id) do
      {:ok, %{should_notify: false, reason: "System notifications disabled"}}
    else
      {:ok, %{should_notify: false, reason: "No tracked systems or characters involved"}}
    end
  end

  defp any_attacker_tracked?(attackers) when is_list(attackers) do
    Enum.any?(attackers, fn attacker ->
      tracked_character?(attacker["character_id"])
    end)
  end

  defp any_attacker_tracked?(_), do: false

  defp deduplication_module do
    Application.get_env(:wanderer_notifier, :deduplication_module)
  end
end
