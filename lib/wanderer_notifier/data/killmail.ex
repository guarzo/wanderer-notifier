defmodule WandererNotifier.Data.Killmail do
  @moduledoc """
  Data structure for EVE Online killmails.
  Contains information about ship kills, combining data from zKillboard and ESI.
  """
  @enforce_keys [:killmail_id, :zkb]
  defstruct [:killmail_id, :zkb, :esi_data]

  @type t :: %__MODULE__{
          killmail_id: any(),
          zkb: map(),
          esi_data: map() | nil
        }

  @doc """
  Implements the Access behaviour to allow accessing the struct like a map.
  This enables syntax like killmail["victim"] to work.
  """
  @behaviour Access

  @impl Access
  def fetch(killmail, key) do
    cond do
      direct_killmail_key?(key) ->
        fetch_direct_property(killmail, key)

      has_esi_data?(killmail) ->
        fetch_from_esi_data(killmail, key)

      true ->
        :error
    end
  end

  # Check if the key is a direct property of the killmail
  defp direct_killmail_key?(key) do
    key in ["killmail_id", "zkb", "esi_data"]
  end

  # Check if the killmail has ESI data
  defp has_esi_data?(killmail) do
    not is_nil(killmail.esi_data)
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

  # Fetch a key from the ESI data
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
  def get(killmail, key, default \\ nil) do
    case fetch(killmail, key) do
      {:ok, value} -> value
      :error -> default
    end
  end

  @impl Access
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
  Creates a new killmail struct with the provided data.

  ## Parameters
  - killmail_id: The ID of the killmail
  - zkb: The zKillboard data for the killmail
  - esi_data: Optional ESI data for the killmail

  ## Returns
  A new %WandererNotifier.Data.Killmail{} struct
  """
  def new(killmail_id, zkb, esi_data \\ nil) do
    %__MODULE__{
      killmail_id: killmail_id,
      zkb: zkb,
      esi_data: esi_data
    }
  end

  @doc """
  Creates a killmail struct from a map.

  ## Parameters
  - map: A map containing killmail data

  ## Returns
  A new %WandererNotifier.Data.Killmail{} struct
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
  A map with victim data, or nil if not available
  """
  def get_victim(killmail) do
    get(killmail, "victim")
  end

  @doc """
  Gets attacker information from a killmail.

  ## Parameters
  - killmail: The killmail struct

  ## Returns
  A list of attacker data maps, or nil if not available
  """
  def get_attacker(killmail) do
    # Return the first attacker if there are multiple
    attackers = get(killmail, "attackers")
    if is_list(attackers) && length(attackers) > 0, do: hd(attackers), else: nil
  end

  @doc """
  Gets the solar system ID from a killmail.

  ## Parameters
  - killmail: The killmail struct

  ## Returns
  The solar system ID as an integer, or nil if not available
  """
  def get_system_id(killmail) do
    get(killmail, "solar_system_id")
  end
end
