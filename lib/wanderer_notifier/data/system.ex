defmodule WandererNotifier.Data.System do
  @moduledoc """
  Data structure for EVE Online solar systems.
  Contains information about tracked systems from the map.
  """

  @type t :: %__MODULE__{
    system_id: String.t() | integer(),
    system_name: String.t(),
    security_status: float() | nil,
    region_id: String.t() | integer() | nil,
    region_name: String.t() | nil,
    constellation_id: String.t() | integer() | nil,
    constellation_name: String.t() | nil,
    effect: String.t() | nil,
    type: String.t() | nil,
    tracked: boolean(),
    tracked_since: DateTime.t() | nil
  }

  defstruct [
    :system_id,
    :system_name,
    :security_status,
    :region_id,
    :region_name,
    :constellation_id,
    :constellation_name,
    :effect,
    :type,
    tracked: false,
    tracked_since: nil
  ]

  @doc """
  Creates a new system from a map or keyword list.
  """
  def new(attrs) when is_map(attrs) or is_list(attrs) do
    struct(__MODULE__, attrs)
  end

  @doc """
  Converts a system map with string keys to a proper System struct.
  """
  def from_map(map) when is_map(map) do
    attrs = %{
      system_id: map["system_id"] || map[:system_id],
      system_name: map["system_name"] || map[:system_name],
      security_status: map["security_status"] || map[:security_status],
      region_id: map["region_id"] || map[:region_id],
      region_name: map["region_name"] || map[:region_name],
      constellation_id: map["constellation_id"] || map[:constellation_id],
      constellation_name: map["constellation_name"] || map[:constellation_name],
      effect: map["effect"] || map[:effect],
      type: map["type"] || map[:type],
      tracked: map["tracked"] || map[:tracked] || false,
      tracked_since: parse_datetime(map["tracked_since"] || map[:tracked_since])
    }

    struct(__MODULE__, attrs)
  end

  # Helper to safely parse ISO 8601 datetime strings or pass through DateTime objects
  defp parse_datetime(nil), do: nil
  defp parse_datetime(%DateTime{} = dt), do: dt
  defp parse_datetime(datetime_string) when is_binary(datetime_string) do
    case DateTime.from_iso8601(datetime_string) do
      {:ok, datetime, _} -> datetime
      _ -> nil
    end
  end
  defp parse_datetime(_), do: nil
end
