defmodule WandererNotifier.Map.MapSystem do
  @moduledoc """
  Struct for representing a system in the map context.
  Provides functionality for system type checking and name formatting.

  ## Fields
  - solar_system_id: Unique identifier for the system
  - name: Current name of the system
  - original_name: Original name before any renaming
  - system_type: Type of system (e.g., wormhole, k-space)
  - type_description: Detailed description of the system type
  - class_title: System class (e.g., C1, C2, etc.)
  - effect_name: Name of the system's effect if any
  - is_shattered: Whether the system is shattered
  - locked: Whether the system is locked
  - region_name: Name of the region containing the system
  - static_details: List of static wormhole connections
  - statics: List of static wormhole connections
  - sun_type_id: Type ID of the system's sun
  - id: Alternative identifier for the system
  - security_status: Security status of the system
  - effect_power: Power of the system's effect
  - region_id: ID of the system's region
  - triglavian_invasion_status: Invasion status of the system
  - constellation_id: ID of the system's constellation
  - constellation_name: Name of the system's constellation
  """

  @enforce_keys [:solar_system_id, :name]
  defstruct [
    :solar_system_id,
    :name,
    :original_name,
    :system_type,
    :type_description,
    :class_title,
    :effect_name,
    :is_shattered,
    :locked,
    :region_name,
    :static_details,
    :statics,
    :system_class,
    :temporary_name,
    :sun_type_id,
    :id,
    :security_status,
    :effect_power,
    :region_id,
    :triglavian_invasion_status,
    :constellation_id,
    :constellation_name
  ]

  @type t :: %__MODULE__{
          solar_system_id: String.t() | integer(),
          name: String.t(),
          original_name: String.t() | nil,
          system_type: String.t() | atom() | nil,
          type_description: String.t() | nil,
          class_title: String.t() | nil,
          effect_name: String.t() | nil,
          is_shattered: boolean() | nil,
          locked: boolean() | nil,
          region_name: String.t() | nil,
          static_details: list() | nil,
          statics: list() | nil,
          system_class: String.t() | integer() | nil,
          temporary_name: String.t() | nil,
          sun_type_id: integer() | nil,
          id: String.t() | integer() | nil,
          security_status: float() | nil,
          effect_power: integer() | nil,
          region_id: integer() | nil,
          triglavian_invasion_status: String.t() | nil,
          constellation_id: integer() | nil,
          constellation_name: String.t() | nil
        }

  @doc """
  Creates a new MapSystem struct from a map of attributes.

  ## Parameters
    - attrs: Map containing system attributes. Must include a string 'id' key.

  ## Returns
    - %MapSystem{} struct

  ## Raises
    - ArgumentError if 'id' key is missing or not a string (enforces correct API format)
  """
  @spec new(map()) :: t()
  def new(data) do
    struct = %__MODULE__{
      id: Map.get(data, :id) || Map.get(data, "id"),
      name: Map.get(data, :name) || Map.get(data, "name"),
      solar_system_id: Map.get(data, :solar_system_id) || Map.get(data, "solar_system_id"),
      region_name: Map.get(data, :region_name) || Map.get(data, "region_name"),
      statics: Map.get(data, :statics) || Map.get(data, "statics"),
      static_details: Map.get(data, :static_details) || Map.get(data, "static_details"),
      system_class: Map.get(data, :system_class) || Map.get(data, "system_class"),
      class_title: Map.get(data, :class_title) || Map.get(data, "class_title"),
      type_description: Map.get(data, :type_description) || Map.get(data, "type_description"),
      is_shattered: Map.get(data, :is_shattered) || Map.get(data, "is_shattered"),
      effect_name: Map.get(data, :effect_name) || Map.get(data, "effect_name"),
      sun_type_id: Map.get(data, :sun_type_id) || Map.get(data, "sun_type_id"),
      temporary_name: Map.get(data, :temporary_name) || Map.get(data, "temporary_name"),
      original_name: Map.get(data, :original_name) || Map.get(data, "original_name"),
      security_status: Map.get(data, :security_status) || Map.get(data, "security_status"),
      effect_power: Map.get(data, :effect_power) || Map.get(data, "effect_power"),
      region_id: Map.get(data, :region_id) || Map.get(data, "region_id"),
      triglavian_invasion_status: Map.get(data, :triglavian_invasion_status) || Map.get(data, "triglavian_invasion_status"),
      constellation_id: Map.get(data, :constellation_id) || Map.get(data, "constellation_id"),
      constellation_name: Map.get(data, :constellation_name) || Map.get(data, "constellation_name")
    }
    struct
  end

  @doc """
  Checks if a system is a wormhole system.

  ## Parameters
    - system: MapSystem struct to check

  ## Returns
    - true if the system is a wormhole system
    - false otherwise
  """
  @spec is_wormhole?(t()) :: boolean()
  def is_wormhole?(%__MODULE__{system_type: type}) do
    type in [:wormhole, "wormhole", "Wormhole"]
  end

  @doc """
  Formats the display name of a system by combining its name, class, and effect.

  ## Parameters
    - system: MapSystem struct to format

  ## Returns
    - String containing the formatted display name
  """
  @spec format_display_name(t()) :: String.t()
  def format_display_name(%__MODULE__{name: name, class_title: class, effect_name: effect}) do
    [name, class, effect]
    |> Enum.reject(&is_nil/1)
    |> Enum.join(" ")
  end

  @doc """
  Updates a MapSystem struct with static info from a map.

  ## Parameters
    - system: MapSystem struct to update
    - static_info: Map containing static information to merge

  ## Returns
    - Updated MapSystem struct
  """
  @spec update_with_static_info(t(), map()) :: t()
  def update_with_static_info(system, static_info) do
    struct = struct(__MODULE__, Map.merge(Map.from_struct(system), static_info))
    validate_types(struct)
    struct
  end

  @doc """
  Validates the types of all fields in a MapSystem struct.
  Raises ArgumentError if any field is the wrong type.
  """
  @spec validate_types(t()) :: :ok
  def validate_types(%__MODULE__{} = system) do
    unless is_binary(system.name), do: raise(ArgumentError, "MapSystem.name must be a string, got: #{inspect(system.name)}")
    unless is_nil(system.original_name) or is_binary(system.original_name), do: raise(ArgumentError, "MapSystem.original_name must be a string or nil, got: #{inspect(system.original_name)}")
    unless is_nil(system.system_type) or is_binary(system.system_type) or is_atom(system.system_type), do: raise(ArgumentError, "MapSystem.system_type must be a string, atom, or nil, got: #{inspect(system.system_type)}")
    unless is_nil(system.type_description) or is_binary(system.type_description), do: raise(ArgumentError, "MapSystem.type_description must be a string or nil, got: #{inspect(system.type_description)}")
    unless is_nil(system.class_title) or is_binary(system.class_title), do: raise(ArgumentError, "MapSystem.class_title must be a string or nil, got: #{inspect(system.class_title)}")
    unless is_nil(system.effect_name) or is_binary(system.effect_name), do: raise(ArgumentError, "MapSystem.effect_name must be a string or nil, got: #{inspect(system.effect_name)}")
    unless is_nil(system.region_name) or is_binary(system.region_name), do: raise(ArgumentError, "MapSystem.region_name must be a string or nil, got: #{inspect(system.region_name)}")
    unless is_nil(system.static_details) or is_list(system.static_details), do: raise(ArgumentError, "MapSystem.static_details must be a list or nil, got: #{inspect(system.static_details)}")
    unless is_nil(system.statics) or is_list(system.statics), do: raise(ArgumentError, "MapSystem.statics must be a list or nil, got: #{inspect(system.statics)}")
    unless is_nil(system.sun_type_id) or is_integer(system.sun_type_id), do: raise(ArgumentError, "MapSystem.sun_type_id must be an integer or nil, got: #{inspect(system.sun_type_id)}")
    unless is_nil(system.solar_system_id) or is_integer(system.solar_system_id) or is_binary(system.solar_system_id), do: raise(ArgumentError, "MapSystem.solar_system_id must be an integer, string, or nil, got: #{inspect(system.solar_system_id)}")
    unless is_nil(system.id) or is_integer(system.id) or is_binary(system.id), do: raise(ArgumentError, "MapSystem.id must be an integer, string, or nil, got: #{inspect(system.id)}")
    unless is_nil(system.is_shattered) or is_boolean(system.is_shattered), do: raise(ArgumentError, "MapSystem.is_shattered must be a boolean or nil, got: #{inspect(system.is_shattered)}")
    unless is_nil(system.locked) or is_boolean(system.locked), do: raise(ArgumentError, "MapSystem.locked must be a boolean or nil, got: #{inspect(system.locked)}")
    unless is_nil(system.system_class) or is_binary(system.system_class), do: raise(ArgumentError, "MapSystem.system_class must be a string or nil, got: #{inspect(system.system_class)}")
    unless is_nil(system.temporary_name) or is_binary(system.temporary_name), do: raise(ArgumentError, "MapSystem.temporary_name must be a string or nil, got: #{inspect(system.temporary_name)}")
    unless is_nil(system.security_status) or is_float(system.security_status), do: raise(ArgumentError, "MapSystem.security_status must be a float or nil, got: #{inspect(system.security_status)}")
    unless is_nil(system.effect_power) or is_integer(system.effect_power), do: raise(ArgumentError, "MapSystem.effect_power must be an integer or nil, got: #{inspect(system.effect_power)}")
    unless is_nil(system.region_id) or is_integer(system.region_id), do: raise(ArgumentError, "MapSystem.region_id must be an integer or nil, got: #{inspect(system.region_id)}")
    unless is_nil(system.triglavian_invasion_status) or is_binary(system.triglavian_invasion_status), do: raise(ArgumentError, "MapSystem.triglavian_invasion_status must be a string or nil, got: #{inspect(system.triglavian_invasion_status)}")
    unless is_nil(system.constellation_id) or is_integer(system.constellation_id), do: raise(ArgumentError, "MapSystem.constellation_id must be an integer or nil, got: #{inspect(system.constellation_id)}")
    unless is_nil(system.constellation_name) or is_binary(system.constellation_name), do: raise(ArgumentError, "MapSystem.constellation_name must be a string or nil, got: #{inspect(system.constellation_name)}")
    :ok
  end
end
