defmodule WandererNotifier.Notifications.Determiner.Kill do
  @moduledoc """
  Determines whether kill notifications should be sent.
  Contains all kill-related notification decision logic.
  """

  @behaviour WandererNotifier.Notifications.Determiner.KillBehaviour

  alias WandererNotifier.Cache.Keys, as: CacheKeys
  alias WandererNotifier.Killmail.Killmail
  require Logger

  @type result :: {:ok, %{should_notify: boolean(), reason: String.t() | nil}}

  @impl true
  @doc """
  Determines if a notification should be sent for a kill.
  """
  @spec should_notify?(Killmail.t() | map()) :: result
  def should_notify?(raw) do
    try do
      data = extract_kill_data(raw)

      # If we're dealing with a Killmail struct, try to get the system_id directly
      system_id =
        case raw do
          %Killmail{system_id: sid} when not is_nil(sid) ->
            to_string(sid)

          _ ->
            extract_sys_id(data)
        end

      kill_id = extract_kill_id(raw)

      # First check if notifications are enabled
      with true <- notifications_enabled?(),
           true <- tracked?(system_id, data) do
        check_deduplication(kill_id)
      else
        false ->
          {:ok, %{should_notify: false, reason: reason_for_disable(system_id)}}

        _other ->
          {:ok, %{should_notify: false, reason: "Unexpected determiner result"}}
      end
    rescue
      error ->
        Logger.error("Error in Kill Determiner", %{
          error: inspect(error),
          killmail_id: extract_kill_id(raw),
          stack: Exception.format_stacktrace(__STACKTRACE__)
        })

        {:ok, %{should_notify: false, reason: "Error determining notification"}}
    end
  end

  @impl true
  @doc """
  Gets the system ID from a kill.
  """
  @spec get_kill_system_id(Killmail.t() | map() | any()) :: String.t() | nil
  def get_kill_system_id(raw) do
    extract_sys_id(extract_kill_data(raw)) || "unknown"
  end

  @impl true
  @doc """
  Gets the list of tracked characters involved in a kill.
  """
  @spec get_tracked_characters(Killmail.t() | map()) :: [String.t()]
  def get_tracked_characters(raw) do
    data = extract_kill_data(raw)
    victim_id = extract_victim_id(data)
    attacker_ids = extract_attackers(data)

    (List.wrap(victim_id) ++ attacker_ids)
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
    |> Enum.filter(&tracked_character?/1)
  end

  @impl true
  @doc """
  Determines if tracked characters are victims in a kill.
  """
  @spec are_tracked_characters_victims?(Killmail.t() | map(), [String.t()]) :: boolean()
  def are_tracked_characters_victims?(raw, tracked_chars) do
    extract_victim_id(extract_kill_data(raw)) in tracked_chars
  end

  # ——— Internal helpers ————————————————————————————————————————————————

  defp notifications_enabled? do
    case Application.get_env(:wanderer_notifier, :config) do
      nil -> true
      mod -> mod.notifications_enabled?() && mod.system_notifications_enabled?()
    end
  end

  defp tracked?(nil, data), do: has_tracked_character?(data)

  defp tracked?(sys, data) do
    is_tracked_system = tracked_system?(sys)
    has_tracked_chars = has_tracked_character?(data)
    is_tracked_system || has_tracked_chars
  end

  defp reason_for_disable(system_id) do
    cond do
      not notifications_enabled?() -> "Notifications disabled"
      not tracked?(system_id, %{}) -> "Not tracked by any character or system"
    end
  end

  defp check_deduplication(kill_id) do
    case deduplication_module().check(:kill, kill_id) do
      {:ok, :new} -> {:ok, %{should_notify: true, reason: nil}}
      {:ok, :duplicate} -> {:ok, %{should_notify: false, reason: "Duplicate kill"}}
      {:error, _} -> {:ok, %{should_notify: true, reason: nil}}
    end
  end

  # ——— Extractors ——————————————————————————————————————————————————————

  defp extract_kill_data(%Killmail{esi_data: %{} = d}), do: d

  defp extract_kill_data(%Killmail{} = killmail) do
    # If the killmail doesn't have full ESI data, try to get the system_id
    # from the struct itself if it's been set during enrichment
    if Map.has_key?(killmail, :system_id) && killmail.system_id do
      %{"solar_system_id" => killmail.system_id}
    else
      %{}
    end
  end

  defp extract_kill_data(map) when is_map(map), do: map
  defp extract_kill_data(_), do: %{}

  defp extract_sys_id(%{"solar_system_id" => id}) when is_integer(id) or is_binary(id) do
    to_string(id)
  end

  defp extract_sys_id(_) do
    nil
  end

  defp extract_kill_id(%Killmail{killmail_id: id}) when is_binary(id), do: id
  defp extract_kill_id(%Killmail{killmail_id: id}), do: to_string(id)

  defp extract_kill_id(map) when is_map(map) do
    map_id = Map.get(map, "killmail_id") || Map.get(map, :killmail_id)
    if map_id, do: to_string(map_id), else: "unknown"
  end

  defp extract_kill_id(_), do: "unknown"

  defp extract_victim_id(data) do
    data
    |> Map.get("victim", %{})
    |> Map.get("character_id")
    |> maybe_to_string()
  end

  defp extract_attackers(data) do
    data
    |> Map.get("attackers", [])
    |> Enum.map(&Map.get(&1, "character_id"))
    |> Enum.reject(&is_nil/1)
    |> Enum.map(&maybe_to_string/1)
  end

  defp maybe_to_string(nil), do: nil
  defp maybe_to_string(val), do: to_string(val)

  # ——— Tracked checks ——————————————————————————————————————————————————

  @impl true
  def tracked_system?(nil), do: false

  @impl true
  def tracked_system?(id) do
    id_str = to_string(id)

    case cache_repo().get(CacheKeys.map_systems()) do
      {:ok, systems} when is_list(systems) ->
        Enum.any?(systems, fn sys ->
          sys_id = Map.get(sys, :solar_system_id) || Map.get(sys, "solar_system_id")
          to_string(sys_id) == id_str
        end)

      _ ->
        false
    end
  rescue
    error ->
      Logger.error("Error checking tracked systems", %{error: inspect(error), system: id})
      false
  end

  @impl true
  def has_tracked_character?(data) do
    victim_id = extract_victim_id(data)
    attacker_ids = extract_attackers(data)

    ids_to_check =
      ([victim_id] ++ attacker_ids)
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()

    Enum.any?(ids_to_check, &tracked_character?/1)
  end

  @impl true
  def tracked_character?(id) when is_integer(id), do: tracked_character?(to_string(id))

  @impl true
  def tracked_character?(id_str) when is_binary(id_str) do
    # First check direct tracking
    case check_direct_tracking(id_str) do
      true -> true
      _ -> check_character_list(id_str)
    end
  rescue
    error ->
      Logger.error("Error checking tracked character", %{error: inspect(error), char: id_str})
      false
  end

  @impl true
  def tracked_character?(_), do: false

  defp check_direct_tracking(id_str) do
    case cache_repo().get("tracked:character:" <> id_str) do
      {:ok, _char_data} -> true
      _ -> false
    end
  end

  defp check_character_list(id_str) do
    case cache_repo().get(CacheKeys.character_list()) do
      {:ok, chars} when is_list(chars) ->
        Enum.any?(chars, fn c ->
          cid = Map.get(c, :character_id) || Map.get(c, "character_id")
          to_string(cid) == id_str
        end)

      _ ->
        false
    end
  end

  # ——— Runtime dependencies ————————————————————————————————————————————

  defp cache_repo do
    Application.get_env(:wanderer_notifier, :cache_repo, WandererNotifier.Cache.CachexImpl)
    |> then(&if Code.ensure_loaded?(&1), do: &1, else: SafeCache)
  end

  defp deduplication_module do
    Application.get_env(
      :wanderer_notifier,
      :deduplication_module,
      WandererNotifier.Notifications.Helpers.Deduplication
    )
  end

  # ——— SafeCache fallback ——————————————————————————————————————————————

  defmodule SafeCache do
    @moduledoc false
    def get(_), do: {:error, :cache_not_available}
    def put(_, _), do: {:error, :cache_not_available}
    def delete(_), do: {:error, :cache_not_available}
    def exists?(_), do: false
  end
end
