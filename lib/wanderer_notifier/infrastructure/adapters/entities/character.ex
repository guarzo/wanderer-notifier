defmodule WandererNotifier.Infrastructure.Adapters.ESI.Entities.Character do
  @moduledoc """
  Domain model representing an EVE Online character from the ESI API.
  Provides a structured interface for working with character data.
  """

  @type t :: %__MODULE__{
          character_id: integer(),
          name: String.t(),
          corporation_id: integer(),
          alliance_id: integer() | nil,
          security_status: float() | nil,
          birthday: DateTime.t() | nil
        }

  defstruct [
    :character_id,
    :name,
    :corporation_id,
    :alliance_id,
    :security_status,
    :birthday
  ]

  @doc """
  Creates a new Character struct from raw ESI API data.

  ## Parameters
    - data: The raw character data from ESI API

  ## Example
      iex> WandererNotifier.Infrastructure.Adapters.ESI.Entities.Character.from_esi_data(%{
      ...>   "character_id" => 123_456,
      ...>   "name" => "Test Character",
      ...>   "corporation_id" => 789_012,
      ...>   "alliance_id" => 345_678,
      ...>   "security_status" => 0.5,
      ...>   "birthday" => "2020-01-01T00:00:00Z"
      ...> })
      %WandererNotifier.Infrastructure.Adapters.ESI.Entities.Character{
        character_id: 123_456,
        name: "Test Character",
        corporation_id: 789_012,
        alliance_id: 345_678,
        security_status: 0.5,
        birthday: ~U[2020-01-01 00:00:00Z]
      }
  """
  @spec from_esi_data(map()) :: t()
  def from_esi_data(data) when is_map(data) do
    birthday = parse_datetime(Map.get(data, "birthday"))

    %__MODULE__{
      character_id: Map.get(data, "character_id"),
      name: Map.get(data, "name"),
      corporation_id: Map.get(data, "corporation_id"),
      alliance_id: Map.get(data, "alliance_id"),
      security_status: Map.get(data, "security_status"),
      birthday: birthday
    }
  end

  @doc """
  Converts a Character struct to a map suitable for storage or serialization.

  ## Parameters
    - character: The Character struct to convert

  ## Returns
    A map with string keys containing the character data.
  """
  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = character) do
    %{
      "character_id" => character.character_id,
      "name" => character.name,
      "corporation_id" => character.corporation_id,
      "alliance_id" => character.alliance_id,
      "security_status" => character.security_status,
      "birthday" => format_datetime(character.birthday)
    }
  end

  # Parses an ISO8601 datetime string into a DateTime struct
  defp parse_datetime(nil), do: nil

  defp parse_datetime(dt_string) when is_binary(dt_string) do
    case DateTime.from_iso8601(dt_string) do
      {:ok, dt, _} -> dt
      _ -> nil
    end
  end

  # Formats a DateTime struct as an ISO8601 string
  defp format_datetime(nil), do: nil

  defp format_datetime(%DateTime{} = dt) do
    DateTime.to_iso8601(dt)
  end
end
