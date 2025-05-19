defmodule WandererNotifier.ESI.Entities.Alliance do
  @moduledoc """
  Domain model representing an EVE Online alliance from the ESI API.
  Provides a structured interface for working with alliance data.
  """

  @type t :: %__MODULE__{
          alliance_id: integer(),
          name: String.t(),
          ticker: String.t(),
          executor_corporation_id: integer() | nil,
          creator_id: integer() | nil,
          creation_date: DateTime.t() | nil,
          faction_id: integer() | nil
        }

  defstruct [
    :alliance_id,
    :name,
    :ticker,
    :executor_corporation_id,
    :creator_id,
    :creation_date,
    :faction_id
  ]

  @doc """
  Creates a new Alliance struct from raw ESI API data.

  ## Parameters
    - data: The raw alliance data from ESI API

  ## Example
      iex> WandererNotifier.ESI.Entities.Alliance.from_esi_data(%{
      ...>   "alliance_id" => 345_678,
      ...>   "name" => "Test Alliance",
      ...>   "ticker" => "TSTA",
      ...>   "executor_corporation_id" => 789_012,
      ...>   "creator_id" => 123_456,
      ...>   "date_founded" => "2020-01-01T00:00:00Z",
      ...>   "faction_id" => 555_555
      ...> })
      %WandererNotifier.ESI.Entities.Alliance{
        alliance_id: 345_678,
        name: "Test Alliance",
        ticker: "TSTA",
        executor_corporation_id: 789_012,
        creator_id: 123_456,
        creation_date: ~U[2020-01-01 00:00:00Z],
        faction_id: 555_555
      }
  """
  @spec from_esi_data(map()) :: t()
  def from_esi_data(data) when is_map(data) do
    creation_date = parse_datetime(Map.get(data, "date_founded"))

    %__MODULE__{
      alliance_id: Map.get(data, "alliance_id"),
      name: Map.get(data, "name"),
      ticker: Map.get(data, "ticker"),
      executor_corporation_id: Map.get(data, "executor_corporation_id"),
      creator_id: Map.get(data, "creator_id"),
      creation_date: creation_date,
      faction_id: Map.get(data, "faction_id")
    }
  end

  @doc """
  Converts an Alliance struct to a map suitable for storage or serialization.

  ## Parameters
    - alliance: The Alliance struct to convert

  ## Returns
    A map with string keys containing the alliance data.
  """
  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = alliance) do
    %{
      "alliance_id" => alliance.alliance_id,
      "name" => alliance.name,
      "ticker" => alliance.ticker,
      "executor_corporation_id" => alliance.executor_corporation_id,
      "creator_id" => alliance.creator_id,
      "date_founded" => format_datetime(alliance.creation_date),
      "faction_id" => alliance.faction_id
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
