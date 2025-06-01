defmodule WandererNotifier.Notifications.Determiner.Kill do
  @moduledoc """
  Determines whether a killmail should trigger a notification.
  """

  require Logger
  alias WandererNotifier.Killmail.Killmail
  alias WandererNotifier.Notifications.Deduplication

  @type notification_result ::
          {:ok, %{should_notify: boolean(), reason: String.t() | atom() | nil}} | {:error, term()}
  @type killmail_data :: Killmail.t() | map()

  @doc """
  Determines if a notification should be sent for a killmail.
  Returns {:ok, %{should_notify: boolean, reason: string | atom}} or {:error, atom}
  """
  @spec should_notify?(killmail_data()) :: notification_result()
  def should_notify?(%Killmail{} = killmail) do
    with killmail_id <- killmail.killmail_id,
         system_id <- Killmail.get_system_id(killmail),
         victim_character_id <- Killmail.get_victim_character_id(killmail) do
      check_killmail_notification(killmail_id, system_id, victim_character_id)
    end
  end

  def should_notify?(%{"killmail_id" => id} = data) do
    with system_id when not is_nil(system_id) <- get_in(data, ["solar_system_id"]),
         victim_character_id <- get_in(data, ["victim", "character_id"]) do
      check_killmail_notification(id, system_id, victim_character_id)
    else
      nil -> {:error, :invalid_system_id}
    end
  end

  def should_notify?(%{"solar_system_id" => system_id} = data) when not is_nil(system_id) do
    with victim_character_id <- get_in(data, ["victim", "character_id"]),
         fake_id <- System.unique_integer() do
      check_killmail_notification(fake_id, system_id, victim_character_id)
    end
  end

  def should_notify?(%{killmail: killmail, config: config}) do
    with killmail_id when not is_nil(killmail_id) <- get_in(killmail, ["killmail_id"]),
         system_id when not is_nil(system_id) <- get_in(killmail, ["solar_system_id"]),
         victim_character_id <- get_in(killmail, ["victim", "character_id"]) do
      check_killmail_notification_with_config(killmail_id, system_id, victim_character_id, config)
    else
      nil -> {:error, :invalid_killmail_data}
    end
  end

  def should_notify?(%{esi_data: esi_data}) do
    with killmail_id when not is_nil(killmail_id) <- esi_data["killmail_id"],
         system_id when not is_nil(system_id) <- get_in(esi_data, ["solar_system_id"]),
         victim_character_id <- get_in(esi_data, ["victim", "character_id"]) do
      check_killmail_notification(killmail_id, system_id, victim_character_id)
    else
      nil -> {:error, :invalid_esi_data}
    end
  end

  # Private function to centralize the notification checking logic
  @spec check_killmail_notification(any(), any(), any()) :: notification_result()
  defp check_killmail_notification(killmail_id, system_id, victim_character_id) do
    with {:ok, :new} <- Deduplication.check(:kill, killmail_id),
         {:ok, config} <- get_config() do
      check_killmail_notification_with_config(
        killmail_id,
        system_id,
        victim_character_id,
        config
      )
    else
      {:ok, :duplicate} -> {:ok, %{should_notify: false, reason: :duplicate}}
      {:error, reason} -> {:error, reason}
    end
  end

  # Private function to check notification rules with provided config
  @spec check_killmail_notification_with_config(any(), any(), any(), keyword()) ::
          notification_result()
  defp check_killmail_notification_with_config(
         _killmail_id,
         system_id,
         victim_character_id,
         config
       ) do
    with :ok <- check_notifications_enabled(config),
         :ok <- check_kill_notifications_enabled(config),
         system_tracked? <- tracked_system?(system_id),
         character_tracked? <- tracked_character?(victim_character_id) do
      check_tracking_status(system_tracked?, character_tracked?, config)
    end
  end

  @spec check_notifications_enabled(keyword()) :: :ok | {:error, :notifications_disabled}
  defp check_notifications_enabled(config) do
    case Keyword.get(config, :notifications_enabled) do
      true -> :ok
      _ -> {:error, :notifications_disabled}
    end
  end

  @spec check_kill_notifications_enabled(keyword()) ::
          :ok | {:error, :kill_notifications_disabled}
  defp check_kill_notifications_enabled(config) do
    case Keyword.get(config, :kill_notifications_enabled) do
      true -> :ok
      _ -> {:error, :kill_notifications_disabled}
    end
  end

  @spec check_tracking_status(boolean(), boolean(), keyword()) :: notification_result()
  defp check_tracking_status(true, _, config) do
    case Keyword.get(config, :system_notifications_enabled) do
      true -> {:ok, %{should_notify: true}}
      _ -> {:ok, %{should_notify: false, reason: "System notifications disabled"}}
    end
  end

  defp check_tracking_status(_, true, config) do
    case Keyword.get(config, :character_notifications_enabled) do
      true -> {:ok, %{should_notify: true}}
      _ -> {:ok, %{should_notify: false, reason: "Character notifications disabled"}}
    end
  end

  defp check_tracking_status(_, _, _config) do
    {:ok, %{should_notify: false, reason: :no_tracked_entities}}
  end

  @spec get_config() :: {:ok, keyword()} | {:error, term()}
  defp get_config do
    case Application.get_env(:wanderer_notifier, :config_module) do
      nil -> {:error, :config_module_not_found}
      module -> {:ok, module.get_config()}
    end
  end

  @doc """
  Checks if a system is being tracked.
  """
  @spec tracked_system?(any()) :: boolean()
  def tracked_system?(nil), do: false
  def tracked_system?("unknown"), do: false
  def tracked_system?(id) when is_binary(id), do: check_tracking_status(:system_module, id)
  def tracked_system?(id), do: check_tracking_status(:system_module, id)

  @doc """
  Checks if a character is being tracked.
  """
  @spec tracked_character?(any()) :: boolean()
  def tracked_character?(nil), do: false
  def tracked_character?(id), do: check_tracking_status(:character_module, id)

  @spec check_tracking_status(atom(), any()) :: boolean()
  defp check_tracking_status(module_key, id) do
    case Application.get_env(:wanderer_notifier, module_key) do
      nil ->
        false

      module ->
        case module.is_tracked?(id) do
          {:ok, result} -> result
          {:error, _} -> false
          false -> false
          true -> true
        end
    end
  end

  @doc """
  Checks if any character in a killmail is being tracked.
  """
  @spec has_tracked_character?(Killmail.t() | map()) :: boolean()
  def has_tracked_character?(%Killmail{} = killmail) do
    with victim_id <- Killmail.get_victim_character_id(killmail),
         attackers <- Killmail.get_attacker(killmail) do
      victim_tracked = tracked_character?(victim_id)
      attacker_tracked = any_attacker_tracked?(attackers)
      victim_tracked or attacker_tracked
    end
  end

  def has_tracked_character?(%{"victim" => victim, "attackers" => attackers}) do
    with victim_id <- get_in(victim, ["character_id"]) do
      victim_tracked = tracked_character?(victim_id)
      attacker_tracked = any_attacker_tracked?(attackers)
      victim_tracked or attacker_tracked
    end
  end

  @doc """
  Gets the system ID from a killmail.
  """
  @spec get_kill_system_id(Killmail.t() | map()) :: any()
  def get_kill_system_id(%Killmail{} = killmail), do: Killmail.get_system_id(killmail)
  def get_kill_system_id(%{"solar_system_id" => id}), do: id
  def get_kill_system_id(_), do: "unknown"

  @spec any_attacker_tracked?(list(map()) | any()) :: boolean()
  defp any_attacker_tracked?(attackers) when is_list(attackers) do
    Enum.any?(attackers, fn attacker ->
      tracked_character?(get_in(attacker, ["character_id"]))
    end)
  end

  defp any_attacker_tracked?(_), do: false
end
