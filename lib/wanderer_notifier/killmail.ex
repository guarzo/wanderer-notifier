defmodule WandererNotifier.Killmail do
  @moduledoc """
  Proxy module for WandererNotifier.Data.Killmail.
  This module delegates all functionality to WandererNotifier.Data.Killmail.
  """

  # Re-exporting the struct definition for backward compatibility
  @enforce_keys [:killmail_id, :zkb]
  defstruct [:killmail_id, :zkb, :esi_data]

  @type t :: %__MODULE__{
          killmail_id: any(),
          zkb: map(),
          esi_data: map() | nil
        }

  # Implementing Access behaviour by delegating to Data.Killmail
  @behaviour Access

  @impl Access
  def fetch(killmail, key) do
    # Convert to Data.Killmail struct if needed
    data_killmail = convert_to_data_killmail(killmail)
    WandererNotifier.Data.Killmail.fetch(data_killmail, key)
  end

  @impl Access
  def get_and_update(killmail, key, fun) do
    # Convert to Data.Killmail struct if needed
    data_killmail = convert_to_data_killmail(killmail)

    {value, updated_data_killmail} =
      WandererNotifier.Data.Killmail.get_and_update(data_killmail, key, fun)

    # Convert back to original struct type
    updated_killmail = convert_from_data_killmail(updated_data_killmail)
    {value, updated_killmail}
  end

  @impl Access
  def pop(killmail, key) do
    # Convert to Data.Killmail struct if needed
    data_killmail = convert_to_data_killmail(killmail)
    {value, updated_data_killmail} = WandererNotifier.Data.Killmail.pop(data_killmail, key)
    # Convert back to original struct type
    updated_killmail = convert_from_data_killmail(updated_data_killmail)
    {value, updated_killmail}
  end

  # Helper functions for struct conversion
  defp convert_to_data_killmail(%__MODULE__{} = killmail) do
    # If it's already our struct, convert it to Data.Killmail struct
    %WandererNotifier.Data.Killmail{
      killmail_id: killmail.killmail_id,
      zkb: killmail.zkb,
      esi_data: killmail.esi_data
    }
  end

  defp convert_to_data_killmail(other) do
    # If it's already a Data.Killmail struct or something else, return as is
    other
  end

  defp convert_from_data_killmail(%WandererNotifier.Data.Killmail{} = killmail) do
    # Convert Data.Killmail struct back to our struct
    %__MODULE__{
      killmail_id: killmail.killmail_id,
      zkb: killmail.zkb,
      esi_data: killmail.esi_data
    }
  end

  defp convert_from_data_killmail(other) do
    # If it's not a Data.Killmail struct, return as is
    other
  end

  # Delegate all other functions to WandererNotifier.Data.Killmail
  defdelegate new(killmail_id, zkb, esi_data \\ nil), to: WandererNotifier.Data.Killmail
  defdelegate from_map(map), to: WandererNotifier.Data.Killmail
  defdelegate get_victim(killmail), to: WandererNotifier.Data.Killmail
  defdelegate get_attacker(killmail), to: WandererNotifier.Data.Killmail
  defdelegate get_system_id(killmail), to: WandererNotifier.Data.Killmail
end
