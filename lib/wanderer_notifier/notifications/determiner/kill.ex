defmodule WandererNotifier.Notifications.Determiner.Kill do
  @moduledoc """
  Determines whether a killmail should trigger a notification.
  """

  require Logger
  alias WandererNotifier.Killmail.Killmail

  @doc """
  Determines if a notification should be sent for a killmail.
  Returns {:ok, %{should_notify: boolean, reason: string | atom}} or {:error, atom}
  """
  def should_notify?(%Killmail{} = killmail) do
    should_notify?(Map.from_struct(killmail))
  end

  def should_notify?(%{"killmail_id" => id} = data) do
    with {:ok, :new} <- check_duplicate(id),
         {:ok, config} <- get_config() do
      check_notification_rules(data, config)
    end
  end

  def should_notify?(%{"solar_system_id" => _} = data) do
    should_notify?(Map.put(data, "killmail_id", System.unique_integer()))
  end

  def should_notify?(%{killmail: killmail, config: config}) do
    # First check for duplicates
    case check_duplicate(killmail["killmail_id"]) do
      {:ok, :new} ->
        # Make tracking checks regardless of notification status
        system_tracked? = tracked_system?(get_in(killmail, ["solar_system_id"]))
        character_tracked? = tracked_character?(get_in(killmail, ["victim", "character_id"]))

        # Then check if notifications are enabled
        case check_notifications_enabled(config) do
          :ok ->
            # If notifications are enabled, proceed with the full check
            with :ok <- check_kill_notifications_enabled(config) do
              check_tracking_status(system_tracked?, character_tracked?, config)
            end

          {:error, reason} ->
            {:error, reason}
        end

      {:ok, %{should_notify: false, reason: reason}} ->
        {:ok, %{should_notify: false, reason: reason}}

      error ->
        error
    end
  end

  def should_notify?(%{esi_data: esi_data} = data) do
    should_notify?(Map.put(data, "killmail_id", esi_data["killmail_id"]))
  end

  defp check_notification_rules(data, config) do
    with :ok <- check_notifications_enabled(config),
         :ok <- check_kill_notifications_enabled(config),
         system_tracked? <- tracked_system?(get_in(data, ["solar_system_id"])),
         character_tracked? <- tracked_character?(get_in(data, ["victim", "character_id"])) do
      check_tracking_status(system_tracked?, character_tracked?, config)
    end
  end

  defp check_notifications_enabled(config) do
    if config.notifications.enabled do
      :ok
    else
      {:error, :notifications_disabled}
    end
  end

  defp check_kill_notifications_enabled(config) do
    if config.notifications.kill.enabled do
      :ok
    else
      {:error, :kill_notifications_disabled}
    end
  end

  defp check_tracking_status(system_tracked?, character_tracked?, config) do
    cond do
      system_tracked? and config.notifications.kill.system.enabled ->
        {:ok, %{should_notify: true}}

      character_tracked? and config.notifications.kill.character.enabled ->
        {:ok, %{should_notify: true}}

      not config.notifications.kill.system.enabled ->
        {:ok, %{should_notify: false, reason: "System notifications disabled"}}

      not config.notifications.kill.character.enabled ->
        {:ok, %{should_notify: false, reason: "Character notifications disabled"}}

      true ->
        {:ok, %{should_notify: false, reason: :no_tracked_entities}}
    end
  end

  defp check_duplicate(id) do
    case Application.get_env(:wanderer_notifier, :deduplication_module).check(:kill, id) do
      {:ok, :duplicate} -> {:ok, %{should_notify: false, reason: "Duplicate kill"}}
      {:ok, :new} -> {:ok, :new}
      error -> error
    end
  end

  defp get_config do
    {:ok, Application.get_env(:wanderer_notifier, :config_module).get_config()}
  end

  @doc """
  Checks if a system is being tracked.
  """
  def tracked_system?(nil), do: false
  def tracked_system?("unknown"), do: false

  def tracked_system?(id) when is_binary(id) do
    check_tracking_status(:system_module, id)
  end

  def tracked_system?(id) do
    check_tracking_status(:system_module, id)
  end

  @doc """
  Checks if a character is being tracked.
  """
  def tracked_character?(nil), do: false

  def tracked_character?(id) do
    check_tracking_status(:character_module, id)
  end

  defp check_tracking_status(module_key, id) do
    case Application.get_env(:wanderer_notifier, module_key).is_tracked?(id) do
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
    victim_tracked = tracked_character?(get_in(esi_data, ["victim", "character_id"]))
    attacker_tracked = any_attacker_tracked?(esi_data["attackers"])
    victim_tracked or attacker_tracked
  end

  def has_tracked_character?(%{"victim" => victim, "attackers" => attackers}) do
    victim_tracked = tracked_character?(get_in(victim, ["character_id"]))
    attacker_tracked = any_attacker_tracked?(attackers)
    victim_tracked or attacker_tracked
  end

  @doc """
  Gets the system ID from a killmail.
  """
  def get_kill_system_id(%Killmail{esi_data: %{"solar_system_id" => id}}), do: id
  def get_kill_system_id(%{"solar_system_id" => id}), do: id
  def get_kill_system_id(_), do: "unknown"

  defp any_attacker_tracked?(attackers) when is_list(attackers) do
    Enum.any?(attackers, fn attacker ->
      tracked_character?(get_in(attacker, ["character_id"]))
    end)
  end

  defp any_attacker_tracked?(_), do: false
end
