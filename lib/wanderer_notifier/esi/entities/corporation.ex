defmodule WandererNotifier.ESI.Entities.Corporation do
  @moduledoc """
  Domain model representing an EVE Online corporation from the ESI API.
  Provides a structured interface for working with corporation data.
  """

  @type t :: %__MODULE__{
          corporation_id: integer(),
          name: String.t(),
          ticker: String.t(),
          member_count: integer(),
          alliance_id: integer() | nil,
          description: String.t() | nil,
          founding_date: DateTime.t() | nil
        }

  defstruct [
    :corporation_id,
    :name,
    :ticker,
    :member_count,
    :alliance_id,
    :description,
    :founding_date
  ]

  @doc """
  Creates a new Corporation struct from raw ESI API data.

  ## Parameters
    - data: The raw corporation data from ESI API

  ## Example
      iex> WandererNotifier.ESI.Entities.Corporation.from_esi_data(%{
      ...>   "corporation_id" => 789012,
      ...>   "name" => "Test Corporation",
      ...>   "ticker" => "TSTC",
      ...>   "member_count" => 100,
      ...>   "alliance_id" => 345678,
      ...>   "description" => "A test corporation",
      ...>   "date_founded" => "2020-01-01T00:00:00Z"
      ...> })
      %WandererNotifier.ESI.Entities.Corporation{
        corporation_id: 789012,
        name: "Test Corporation",
        ticker: "TSTC",
        member_count: 100,
        alliance_id: 345678,
        description: "A test corporation",
        founding_date: ~U[2020-01-01 00:00:00Z]
      }
  """
  @spec from_esi_data(map()) :: t()
  def from_esi_data(data) when is_map(data) do
    founding_date = parse_datetime(Map.get(data, "date_founded"))

    %__MODULE__{
      corporation_id: Map.get(data, "corporation_id"),
      name: Map.get(data, "name"),
      ticker: Map.get(data, "ticker"),
      member_count: Map.get(data, "member_count"),
      alliance_id: Map.get(data, "alliance_id"),
      description: Map.get(data, "description"),
      founding_date: founding_date
    }
  end

  @doc """
  Converts a Corporation struct to a map suitable for storage or serialization.

  ## Parameters
    - corporation: The Corporation struct to convert

  ## Returns
    A map with string keys containing the corporation data.
  """
  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = corporation) do
    %{
      "corporation_id" => corporation.corporation_id,
      "name" => corporation.name,
      "ticker" => corporation.ticker,
      "member_count" => corporation.member_count,
      "alliance_id" => corporation.alliance_id,
      "description" => corporation.description,
      "date_founded" => format_datetime(corporation.founding_date)
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
