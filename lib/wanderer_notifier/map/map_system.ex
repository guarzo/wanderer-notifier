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
  - sun_type_id: Type ID of the system's sun
  - id: Alternative identifier for the system
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
    :sun_type_id,
    :id
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
          sun_type_id: integer() | nil,
          id: String.t() | integer() | nil
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
  def new(attrs) when is_map(attrs) do
    system_id = Map.get(attrs, "id")
    name = Map.get(attrs, "name")
    solar_system_id = Map.get(attrs, "solar_system_id")

    if !(is_binary(system_id) and is_binary(name) and not is_nil(solar_system_id)) do
      raise ArgumentError,
            "MapSystem.new/1 expects a map with string 'id', string 'name', and non-nil 'solar_system_id'. Got: #{inspect(attrs)}"
    end

    struct = struct(__MODULE__, %{
      system_id: system_id,
      name: name,
      solar_system_id: solar_system_id,
      original_name: Map.get(attrs, "original_name"),
      system_type: Map.get(attrs, "system_type"),
      type_description: Map.get(attrs, "type_description"),
      class_title: Map.get(attrs, "class_title"),
      effect_name: Map.get(attrs, "effect_name"),
      is_shattered: Map.get(attrs, "is_shattered"),
      locked: Map.get(attrs, "locked"),
      region_name: Map.get(attrs, "region_name"),
      static_details: Map.get(attrs, "static_details"),
      sun_type_id: Map.get(attrs, "sun_type_id"),
      id: system_id
    })
    validate_types(struct)
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
    unless is_nil(system.sun_type_id) or is_integer(system.sun_type_id), do: raise(ArgumentError, "MapSystem.sun_type_id must be an integer or nil, got: #{inspect(system.sun_type_id)}")
    unless is_nil(system.solar_system_id) or is_integer(system.solar_system_id) or is_binary(system.solar_system_id), do: raise(ArgumentError, "MapSystem.solar_system_id must be an integer, string, or nil, got: #{inspect(system.solar_system_id)}")
    unless is_nil(system.id) or is_integer(system.id) or is_binary(system.id), do: raise(ArgumentError, "MapSystem.id must be an integer, string, or nil, got: #{inspect(system.id)}")
    unless is_nil(system.is_shattered) or is_boolean(system.is_shattered), do: raise(ArgumentError, "MapSystem.is_shattered must be a boolean or nil, got: #{inspect(system.is_shattered)}")
    unless is_nil(system.locked) or is_boolean(system.locked), do: raise(ArgumentError, "MapSystem.locked must be a boolean or nil, got: #{inspect(system.locked)}")
    :ok
  end
end
