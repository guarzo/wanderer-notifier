defmodule WandererNotifier.ZKill.Killmail do
  @moduledoc """
  Represents a ZKillboard killmail with relevant data.
  Contains both the raw ZKillboard data and helper functions to extract information.
  """

  alias WandererNotifier.ZKill.Parser

  @type t :: %__MODULE__{
          killmail_id: integer(),
          zkb: map(),
          esi_data: map() | nil
        }

  defstruct killmail_id: nil,
            zkb: %{},
            esi_data: nil

  @doc """
  Creates a new killmail struct from the given data.

  ## Parameters
    - kill_id: The killmail ID
    - zkb_data: The ZKill data (zkb field)
    - esi_data: Optional data from ESI API

  ## Returns
    - A new ZKill.Killmail struct
  """
  def new(kill_id, zkb_data, esi_data \\ nil) do
    %__MODULE__{
      killmail_id: kill_id,
      zkb: zkb_data,
      esi_data: esi_data
    }
  end

  @doc """
  Creates a killmail struct from a raw API response.

  ## Parameters
    - data: Raw data from ZKillboard API

  ## Returns
    - {:ok, killmail} on success
    - {:error, reason} on failure
  """
  def from_api(data) when is_map(data) do
    case Parser.parse_killmail(data) do
      {:ok, parsed} ->
        {:ok,
         %__MODULE__{
           killmail_id: Map.get(parsed, "killmail_id"),
           zkb: Map.get(parsed, "zkb", %{}),
           esi_data: Map.get(parsed, "esi_data")
         }}

      error ->
        error
    end
  end

  def from_api(_), do: {:error, :invalid_input}

  @doc """
  Creates a killmail struct from a map.

  ## Parameters
    - map: A map with compatible structure

  ## Returns
    - A new ZKill.Killmail struct
  """
  def from_map(map) when is_map(map) do
    %__MODULE__{
      killmail_id: map["killmail_id"],
      zkb: map["zkb"],
      esi_data: map["esi_data"]
    }
  end

  @doc """
  Gets victim information from a killmail.

  ## Parameters
    - killmail: The killmail struct

  ## Returns
    - A map with victim data, or nil if not available
  """
  def get_victim(killmail) do
    get_in(killmail.esi_data || %{}, ["victim"])
  end

  @doc """
  Gets attacker information from a killmail.

  ## Parameters
    - killmail: The killmail struct

  ## Returns
    - A list of attacker data maps, or empty list if not available
  """
  def get_attackers(killmail) do
    get_in(killmail.esi_data || %{}, ["attackers"]) || []
  end

  @doc """
  Gets the solar system ID from a killmail.

  ## Parameters
    - killmail: The killmail struct

  ## Returns
    - The solar system ID as an integer, or nil if not available
  """
  def get_system_id(killmail) do
    get_in(killmail.esi_data || %{}, ["solar_system_id"])
  end

  @doc """
  Gets the victim's ship type ID from a killmail.

  ## Parameters
    - killmail: The killmail struct

  ## Returns
    - The ship type ID, or nil if not available
  """
  def get_victim_ship_type_id(killmail) do
    victim = get_victim(killmail)
    if victim, do: victim["ship_type_id"], else: nil
  end

  @doc """
  Gets the victim's character ID from a killmail.

  ## Parameters
    - killmail: The killmail struct

  ## Returns
    - The character ID, or nil if not available
  """
  def get_victim_character_id(killmail) do
    victim = get_victim(killmail)
    if victim, do: victim["character_id"], else: nil
  end

  @doc """
  Gets the victim's corporation ID from a killmail.

  ## Parameters
    - killmail: The killmail struct

  ## Returns
    - The corporation ID, or nil if not available
  """
  def get_victim_corporation_id(killmail) do
    victim = get_victim(killmail)
    if victim, do: victim["corporation_id"], else: nil
  end

  @doc """
  Gets the killmail hash from zKillboard data.

  ## Parameters
    - killmail: The killmail struct

  ## Returns
    - The killmail hash, or nil if not available
  """
  def get_hash(killmail) do
    get_in(killmail.zkb || %{}, ["hash"])
  end

  @doc """
  Gets the total ISK value of the killmail.

  ## Parameters
    - killmail: The killmail struct

  ## Returns
    - The total value in ISK as a float, or 0 if not available
  """
  def get_total_value(killmail) do
    get_in(killmail.zkb || %{}, ["totalValue"]) || 0
  end

  @doc """
  Determines if the killmail is from an NPC kill.

  ## Parameters
    - killmail: The killmail struct

  ## Returns
    - true if it is an NPC kill, false otherwise
  """
  def is_npc_kill?(killmail) do
    get_in(killmail.zkb || %{}, ["npc"]) == true
  end
end
