defmodule WandererNotifier.Data.Killmail do
  @moduledoc """
  Stub implementation of the Data.Killmail struct for testing.
  Contains only the minimal required functionality.
  """
  @enforce_keys [:killmail_id, :zkb]
  defstruct [:killmail_id, :zkb, :esi_data]

  @doc """
  Creates a new killmail struct with the provided data.
  """
  def new(killmail_id, zkb, esi_data \\ nil) do
    %__MODULE__{
      killmail_id: killmail_id,
      zkb: zkb,
      esi_data: esi_data
    }
  end

  @doc """
  Gets victim information from a killmail.
  """
  def get_victim(%__MODULE__{} = killmail) do
    get_in(killmail.esi_data || %{}, ["victim"])
  end

  @doc """
  Gets attackers information from a killmail.
  """
  def get_attacker(%__MODULE__{} = killmail) do
    get_in(killmail.esi_data || %{}, ["attackers"])
  end

  @doc """
  Gets the system id from a killmail.
  """
  def get_system_id(%__MODULE__{} = killmail) do
    get_in(killmail.esi_data || %{}, ["solar_system_id"])
  end

  @doc """
  Helper function to get a value from the killmail.
  """
  def get(killmail, key, default \\ nil) do
    get_in(killmail.esi_data || %{}, [key]) || default
  end

  @doc """
  Validates that a killmail struct has complete data.
  """
  def validate_complete_data(%__MODULE__{} = _killmail) do
    # Simple stub that always passes validation
    {:ok, :validated}
  end

  @doc """
  Dumps all available data fields in the killmail for debugging.
  """
  def debug_data(%__MODULE__{} = killmail) do
    %{
      killmail_id: killmail.killmail_id,
      zkb_data: killmail.zkb,
      esi_data: killmail.esi_data
    }
  end
end
