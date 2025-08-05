defmodule WandererNotifier.Domains.Killmail.Killmail do
  @moduledoc """
  Simplified data structure for EVE Online killmails.
  Contains flattened information about ship kills from WebSocket data.

  This structure has been optimized for WebSocket-sourced killmails which come
  pre-enriched, eliminating the need for complex transformation logic.
  """

  @enforce_keys [:killmail_id]
  defstruct [
    # Core identifiers
    :killmail_id,
    :system_id,
    :system_name,
    :kill_time,

    # Victim fields (flattened from nested structure)
    :victim_character_id,
    :victim_character_name,
    :victim_corporation_id,
    :victim_corporation_name,
    :victim_alliance_id,
    :victim_alliance_name,
    :victim_ship_type_id,
    :victim_ship_name,
    :damage_taken,

    # Attackers (kept as list for simplicity)
    :attackers,

    # Metadata
    :zkb,
    :value,
    :points,
    :esi_data,
    :enriched?,

    # Items data
    :items_dropped,
    :notable_items
  ]

  @type t :: %__MODULE__{
          killmail_id: String.t(),
          system_id: integer() | nil,
          system_name: String.t(),
          kill_time: String.t() | nil,
          victim_character_id: integer() | nil,
          victim_character_name: String.t() | nil,
          victim_corporation_id: integer() | nil,
          victim_corporation_name: String.t() | nil,
          victim_alliance_id: integer() | nil,
          victim_alliance_name: String.t() | nil,
          victim_ship_type_id: integer() | nil,
          victim_ship_name: String.t() | nil,
          damage_taken: integer() | nil,
          attackers: list(map()) | nil,
          zkb: map() | nil,
          value: number() | nil,
          points: integer() | nil,
          esi_data: map() | nil,
          enriched?: boolean(),
          items_dropped: list(map()) | nil,
          notable_items: list(map()) | nil
        }

  @doc """
  Creates a new killmail struct from WebSocket data.

  This is the primary constructor for pre-enriched WebSocket killmails.
  """
  @spec from_websocket_data(String.t(), integer(), map()) :: t()
  def from_websocket_data(killmail_id, system_id, data) do
    victim = Map.get(data, "victim", %{})
    zkb_data = Map.get(data, "zkb", %{})

    %__MODULE__{
      killmail_id: killmail_id,
      system_id: system_id,
      system_name: get_system_name(system_id),
      kill_time: Map.get(data, "kill_time"),

      # Flattened victim fields
      victim_character_id: Map.get(victim, "character_id"),
      victim_character_name: Map.get(victim, "character_name"),
      victim_corporation_id: Map.get(victim, "corporation_id"),
      victim_corporation_name: Map.get(victim, "corporation_name"),
      victim_alliance_id: Map.get(victim, "alliance_id"),
      victim_alliance_name: Map.get(victim, "alliance_name"),
      victim_ship_type_id: Map.get(victim, "ship_type_id"),
      victim_ship_name: Map.get(victim, "ship_name"),
      damage_taken: Map.get(victim, "damage_taken"),

      # Keep attackers as list
      attackers: Map.get(data, "attackers", []),

      # Metadata
      zkb: zkb_data,
      value: Map.get(zkb_data, "totalValue", 0),
      points: Map.get(zkb_data, "points", 0),
      esi_data: build_esi_data(killmail_id, system_id, data),
      enriched?: true
    }
  end

  @doc """
  Creates a killmail struct from a map.
  """
  @spec from_map(map()) :: t()
  def from_map(map) do
    struct!(__MODULE__, map)
  end

  @doc """
  Gets victim information as a map for backward compatibility.
  """
  @spec get_victim(t()) :: map()
  def get_victim(%__MODULE__{} = killmail) do
    %{
      "character_id" => killmail.victim_character_id,
      "character_name" => killmail.victim_character_name,
      "corporation_id" => killmail.victim_corporation_id,
      "corporation_name" => killmail.victim_corporation_name,
      "alliance_id" => killmail.victim_alliance_id,
      "alliance_name" => killmail.victim_alliance_name,
      "ship_type_id" => killmail.victim_ship_type_id,
      "ship_name" => killmail.victim_ship_name,
      "damage_taken" => killmail.damage_taken
    }
    |> Enum.reject(fn {_k, v} -> is_nil(v) end)
    |> Map.new()
  end

  @doc """
  Gets attacker information.
  """
  @spec get_attacker(t()) :: list(map())
  def get_attacker(%__MODULE__{attackers: attackers}) when is_list(attackers), do: attackers
  def get_attacker(%__MODULE__{}), do: []

  @doc """
  Gets the solar system ID.
  """
  @spec get_system_id(t()) :: integer() | nil
  def get_system_id(%__MODULE__{system_id: nil, esi_data: esi_data}) when is_map(esi_data) do
    get_in(esi_data, ["solar_system_id"])
  end

  def get_system_id(%__MODULE__{system_id: system_id}), do: system_id

  @doc """
  Gets the victim's ship type ID.
  """
  @spec get_victim_ship_type_id(t()) :: integer() | nil
  def get_victim_ship_type_id(%__MODULE__{victim_ship_type_id: ship_type_id}), do: ship_type_id

  @doc """
  Gets the victim's character ID.
  """
  @spec get_victim_character_id(t()) :: integer() | nil
  def get_victim_character_id(%__MODULE__{victim_character_id: character_id}), do: character_id

  @doc """
  Gets the victim's corporation ID.
  """
  @spec get_victim_corporation_id(t()) :: integer() | nil
  def get_victim_corporation_id(%__MODULE__{victim_corporation_id: corp_id}), do: corp_id

  @doc """
  Gets the killmail hash from zKillboard data.
  """
  @spec get_hash(t()) :: String.t() | nil
  def get_hash(%__MODULE__{zkb: zkb}) when is_map(zkb), do: Map.get(zkb, "hash")
  def get_hash(%__MODULE__{}), do: nil

  # Private helper functions

  defp get_system_name(system_id) when is_integer(system_id) do
    WandererNotifier.Domains.Killmail.Enrichment.get_system_name(system_id)
  rescue
    error in [FunctionClauseError, ArgumentError, RuntimeError] ->
      require Logger

      Logger.warning("Failed to get system name for system_id #{system_id}",
        error: inspect(error),
        system_id: system_id
      )

      "Unknown"
  end

  defp get_system_name(_), do: "Unknown"

  defp build_esi_data(killmail_id, system_id, data) do
    %{
      "killmail_id" => killmail_id,
      "solar_system_id" => system_id,
      "killmail_time" => Map.get(data, "kill_time"),
      "victim" => Map.get(data, "victim", %{}),
      "attackers" => Map.get(data, "attackers", [])
    }
  end
end
