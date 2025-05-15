defmodule WandererNotifier.Notifications.Determiner.Kill do
  @moduledoc """
  Determines whether a killmail should trigger a notification.
  """

  require Logger
  alias WandererNotifier.Config
  alias WandererNotifier.Killmail.Killmail

  @doc """
  Determines if a notification should be sent for a killmail.

  ## Parameters
  - killmail: The killmail to check

  ## Returns
  - {:ok, %{should_notify: boolean, reason: String.t() | nil}} on success
  - {:error, reason} on failure
  """
  def should_notify?(killmail) do
    with {:ok, :new} <- deduplication_module().check(:kill, killmail.killmail_id),
         true <- Config.notifications_enabled?() do
      should_notify_for_kill?(killmail)
    else
      {:ok, :duplicate} ->
        {:ok, %{should_notify: false, reason: "Duplicate kill"}}

      false ->
        {:ok, %{should_notify: false, reason: "Notifications disabled"}}

      error ->
        Logger.error("Error in Kill Determiner #{inspect(error)}")
        {:ok, %{should_notify: false, reason: "Error determining notification"}}
    end
  end

  defp should_notify_for_kill?(killmail) do
    system_id = get_kill_system_id(killmail)
    has_tracked_system = tracked_system?(system_id)
    has_tracked_character = has_tracked_character?(killmail.esi_data)
    system_enabled = Config.system_notifications_enabled?()
    character_enabled = Config.character_notifications_enabled?()

    cond do
      not has_tracked_system and not has_tracked_character ->
        {:ok, %{should_notify: false, reason: "Not tracked by any character or system"}}

      not Config.notifications_enabled?() ->
        {:ok, %{should_notify: false, reason: "Notifications disabled"}}

      has_tracked_system and system_enabled ->
        {:ok, %{should_notify: true, reason: nil, type: :system_kill}}

      has_tracked_character and character_enabled ->
        {:ok, %{should_notify: true, reason: nil, type: :character_kill}}

      true ->
        {:ok, %{should_notify: false, reason: "Not tracked or notifications disabled"}}
    end
  end

  @doc """
  Gets the system ID from a killmail.
  """
  def get_kill_system_id(%Killmail{esi_data: nil}), do: "unknown"
  def get_kill_system_id(%Killmail{esi_data: esi_data}), do: esi_data["solar_system_id"]
  def get_kill_system_id(%{"solar_system_id" => system_id}), do: system_id
  def get_kill_system_id(_), do: "unknown"

  @doc """
  Checks if a system is being tracked.
  """
  def tracked_system?(system_id) when is_binary(system_id) do
    case system_module().is_tracked?(system_id) do
      {:ok, true} -> true
      _ -> false
    end
  end

  def tracked_system?(_), do: false

  @doc """
  Checks if a killmail has any tracked characters.
  """
  def has_tracked_character?(nil), do: false

  def has_tracked_character?(%{"victim" => victim, "attackers" => attackers}) do
    victim_tracked = tracked_character?(victim)
    attackers_tracked = Enum.any?(attackers, &tracked_character?/1)
    victim_tracked or attackers_tracked
  end

  def has_tracked_character?(%{"victim" => victim}) do
    tracked_character?(victim)
  end

  def has_tracked_character?(%{"attackers" => attackers}) do
    Enum.any?(attackers, &tracked_character?/1)
  end

  def has_tracked_character?(_), do: false

  @doc """
  Checks if a character is tracked.
  """
  def tracked_character?(nil), do: false
  def tracked_character?(%{"character_id" => nil}), do: false

  def tracked_character?(%{"character_id" => character_id}) when is_binary(character_id) do
    case character_module().is_tracked?(character_id) do
      {:ok, true} -> true
      _ -> false
    end
  end

  def tracked_character?(%{"character_id" => character_id}) when is_integer(character_id) do
    case character_module().is_tracked?(to_string(character_id)) do
      {:ok, true} -> true
      _ -> false
    end
  end

  def tracked_character?(character_id) when is_binary(character_id) do
    case character_module().is_tracked?(character_id) do
      {:ok, true} -> true
      _ -> false
    end
  end

  def tracked_character?(_), do: false

  # Helper functions to get configured modules
  defp system_module, do: Application.get_env(:wanderer_notifier, :system_module)

  defp character_module do
    Application.get_env(
      :wanderer_notifier,
      :character_module,
      WandererNotifier.Map.MapCharacter
    )
  end

  defp deduplication_module do
    Application.get_env(
      :wanderer_notifier,
      :deduplication_module,
      WandererNotifier.Notifications.Helpers.Deduplication
    )
  end
end
