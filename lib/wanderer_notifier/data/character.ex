defmodule WandererNotifier.Data.Character do
  @moduledoc """
  Data structure for EVE Online characters.
  Contains information about tracked characters from the map.
  """

  alias WandererNotifier.Data.DateTimeUtil
  alias WandererNotifier.Data.MapUtil

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
  @spec from_map(map()) :: t()
  def from_map(map) when is_map(map) do
    %__MODULE__{
      character_id: MapUtil.get_value(map, ["character_id", :character_id]),
      character_name: MapUtil.get_value(map, ["character_name", "name", :character_name, :name]),
      corporation_id: MapUtil.get_value(map, ["corporation_id", :corporation_id]),
      corporation_name: MapUtil.get_value(map, ["corporation_name", :corporation_name]),
      alliance_id: MapUtil.get_value(map, ["alliance_id", :alliance_id]),
      alliance_name: MapUtil.get_value(map, ["alliance_name", :alliance_name]),
      tracked: MapUtil.get_value(map, ["tracked", :tracked]) || false,
      tracked_since: parse_datetime(MapUtil.get_value(map, ["tracked_since", :tracked_since])),
      last_seen: parse_datetime(MapUtil.get_value(map, ["last_seen", :last_seen]))
    }
  end

  @doc """
  Safely parses an ISO 8601 datetime string into a DateTime struct.
  Returns nil if the input is nil or invalid.
  """
  @spec parse_datetime(String.t() | DateTime.t() | nil) :: DateTime.t() | nil
  defdelegate parse_datetime(datetime), to: DateTimeUtil
end
