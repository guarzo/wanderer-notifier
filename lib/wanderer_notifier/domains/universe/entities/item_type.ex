defmodule WandererNotifier.Domains.Universe.Entities.ItemType do
  @moduledoc """
  Represents an EVE Online item type with cached data from Fuzzworks.

  This entity contains both ship types and regular items, providing
  fast lookups without requiring ESI API calls.
  """

  @type t :: %__MODULE__{
          type_id: integer(),
          name: String.t(),
          group_id: integer(),
          group_name: String.t() | nil,
          category_id: integer() | nil,
          mass: float() | nil,
          volume: float() | nil,
          capacity: float() | nil,
          portion_size: integer() | nil,
          race_id: integer() | nil,
          base_price: float() | nil,
          published: boolean(),
          market_group_id: integer() | nil,
          icon_id: integer() | nil,
          sound_id: integer() | nil,
          graphic_id: integer() | nil,
          is_ship: boolean()
        }

  defstruct [
    :type_id,
    :name,
    :group_id,
    :group_name,
    :category_id,
    :mass,
    :volume,
    :capacity,
    :portion_size,
    :race_id,
    :base_price,
    :published,
    :market_group_id,
    :icon_id,
    :sound_id,
    :graphic_id,
    :is_ship
  ]

  @doc """
  Creates a new ItemType from CSV data.
  """
  @spec from_csv_data(map(), String.t() | nil, boolean()) :: t()
  def from_csv_data(csv_data, group_name \\ nil, is_ship \\ false) do
    %__MODULE__{
      type_id: csv_data.type_id,
      name: csv_data.name,
      group_id: csv_data.group_id,
      group_name: group_name,
      category_id: Map.get(csv_data, :category_id),
      mass: csv_data.mass,
      volume: csv_data.volume,
      capacity: csv_data.capacity,
      portion_size: csv_data.portion_size,
      race_id: csv_data.race_id,
      base_price: csv_data.base_price,
      published: csv_data.published,
      market_group_id: csv_data.market_group_id,
      icon_id: csv_data.icon_id,
      sound_id: csv_data.sound_id,
      graphic_id: csv_data.graphic_id,
      is_ship: is_ship
    }
  end

  @doc """
  Creates a simplified ItemType from ESI fallback data.
  """
  @spec from_esi_data(integer(), map()) :: t()
  def from_esi_data(type_id, esi_data) do
    %__MODULE__{
      type_id: type_id,
      name: Map.get(esi_data, "name", "Unknown Item"),
      group_id: Map.get(esi_data, "group_id", 0),
      group_name: nil,
      category_id: nil,
      mass: Map.get(esi_data, "mass"),
      volume: Map.get(esi_data, "volume"),
      capacity: Map.get(esi_data, "capacity"),
      portion_size: Map.get(esi_data, "portion_size"),
      race_id: Map.get(esi_data, "race_id"),
      base_price: nil,
      published: Map.get(esi_data, "published", true),
      market_group_id: Map.get(esi_data, "market_group_id"),
      icon_id: Map.get(esi_data, "icon_id"),
      sound_id: Map.get(esi_data, "sound_id"),
      graphic_id: Map.get(esi_data, "graphic_id"),
      is_ship: false
    }
  end

  @doc """
  Returns true if this item type is a ship.
  """
  @spec ship?(t()) :: boolean()
  def ship?(%__MODULE__{is_ship: is_ship}), do: is_ship

  @doc """
  Returns the display name for this item type.
  """
  @spec display_name(t()) :: String.t()
  def display_name(%__MODULE__{name: name}), do: name

  @doc """
  Returns the type ID as a string for API compatibility.
  """
  @spec type_id_string(t()) :: String.t()
  def type_id_string(%__MODULE__{type_id: type_id}), do: to_string(type_id)
end
