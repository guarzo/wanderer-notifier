defmodule WandererNotifier.Data.System do
  @moduledoc """
  Data structure for EVE Online solar systems.
  Contains information about tracked systems from the map.
  """

  alias WandererNotifier.Data.DateTimeUtil
  alias WandererNotifier.Data.MapUtil

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
  Converts a map with string or atom keys into a System struct.
  """
  @spec from_map(map()) :: t()
  def from_map(map) when is_map(map) do
    %__MODULE__{
      system_id: MapUtil.get_value(map, ["system_id", :system_id]),
      system_name: MapUtil.get_value(map, ["system_name", :system_name]),
      security_status: MapUtil.get_value(map, ["security_status", :security_status]),
      region_id: MapUtil.get_value(map, ["region_id", :region_id]),
      region_name: MapUtil.get_value(map, ["region_name", :region_name]),
      constellation_id: MapUtil.get_value(map, ["constellation_id", :constellation_id]),
      constellation_name: MapUtil.get_value(map, ["constellation_name", :constellation_name]),
      effect: MapUtil.get_value(map, ["effect", :effect]),
      type: MapUtil.get_value(map, ["type", :type]),
      tracked: MapUtil.get_value(map, ["tracked", :tracked]) || false,
      tracked_since: parse_datetime(MapUtil.get_value(map, ["tracked_since", :tracked_since]))
    }
  end

  @doc """
  Safely parses an ISO 8601 datetime string into a DateTime struct.
  Returns nil if the input is nil or invalid.
  """
  @spec parse_datetime(String.t() | DateTime.t() | nil) :: DateTime.t() | nil
  defdelegate parse_datetime(datetime), to: DateTimeUtil
end
