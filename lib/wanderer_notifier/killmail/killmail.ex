defmodule WandererNotifier.Killmail.Killmail do
  @moduledoc """
  Data structure for EVE Online killmails.
  Contains information about ship kills, combining data from zKillboard and ESI.
  """
  @enforce_keys [:killmail_id, :zkb]
  defstruct [
    :killmail_id,
    :zkb,
    :esi_data,
    :victim_name,
    :victim_corporation,
    :victim_corp_ticker,
    :victim_alliance,
    :ship_name,
    :system_name,
    :system_id,
    :attackers,
    :value
  ]

  @type killmail_id :: String.t() | integer()
  @type zkb_data :: map()
  @type esi_data :: map() | nil

  @type t :: %__MODULE__{
          killmail_id: killmail_id(),
          zkb: zkb_data(),
          esi_data: esi_data(),
          victim_name: String.t() | nil,
          victim_corporation: String.t() | nil,
          victim_corp_ticker: String.t() | nil,
          victim_alliance: String.t() | nil,
          ship_name: String.t() | nil,
          system_name: String.t() | nil,
          system_id: integer() | nil,
          attackers: list(map()) | nil,
          value: number() | nil
        }

  @doc """
  Implements the Access behaviour to allow accessing the struct like a map.
  This enables syntax like killmail["victim"] to work.
  """
  @behaviour Access

  @impl Access
  @spec fetch(t(), String.t()) :: {:ok, any()} | :error
  def fetch(killmail, key) when key in ["killmail_id", "zkb", "esi_data"] do
    fetch_direct_property(killmail, key)
  end

  def fetch(%__MODULE__{esi_data: esi_data}, _key) when is_nil(esi_data) do
    :error
  end

  def fetch(killmail, key) do
    fetch_from_esi_data(killmail, key)
  end

  # Fetch direct property from the killmail
  defp fetch_direct_property(killmail, key) do
    value =
      case key do
        "killmail_id" -> killmail.killmail_id
        "zkb" -> killmail.zkb
        "esi_data" -> killmail.esi_data
      end

    {:ok, value}
  end

  # Fetch a key from the esi data
  defp fetch_from_esi_data(killmail, key) do
    # Handle special cases for victim and attackers explicitly
    case key do
      "victim" -> Map.fetch(killmail.esi_data, "victim")
      "attackers" -> Map.fetch(killmail.esi_data, "attackers")
      _ -> Map.fetch(killmail.esi_data, key)
    end
  end

  @doc """
  Helper function to get a value from the killmail.
  Not part of the Access behaviour but useful for convenience.
  """
  @spec get(t(), String.t(), any()) :: any()
  def get(killmail, key, default \\ nil) do
    case fetch(killmail, key) do
      {:ok, value} -> value
      :error -> default
    end
  end

  @impl Access
  @spec get_and_update(t(), String.t(), (any() -> {any(), any()})) :: {any(), t()}
  def get_and_update(killmail, key, fun) do
    current_value = get(killmail, key)
    {get_value, new_value} = fun.(current_value)

    new_killmail =
      case key do
        "killmail_id" ->
          %{killmail | killmail_id: new_value}

        "zkb" ->
          %{killmail | zkb: new_value}

        "esi_data" ->
          %{killmail | esi_data: new_value}

        _ ->
          if killmail.esi_data do
            new_esi_data = Map.put(killmail.esi_data, key, new_value)
            %{killmail | esi_data: new_esi_data}
          else
            killmail
          end
      end

    {get_value, new_killmail}
  end

  @impl Access
  @spec pop(t(), String.t()) :: {any(), t()}
  def pop(killmail, key) do
    value = get(killmail, key)

    new_killmail =
      case key do
        "killmail_id" ->
          %{killmail | killmail_id: nil}

        "zkb" ->
          %{killmail | zkb: nil}

        "esi_data" ->
          %{killmail | esi_data: nil}

        _ ->
          if killmail.esi_data do
            new_esi_data = Map.delete(killmail.esi_data, key)
            %{killmail | esi_data: new_esi_data}
          else
            killmail
          end
      end

    {value, new_killmail}
  end

  @doc """
  Creates a new killmail struct with just ID and ZKB data.
  This is used for scenarios where esi data isn't available.
  """
  @spec new(killmail_id(), zkb_data()) :: t()
  def new(killmail_id, zkb) do
    value = get_in(zkb, ["totalValue"]) || 0

    %__MODULE__{
      killmail_id: killmail_id,
      zkb: zkb,
      esi_data: nil,
      value: value,
      system_name: "Unknown",
      system_id: nil
    }
  end

  @doc """
  Creates a new killmail struct with the provided data.
  Overloaded for compatibility with processing/killmail/core.ex
  """
  @spec new(killmail_id(), zkb_data(), map()) :: t()
  def new(kill_id, zkb, enriched_data) do
    value = get_in(zkb, ["totalValue"]) || 0
    system_id = get_in(enriched_data, ["solar_system_id"])

    system_name = get_system_name_with_fallback(enriched_data, system_id)

    %__MODULE__{
      killmail_id: kill_id,
      zkb: zkb,
      esi_data: enriched_data,
      value: value,
      system_name: system_name,
      system_id: system_id
    }
  end

  @doc """
  Creates a killmail struct from a map.

  ## Parameters
  - map: A map containing killmail data

  ## Returns
  A new %WandererNotifier.Killmail.Killmail{} struct
  """
  @spec from_map(map()) :: t()
  def from_map(map) when is_map(map) do
    value = get_in(map, ["zkb", "totalValue"]) || 0
    system_id = get_in(map, ["esi_data", "solar_system_id"])

    system_name = get_system_name_with_fallback(map["esi_data"] || %{}, system_id)

    %__MODULE__{
      killmail_id: map["killmail_id"],
      zkb: map["zkb"],
      esi_data: map["esi_data"],
      value: value,
      system_name: system_name,
      system_id: system_id
    }
  end

  @doc """
  Gets victim information from a killmail.

  ## Parameters
  - killmail: The killmail struct

  ## Returns
  A map with victim data, or nil if not available
  """
  @spec get_victim(t()) :: map() | nil
  def get_victim(killmail) do
    get(killmail, "victim")
  end

  @doc """
  Gets attacker information from a killmail.

  ## Parameters
  - killmail: The killmail struct

  ## Returns
  A list of attacker data maps, or empty list if not available
  """
  @spec get_attacker(t()) :: list(map())
  def get_attacker(killmail) do
    # Return the full list of attackers
    get(killmail, "attackers") || []
  end

  @doc """
  Gets the solar system ID from a killmail.

  ## Parameters
  - killmail: The killmail struct

  ## Returns
  The solar system ID as an integer, or nil if not available
  """
  @spec get_system_id(t()) :: integer() | nil
  def get_system_id(killmail) do
    killmail.system_id || get(killmail, "solar_system_id")
  end

  @doc """
  Gets the victim's ship type ID from a killmail.

  ## Parameters
  - killmail: The killmail struct

  ## Returns
  The ship type ID, or nil if not available
  """
  @spec get_victim_ship_type_id(t()) :: integer() | nil
  def get_victim_ship_type_id(killmail) do
    victim = get_victim(killmail)
    if victim, do: victim["ship_type_id"], else: nil
  end

  @doc """
  Gets the victim's character ID from a killmail.

  ## Parameters
  - killmail: The killmail struct

  ## Returns
  The character ID, or nil if not available
  """
  @spec get_victim_character_id(t()) :: integer() | nil
  def get_victim_character_id(killmail) do
    victim = get_victim(killmail)
    if victim, do: victim["character_id"], else: nil
  end

  @doc """
  Gets the victim's corporation ID from a killmail.

  ## Parameters
  - killmail: The killmail struct

  ## Returns
  The corporation ID, or nil if not available
  """
  @spec get_victim_corporation_id(t()) :: integer() | nil
  def get_victim_corporation_id(killmail) do
    victim = get_victim(killmail)
    if victim, do: victim["corporation_id"], else: nil
  end

  @doc """
  Gets the killmail hash from zKillboard data.

  ## Parameters
  - killmail: The killmail struct

  ## Returns
  The killmail hash, or nil if not available
  """
  @spec get_hash(t()) :: String.t() | nil
  def get_hash(killmail) do
    if killmail.zkb, do: killmail.zkb["hash"], else: nil
  end

  # Private helper functions

  @spec get_system_name_with_fallback(map(), integer() | nil) :: String.t()
  defp get_system_name_with_fallback(enriched_data, system_id) do
    get_in(enriched_data, ["solar_system_name"]) ||
      fetch_system_name_from_cache(system_id) ||
      "Unknown"
  end

  @spec fetch_system_name_from_cache(integer() | nil) :: String.t() | nil
  defp fetch_system_name_from_cache(nil), do: nil
  defp fetch_system_name_from_cache(system_id) do
    WandererNotifier.Killmail.Cache.get_system_name(system_id)
  end
end
