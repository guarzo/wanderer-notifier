defmodule WandererNotifier.Notifications.Determiner.Kill do
  @moduledoc """
  Determines whether a killmail should trigger a notification.
  """

  require Logger
  alias WandererNotifier.Killmail.Killmail
  alias WandererNotifier.Config

  @type notification_result ::
          {:ok, %{should_notify: boolean(), reason: String.t() | atom() | nil}} | {:error, term()}
  @type killmail_data :: Killmail.t() | map()

  @doc """
  Determines if a notification should be sent for a killmail.
  Returns {:ok, %{should_notify: boolean, reason: string | atom}} or {:error, atom}
  """
  @spec should_notify?(killmail_data()) :: notification_result()
  def should_notify?(%Killmail{} = killmail) do
    killmail_id = killmail.killmail_id
    system_id = Killmail.get_system_id(killmail)
    victim_character_id = Killmail.get_victim_character_id(killmail)

    check_killmail_notification(killmail_id, system_id, victim_character_id)
  end

  # Handle WebSocket killmail format with atom keys
  def should_notify?(%{killmail_id: id, system_id: system_id, victim: victim} = _data) do
    victim_character_id = Map.get(victim, :character_id)
    check_killmail_notification(id, system_id, victim_character_id)
  end

  def should_notify?(%{"killmail_id" => id} = data) do
    system_id = get_in(data, ["solar_system_id"])
    victim_character_id = get_in(data, ["victim", "character_id"])

    check_killmail_notification(id, system_id, victim_character_id)
  end

  def should_notify?(%{"killID" => id, "killmail" => killmail_data} = _data) do
    # Handle zkillboard format with nested killmail data
    system_id = get_in(killmail_data, ["solar_system_id"])
    victim_character_id = get_in(killmail_data, ["victim", "character_id"])
    killmail_id = get_in(killmail_data, ["killmail_id"]) || id

    check_killmail_notification(killmail_id, system_id, victim_character_id)
  end

  def should_notify?(%{"solar_system_id" => _} = data) do
    # Generate a unique ID for non-killmail data
    fake_id = System.unique_integer()
    system_id = get_in(data, ["solar_system_id"])
    victim_character_id = get_in(data, ["victim", "character_id"])

    check_killmail_notification(fake_id, system_id, victim_character_id)
  end

  def should_notify?(%{killmail: killmail, config: config}) do
    # Extract killmail_id from the nested structure
    killmail_id = get_in(killmail, ["killmail_id"])
    system_id = get_in(killmail, ["solar_system_id"])
    victim_character_id = get_in(killmail, ["victim", "character_id"])

    check_killmail_notification_with_config(killmail_id, system_id, victim_character_id, config)
  end

  def should_notify?(%{esi_data: esi_data} = _data) do
    killmail_id = esi_data["killmail_id"]
    system_id = get_in(esi_data, ["solar_system_id"])
    victim_character_id = get_in(esi_data, ["victim", "character_id"])

    check_killmail_notification(killmail_id, system_id, victim_character_id)
  end

  # Private function to centralize the notification checking logic
  @spec check_killmail_notification(any(), any(), any()) :: notification_result()
  defp check_killmail_notification(killmail_id, system_id, victim_character_id) do
    # No duplicate check here - the pipeline already handles deduplication
    with {:ok, config} <- get_config() do
      check_killmail_notification_with_config(
        killmail_id,
        system_id,
        victim_character_id,
        config
      )
    end
  end

  # Private function to check notification rules with provided config
  @spec check_killmail_notification_with_config(any(), any(), any(), keyword() | map()) ::
          notification_result()
  defp check_killmail_notification_with_config(
         _killmail_id,
         system_id,
         victim_character_id,
         config
       ) do
    case check_notifications_enabled(config) do
      :ok ->
        case check_kill_notifications_enabled(config) do
          :ok ->
            system_tracked? = tracked_system?(system_id)
            character_tracked? = tracked_character?(victim_character_id)
            check_tracking_status(system_tracked?, character_tracked?, config)

          {:error, _} = error ->
            error
        end

      {:error, _} = error ->
        error
    end
  end

  @spec check_notifications_enabled(keyword() | map()) :: :ok | {:error, :notifications_disabled}
  defp check_notifications_enabled(config) when is_list(config) do
    if Keyword.get(config, :notifications_enabled, false),
      do: :ok,
      else: {:error, :notifications_disabled}
  end

  defp check_notifications_enabled(config) when is_map(config) do
    if Map.get(config, :notifications_enabled, false),
      do: :ok,
      else: {:error, :notifications_disabled}
  end

  @spec check_kill_notifications_enabled(keyword() | map()) ::
          :ok | {:error, :kill_notifications_disabled}
  defp check_kill_notifications_enabled(config) when is_list(config) do
    if Keyword.get(config, :kill_notifications_enabled, false),
      do: :ok,
      else: {:error, :kill_notifications_disabled}
  end

  defp check_kill_notifications_enabled(config) when is_map(config) do
    if Map.get(config, :kill_notifications_enabled, false),
      do: :ok,
      else: {:error, :kill_notifications_disabled}
  end

  @spec check_tracking_status(boolean(), boolean(), keyword() | map()) :: notification_result()
  defp check_tracking_status(system_tracked?, character_tracked?, config) do
    case {system_tracked?, character_tracked?} do
      {true, true} -> handle_both_tracked(config)
      {true, false} -> handle_system_only_tracked(config)
      {false, true} -> handle_character_only_tracked(config)
      {false, false} -> {:ok, %{should_notify: false, reason: :no_tracked_entities}}
    end
  end

  defp handle_both_tracked(config) do
    if character_notifications_enabled?(config) do
      {:ok, %{should_notify: true, reason: :both_tracked}}
    else
      handle_system_only_tracked(config)
    end
  end

  defp handle_system_only_tracked(config) do
    if system_notifications_enabled?(config) do
      {:ok, %{should_notify: true, reason: :system_tracked}}
    else
      {:ok, %{should_notify: false, reason: "System notifications disabled"}}
    end
  end

  defp handle_character_only_tracked(config) do
    if character_notifications_enabled?(config) do
      {:ok, %{should_notify: true, reason: :character_tracked}}
    else
      {:ok, %{should_notify: false, reason: "Character notifications disabled"}}
    end
  end

  defp system_notifications_enabled?(config) when is_map(config) do
    Map.get(config, :system_notifications_enabled, true)
  end

  defp system_notifications_enabled?(config) when is_list(config) do
    Keyword.get(config, :system_notifications_enabled, true)
  end

  defp character_notifications_enabled?(config) when is_map(config) do
    Map.get(config, :character_notifications_enabled, true)
  end

  defp character_notifications_enabled?(config) when is_list(config) do
    Keyword.get(config, :character_notifications_enabled, true)
  end

  @spec get_config() :: {:ok, keyword()} | {:error, term()}
  defp get_config do
    {:ok, Config.config_module().get_config()}
  end

  @doc """
  Checks if a system is being tracked.
  """
  @spec tracked_system?(any()) :: boolean()
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
  @spec tracked_character?(any()) :: boolean()
  def tracked_character?(nil), do: false

  def tracked_character?(id) do
    check_tracking_status(:character_module, id)
  end

  @spec check_tracking_status(atom(), any()) :: boolean()
  defp check_tracking_status(module_key, id) do
    module =
      case module_key do
        :character_module -> Config.character_track_module()
        :system_module -> Config.system_track_module()
      end

    # Both modules now return {:ok, boolean()} | {:error, any()}
    case module.is_tracked?(id) do
      {:ok, result} -> result
      {:error, _} -> false
    end
  end

  @doc """
  Checks if any character in a killmail is being tracked.
  """
  @spec has_tracked_character?(Killmail.t() | map()) :: boolean()
  def has_tracked_character?(%Killmail{} = killmail) do
    victim_id = Killmail.get_victim_character_id(killmail)
    attackers = Killmail.get_attacker(killmail)

    victim_tracked = tracked_character?(victim_id)
    attacker_tracked = any_attacker_tracked?(attackers)
    victim_tracked or attacker_tracked
  end

  def has_tracked_character?(%{"victim" => victim, "attackers" => attackers}) do
    victim_tracked = tracked_character?(get_in(victim, ["character_id"]))
    attacker_tracked = any_attacker_tracked?(attackers)
    victim_tracked or attacker_tracked
  end

  # Handle WebSocket killmail format with atom keys
  def has_tracked_character?(%{victim: victim, attackers: attackers}) do
    victim_tracked = tracked_character?(Map.get(victim, :character_id))
    attacker_tracked = any_attacker_tracked?(attackers)
    victim_tracked or attacker_tracked
  end

  @doc """
  Gets the system ID from a killmail.
  """
  @spec get_kill_system_id(Killmail.t() | map()) :: any()
  def get_kill_system_id(%Killmail{} = killmail), do: Killmail.get_system_id(killmail)
  def get_kill_system_id(%{"solar_system_id" => id}), do: id
  def get_kill_system_id(%{system_id: id}), do: id
  def get_kill_system_id(_), do: "unknown"

  @spec any_attacker_tracked?(list(map()) | any()) :: boolean()
  defp any_attacker_tracked?(attackers) when is_list(attackers) do
    Enum.any?(attackers, fn attacker ->
      character_id = get_in(attacker, ["character_id"]) || Map.get(attacker, :character_id)
      tracked_character?(character_id)
    end)
  end

  defp any_attacker_tracked?(_), do: false
end
