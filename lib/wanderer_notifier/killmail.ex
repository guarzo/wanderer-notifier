defmodule WandererNotifier.Killmail do
  @moduledoc """
  Represents an enriched killmail with both zKill and ESI data.
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
    case key do
      "killmail_id" -> {:ok, killmail.killmail_id}
      "zkb" -> {:ok, killmail.zkb}
      "esi_data" -> {:ok, killmail.esi_data}
      "victim" ->
        if killmail.esi_data do
          Map.fetch(killmail.esi_data, "victim")
        else
          :error
        end
      "attackers" ->
        if killmail.esi_data do
          Map.fetch(killmail.esi_data, "attackers")
        else
          :error
        end
      _ ->
        if killmail.esi_data do
          Map.fetch(killmail.esi_data, key)
        else
          :error
        end
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

    new_killmail = case key do
      "killmail_id" -> %{killmail | killmail_id: new_value}
      "zkb" -> %{killmail | zkb: new_value}
      "esi_data" -> %{killmail | esi_data: new_value}
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

    new_killmail = case key do
      "killmail_id" -> %{killmail | killmail_id: nil}
      "zkb" -> %{killmail | zkb: nil}
      "esi_data" -> %{killmail | esi_data: nil}
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
end
