defmodule WandererNotifier.Data.Character do
  @moduledoc """
  Data structure for EVE Online characters.
  Contains information about tracked characters from the map.
  """

  @type t :: %__MODULE__{
    character_id: String.t() | integer(),
    character_name: String.t(),
    corporation_id: String.t() | integer() | nil,
    corporation_name: String.t() | nil,
    alliance_id: String.t() | integer() | nil,
    alliance_name: String.t() | nil,
    tracked: boolean(),
    tracked_since: DateTime.t() | nil,
    last_seen: DateTime.t() | nil
  }

  defstruct [
    :character_id,
    :character_name,
    :corporation_id,
    :corporation_name,
    :alliance_id,
    :alliance_name,
    tracked: false,
    tracked_since: nil,
    last_seen: nil
  ]

  @doc """
  Creates a new character from a map or keyword list.
  """
  def new(attrs) when is_map(attrs) or is_list(attrs) do
    struct(__MODULE__, attrs)
  end

  @doc """
  Converts a character map with string keys to a proper Character struct.
  """
  def from_map(map) when is_map(map) do
    attrs = %{
      character_id: map["character_id"] || map[:character_id],
      character_name: map["character_name"] || map[:character_name],
      corporation_id: map["corporation_id"] || map[:corporation_id],
      corporation_name: map["corporation_name"] || map[:corporation_name],
      alliance_id: map["alliance_id"] || map[:alliance_id],
      alliance_name: map["alliance_name"] || map[:alliance_name],
      tracked: map["tracked"] || map[:tracked] || false,
      tracked_since: parse_datetime(map["tracked_since"] || map[:tracked_since]),
      last_seen: parse_datetime(map["last_seen"] || map[:last_seen])
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
