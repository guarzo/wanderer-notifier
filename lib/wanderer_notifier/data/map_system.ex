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
          system_type: atom(),
          # Type description of the system
          type_description: String.t(),
          # Whether the system is shattered
          is_shattered: boolean(),
          # Sun type ID for the system
          sun_type_id: integer() | nil
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
    :system_type,
    :type_description,
    :is_shattered,
    :sun_type_id
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

    # Determine the system_type based on the ID
    system_type = determine_system_type(solar_system_id)

    # Get a more specific type description for the system
    type_description =
      map_response["type_description"] ||
        get_in(map_response, ["staticInfo", "typeDescription"]) ||
        get_in(map_response, ["staticInfo", "class_title"]) ||
        if solar_system_id,
          do: determine_system_type_description(solar_system_id),
          else: "Unknown"

    # For wormhole systems, enhance with class information if available
    {type_description, class_title} =
      if system_type == :wormhole do
        class_title =
          map_response["class_title"] || get_in(map_response, ["staticInfo", "class_title"])

        if class_title do
          {class_title, class_title}
        else
          {determine_wormhole_class(solar_system_id), determine_wormhole_class(solar_system_id)}
        end
      else
        {type_description,
         map_response["class_title"] || get_in(map_response, ["staticInfo", "class_title"])}
      end

    # Determine original_name (proper J-name for wormholes)
    original_name =
      cond do
        # Use explicit original_name if available
        map_response["original_name"] && map_response["original_name"] != "" ->
          map_response["original_name"]

        # For wormhole systems with numeric IDs, generate J-name
        system_type == :wormhole && is_integer(solar_system_id) ->
          "J#{solar_system_id - 31_000_000}"

        # Otherwise use name
        true ->
          map_response["name"]
      end

    # Use the documented fields from the API
    %__MODULE__{
      id: map_response["id"],
      solar_system_id: solar_system_id,
      name: map_response["name"],
      original_name: original_name,
      # Only set temporary_name if it's different from the original_name
      temporary_name:
        if(
          map_response["temporary_name"] &&
            map_response["temporary_name"] !=
              (original_name || map_response["name"])
        ) do
          map_response["temporary_name"]
        else
          nil
        end,
      locked: map_response["locked"] || false,
      system_type: system_type,
      type_description: type_description,
      # Use the updated class_title
      class_title: class_title,
      # Will be populated if system-static-info is called
      effect_name:
        map_response["effect_name"] || get_in(map_response, ["staticInfo", "effectName"]),
      # Will be populated if system-static-info is called
      statics: map_response["statics"] || get_in(map_response, ["staticInfo", "statics"]) || [],
      # Will be populated if system-static-info is called
      static_details:
        map_response["static_details"] || get_in(map_response, ["staticInfo", "static_details"]) ||
          [],
      # Will be populated if system-static-info is called
      region_name:
        map_response["region_name"] || get_in(map_response, ["staticInfo", "regionName"]),
      is_shattered:
        map_response["is_shattered"] || get_in(map_response, ["staticInfo", "isShattered"]) ||
          false,
      sun_type_id:
        map_response["sun_type_id"] || get_in(map_response, ["staticInfo", "sun_type_id"])
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

      type_description =
        Map.get(static_info, "type_description") || Map.get(static_info, "typeDescription")

      is_shattered = Map.get(static_info, "is_shattered") || Map.get(static_info, "isShattered")

      # Update the system with additional information
      %__MODULE__{
        system
        | class_title: class_title || system.class_title,
          effect_name: effect_name || system.effect_name,
          statics: statics,
          static_details: static_details,
          region_name: region_name || system.region_name,
          type_description: type_description || system.type_description,
          is_shattered: is_shattered || system.is_shattered,
          sun_type_id: Map.get(static_info, "sun_type_id") || system.sun_type_id
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

  @doc """
  Gets the type description of a system.

  ## Parameters
    - system: A MapSystem struct

  ## Returns
    - The type description as a string
  """
  def get_type_description(system) do
    system.type_description
  end

  # Private helper functions

  # Determine system type based on solar_system_id
  defp determine_system_type(id) when is_integer(id) and id >= 31_000_000 and id < 32_000_000,
    do: :wormhole

  defp determine_system_type(_), do: :kspace

  # Helper function to determine system type description based on ID
  defp determine_system_type_description(system_id) when is_integer(system_id) do
    # J-space systems have IDs in the 31xxxxxx range
    cond do
      system_id >= 31_000_000 and system_id < 32_000_000 ->
        # Classify wormhole system based on ID range
        cond do
          system_id < 31_000_006 -> "Thera"
          system_id < 31_001_000 -> "Class 1"
          system_id < 31_002_000 -> "Class 2"
          system_id < 31_003_000 -> "Class 3"
          system_id < 31_004_000 -> "Class 4"
          system_id < 31_005_000 -> "Class 5"
          system_id < 31_006_000 -> "Class 6"
          true -> "Wormhole"
        end

      system_id < 30_000_000 ->
        "Unknown"

      system_id >= 30_000_000 and system_id < 31_000_000 ->
        if rem(system_id, 1000) < 500, do: "Low-sec", else: "Null-sec"

      true ->
        "K-space"
    end
  end

  defp determine_system_type_description(_), do: "Unknown"

  # Add helper function to determine wormhole class based on ID
  defp determine_wormhole_class(system_id) when is_integer(system_id) do
    # J-space systems have IDs in the 31xxxxxx range
    cond do
      system_id < 31_000_006 -> "Thera"
      system_id < 31_001_000 -> "Class 1"
      system_id < 31_002_000 -> "Class 2"
      system_id < 31_003_000 -> "Class 3"
      system_id < 31_004_000 -> "Class 4"
      system_id < 31_005_000 -> "Class 5"
      system_id < 31_006_000 -> "Class 6"
      true -> "Wormhole"
    end
  end

  defp determine_wormhole_class(_), do: "Wormhole"
end
