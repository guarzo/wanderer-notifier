defmodule WandererNotifier.Data.MapSystem do
  @moduledoc """
  Struct and functions for managing map system data.

  This module standardizes the representation of solar systems from the map API,
  including proper name formatting and type classification.

  Implements the Access behaviour to allow map-like access with ["key"] syntax.
  """
  @behaviour Access

  @typedoc "Type representing a map system"
  @type t :: %__MODULE__{
          # Map system ID
          id: String.t(),
          # EVE Online system ID
          solar_system_id: integer(),
          # Display name (properly formatted)
          name: String.t(),
          # Original EVE name
          original_name: String.t(),
          # User-assigned nickname
          temporary_name: String.t() | nil,
          # Whether the system is locked
          locked: boolean(),
          # Class designation (e.g., "C3")
          class_title: String.t() | nil,
          # System effect name (if any)
          effect_name: String.t() | nil,
          # Name of the EVE region
          region_name: String.t() | nil,
          # List of static wormhole types with destination info
          statics: list(map()),
          # Detailed information about static wormholes
          static_details: list(map()),
          # :wormhole, :highsec, :lowsec, etc.
          system_type: atom()
        }

  defstruct [
    :id,
    :solar_system_id,
    :name,
    :original_name,
    :temporary_name,
    :locked,
    :class_title,
    :effect_name,
    :region_name,
    :statics,
    :static_details,
    :system_type
  ]

  # Implement Access behaviour methods to allow map-like access

  @doc """
  Implements the Access behaviour fetch method.
  Allows accessing fields with map["key"] syntax.

  ## Examples
      iex> system = %MapSystem{id: "123", name: "Test"}
      iex> system["id"]
      "123"
      iex> system["name"]
      "Test"
  """
  @spec fetch(t(), atom() | String.t()) :: {:ok, any()} | :error
  def fetch(struct, key) when is_atom(key) do
    Map.fetch(Map.from_struct(struct), key)
  end

  def fetch(struct, key) when is_binary(key) do
    # Try to convert to an existing atom to access the struct field directly
    try do
      atom_key = String.to_existing_atom(key)
      Map.fetch(Map.from_struct(struct), atom_key)
    rescue
      ArgumentError -> :error
    end
  end

  @doc """
  Implements the Access behaviour get method.

  ## Examples
      iex> system = %MapSystem{id: "123", name: "Test"}
      iex> system["missing_key", :default]
      :default
  """
  @spec get(t(), atom() | String.t(), any()) :: any()
  def get(struct, key, default \\ nil) do
    case fetch(struct, key) do
      {:ok, value} -> value
      :error -> default
    end
  end

  @doc """
  Implements the Access behaviour get_and_update method.
  Not fully implemented since structs are intended to be immutable.
  """
  @spec get_and_update(t(), any(), (any() -> {any(), any()})) :: {any(), t()}
  def get_and_update(_struct, _key, _fun) do
    raise "get_and_update not implemented for immutable MapSystem struct"
  end

  @doc """
  Implements the Access behaviour pop method.
  Not fully implemented since structs are intended to be immutable.
  """
  @spec pop(t(), any()) :: {any(), t()}
  def pop(_struct, _key) do
    raise "pop not implemented for immutable MapSystem struct"
  end

  @doc """
  Creates a new MapSystem struct from map API response data.

  ## Parameters
    - map_response: Raw API response data for a single system

  ## Returns
    - A new MapSystem struct with standardized fields
  """
  def new(map_response) do
    # Convert solar_system_id to integer if it's a string
    solar_system_id =
      case map_response["solar_system_id"] do
        id when is_binary(id) ->
          case Integer.parse(id) do
            {num, _} -> num
            :error -> nil
          end

        id when is_integer(id) ->
          id

        _ ->
          nil
      end

    # Use the documented fields from the API
    %__MODULE__{
      id: map_response["id"],
      solar_system_id: solar_system_id,
      name: map_response["name"],
      # Try to use explicit original_name if available, otherwise use name
      original_name: map_response["original_name"] || map_response["name"],
      # Only set temporary_name if it's different from the original_name
      temporary_name:
        if(
          map_response["temporary_name"] &&
            map_response["temporary_name"] !=
              (map_response["original_name"] || map_response["name"])
        ) do
          map_response["temporary_name"]
        else
          nil
        end,
      locked: map_response["locked"] || false,
      system_type: determine_system_type(solar_system_id),
      # Will be populated if system-static-info is called
      class_title: nil,
      # Will be populated if system-static-info is called
      effect_name: nil,
      # Will be populated if system-static-info is called
      statics: [],
      # Will be populated if system-static-info is called
      static_details: [],
      # Will be populated if system-static-info is called
      region_name: nil
    }
  end

  @doc """
  Updates a MapSystem with detailed static information.

  ## Parameters
    - system: Existing MapSystem struct
    - static_info: Data from the system-static-info API endpoint

  ## Returns
    - Updated MapSystem struct with additional information
  """
  def update_with_static_info(system, static_info) do
    # Check if static_info is valid
    if is_nil(static_info) or not is_map(static_info) do
      # If static_info is invalid, just return the original system
      system
    else
      # Extract key details from static_info according to documented format
      statics = Map.get(static_info, "statics", [])
      static_details = Map.get(static_info, "static_details", [])
      class_title = Map.get(static_info, "class_title")
      effect_name = Map.get(static_info, "effect_name")
      region_name = Map.get(static_info, "region_name")

      # Update the system with additional information
      %__MODULE__{
        system
        | class_title: class_title || system.class_title,
          effect_name: effect_name || system.effect_name,
          statics: statics,
          static_details: static_details,
          region_name: region_name || system.region_name
      }
    end
  end

  @doc """
  Determines if a system is a wormhole based on its ID.

  ## Parameters
    - system: A MapSystem struct

  ## Returns
    - true if the system is a wormhole, false otherwise
  """
  def is_wormhole?(system) do
    system.system_type == :wormhole
  end

  @doc """
  Formats a system name according to display rules.

  Rules:
  - If temporary_name exists, use it with original_name in parentheses
  - Otherwise, use original_name
  - Fall back to regular name field if needed

  ## Parameters
    - system: A MapSystem struct or map with name fields

  ## Returns
    - Properly formatted system name string
  """
  def format_display_name(system) do
    cond do
      is_map(system) && system.temporary_name && system.temporary_name != "" &&
          system.original_name ->
        "#{system.temporary_name} (#{system.original_name})"

      is_map(system) && system.original_name && system.original_name != "" ->
        system.original_name

      is_map(system) && Map.get(system, :name) ->
        system.name

      true ->
        "Unknown System"
    end
  end

  # Private helper functions

  # Determine system type based on solar_system_id
  defp determine_system_type(id) when is_integer(id) and id >= 31_000_000 and id < 32_000_000,
    do: :wormhole

  defp determine_system_type(_), do: :kspace
end
