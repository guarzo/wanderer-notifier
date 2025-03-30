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

  # Handle field name conversions for common API inconsistencies
  # Using separate function heads for each camelCase key
  def fetch(struct, "typeDescription"), do: fetch_field(struct, :type_description)
  def fetch(struct, "isShattered"), do: fetch_field(struct, :is_shattered)
  def fetch(struct, "systemType"), do: fetch_field(struct, :system_type)
  def fetch(struct, "solarSystemId"), do: fetch_field(struct, :solar_system_id)
  def fetch(struct, "temporaryName"), do: fetch_field(struct, :temporary_name)
  def fetch(struct, "originalName"), do: fetch_field(struct, :original_name)
  def fetch(struct, "classTitle"), do: fetch_field(struct, :class_title)
  def fetch(struct, "effectName"), do: fetch_field(struct, :effect_name)
  def fetch(struct, "regionName"), do: fetch_field(struct, :region_name)
  def fetch(struct, "sunTypeId"), do: fetch_field(struct, :sun_type_id)

  # For any other string key, try to convert to an existing atom
  def fetch(struct, key) when is_binary(key) do
    try_convert_to_atom(struct, key)
  end

  # Helper to fetch a field from the struct
  defp fetch_field(struct, key) do
    Map.fetch(Map.from_struct(struct), key)
  end

  # Helper to try converting a string to an existing atom
  defp try_convert_to_atom(struct, key) do
    atom_key = String.to_existing_atom(key)
    fetch_field(struct, atom_key)
  rescue
    ArgumentError -> :error
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

  # Parse solar_system_id from string or integer
  defp parse_solar_system_id(solar_system_id) do
    case solar_system_id do
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
  end

  # Determine system type and class information
  defp determine_system_type_info(system_type, solar_system_id, map_response, type_description) do
    if system_type == :wormhole do
      class_title =
        map_response["class_title"] || get_in(map_response, ["staticInfo", "class_title"])

      if class_title do
        {class_title, class_title}
      else
        wh_class = determine_wormhole_class(solar_system_id)
        {wh_class, wh_class}
      end
    else
      {type_description,
       map_response["class_title"] || get_in(map_response, ["staticInfo", "class_title"])}
    end
  end

  # Determine the original name for the system
  defp determine_original_name(map_response, system_type, solar_system_id) do
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
  end

  # Determine the temporary name for the system
  defp determine_temporary_name(map_response, original_name) do
    if map_response["temporary_name"] &&
         map_response["temporary_name"] != (original_name || map_response["name"]) do
      map_response["temporary_name"]
    else
      nil
    end
  end

  # Extract statics from map response
  defp extract_statics(map_response) do
    map_response["statics"] || get_in(map_response, ["staticInfo", "statics"]) || []
  end

  # Extract static details from map response
  defp extract_static_details(map_response) do
    map_response["static_details"] || get_in(map_response, ["staticInfo", "static_details"]) || []
  end

  # Extract effect name from map response
  defp extract_effect_name(map_response) do
    map_response["effect_name"] || get_in(map_response, ["staticInfo", "effectName"])
  end

  # Extract region name from map response
  defp extract_region_name(map_response) do
    map_response["region_name"] || get_in(map_response, ["staticInfo", "regionName"])
  end

  # Extract sun type ID from map response
  defp extract_sun_type_id(map_response) do
    map_response["sun_type_id"] || get_in(map_response, ["staticInfo", "sun_type_id"])
  end

  def new(map_response) do
    # Convert solar_system_id to integer if it's a string
    solar_system_id = parse_solar_system_id(map_response["solar_system_id"])

    # Determine the system_type based on the ID
    system_type = determine_system_type(solar_system_id)

    # Get a more specific type description for the system
    type_description = extract_type_description(map_response)

    # For wormhole systems, enhance with class information if available
    {type_description, class_title} =
      determine_system_type_info(system_type, solar_system_id, map_response, type_description)

    # Determine original_name (proper J-name for wormholes)
    original_name = determine_original_name(map_response, system_type, solar_system_id)

    # Use the documented fields from the API
    %__MODULE__{
      id: map_response["id"],
      solar_system_id: solar_system_id,
      name: map_response["name"],
      original_name: original_name,
      # Only set temporary_name if it's different from the original_name
      temporary_name: determine_temporary_name(map_response, original_name),
      locked: map_response["locked"] || false,
      system_type: system_type,
      type_description: type_description,
      # Use the updated class_title
      class_title: class_title,
      # Will be populated if system-static-info is called
      effect_name: extract_effect_name(map_response),
      # Will be populated if system-static-info is called
      statics: extract_statics(map_response),
      # Will be populated if system-static-info is called
      static_details: extract_static_details(map_response),
      # Will be populated if system-static-info is called
      region_name: extract_region_name(map_response),
      is_shattered: extract_is_shattered(map_response),
      sun_type_id: extract_sun_type_id(map_response)
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
    if valid_static_info?(static_info) do
      update_system_with_valid_info(system, static_info)
    else
      system
    end
  end

  # Check if static_info is valid for processing
  defp valid_static_info?(static_info) do
    not is_nil(static_info) and is_map(static_info)
  end

  # Extract fields from static_info with fallbacks
  defp extract_field(static_info, primary_key, alternate_key \\ nil, default \\ nil) do
    cond do
      not is_nil(Map.get(static_info, primary_key)) ->
        Map.get(static_info, primary_key)

      not is_nil(alternate_key) and not is_nil(Map.get(static_info, alternate_key)) ->
        Map.get(static_info, alternate_key)

      true ->
        default
    end
  end

  # Update the system with extracted static information
  defp update_system_with_valid_info(system, static_info) do
    # Extract all necessary fields
    statics = extract_field(static_info, "statics", nil, [])
    static_details = extract_field(static_info, "static_details", nil, [])
    class_title = extract_field(static_info, "class_title")
    effect_name = extract_field(static_info, "effect_name")
    region_name = extract_field(static_info, "region_name")
    type_description = extract_field(static_info, "type_description", "typeDescription")
    is_shattered = extract_field(static_info, "is_shattered", "isShattered")
    sun_type_id = extract_field(static_info, "sun_type_id")

    # Update the system with new information, falling back to existing values
    %__MODULE__{
      system
      | class_title: class_title || system.class_title,
        effect_name: effect_name || system.effect_name,
        statics: statics,
        static_details: static_details,
        region_name: region_name || system.region_name,
        type_description: type_description || system.type_description,
        is_shattered: is_shattered || system.is_shattered,
        sun_type_id: sun_type_id || system.sun_type_id
    }
  end

  @doc """
  Determines if a system is a wormhole based on its ID.

  ## Parameters
    - system: A MapSystem struct

  ## Returns
    - true if the system is a wormhole, false otherwise
  """
  def wormhole?(system) do
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
  # Format display name with explicit pattern matching and guard clauses
  def format_display_name(%{temporary_name: temp_name, original_name: orig_name})
      when is_binary(temp_name) and temp_name != "" and is_binary(orig_name) do
    "#{temp_name} (#{orig_name})"
  end

  def format_display_name(%{original_name: name}) when is_binary(name) and name != "" do
    name
  end

  def format_display_name(%{name: name}) when is_binary(name) do
    name
  end

  def format_display_name(_system) do
    "Unknown System"
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
    cond do
      wormhole_id?(system_id) ->
        classify_wormhole(system_id)

      kspace_id?(system_id) ->
        classify_kspace(system_id)

      system_id < 30_000_000 ->
        "Unknown"

      true ->
        "K-space"
    end
  end

  defp determine_system_type_description(_), do: "Unknown"

  # Check if ID is in wormhole range
  defp wormhole_id?(system_id) do
    system_id >= 31_000_000 and system_id < 32_000_000
  end

  # Check if ID is in k-space range
  defp kspace_id?(system_id) do
    system_id >= 30_000_000 and system_id < 31_000_000
  end

  # Classify wormhole system based on ID range
  defp classify_wormhole(system_id) do
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

  # Classify k-space system (low-sec or null-sec)
  defp classify_kspace(system_id) do
    if rem(system_id, 1000) < 500, do: "Low-sec", else: "Null-sec"
  end

  # Add helper function to determine wormhole class based on ID
  defp determine_wormhole_class(system_id) when is_integer(system_id) do
    # Use the existing classify_wormhole function to avoid duplication
    classify_wormhole(system_id)
  end

  defp determine_wormhole_class(_), do: "Wormhole"

  # Helper function to extract type description with consistent field names
  defp extract_type_description(map_response) do
    map_response["type_description"] ||
      map_response["typeDescription"] ||
      get_in(map_response, ["staticInfo", "type_description"]) ||
      get_in(map_response, ["staticInfo", "typeDescription"]) ||
      get_in(map_response, ["staticInfo", "class_title"]) ||
      if Map.get(map_response, "solar_system_id"),
        do: determine_system_type_description(Map.get(map_response, "solar_system_id")),
        else: "Unknown"
  end

  # Helper function to extract is_shattered status with consistent field names
  defp extract_is_shattered(map_response) do
    Map.get(map_response, "is_shattered") ||
      Map.get(map_response, "isShattered") ||
      get_in(map_response, ["staticInfo", "is_shattered"]) ||
      get_in(map_response, ["staticInfo", "isShattered"]) ||
      false
  end

  @doc """
  Safely gets the statics list for a system, ensuring it's never nil.
  Important for notification formatting.

  ## Parameters
    - system: A MapSystem struct

  ## Returns
    - List of statics, or empty list if none
  """
  def get_statics(system) do
    cond do
      is_list(system.static_details) and length(system.static_details) > 0 ->
        system.static_details

      is_list(system.statics) and length(system.statics) > 0 ->
        system.statics

      system.system_type == :wormhole ->
        # For wormholes with no statics info, provide basic info based on class
        add_default_statics_by_class(system)

      true ->
        []
    end
  end

  # Add default statics based on wormhole class
  defp add_default_statics_by_class(%{class_title: class_title})
       when class_title in ["Class 1", "C1"] do
    ["K162"]
  end

  defp add_default_statics_by_class(%{class_title: class_title})
       when class_title in ["Class 2", "C2"] do
    ["K162"]
  end

  defp add_default_statics_by_class(%{class_title: class_title})
       when class_title in ["Class 3", "C3"] do
    ["K162"]
  end

  defp add_default_statics_by_class(%{class_title: class_title})
       when class_title in ["Class 4", "C4"] do
    ["K162"]
  end

  defp add_default_statics_by_class(%{class_title: class_title})
       when class_title in ["Class 5", "C5"] do
    ["K162"]
  end

  defp add_default_statics_by_class(%{class_title: class_title})
       when class_title in ["Class 6", "C6"] do
    ["K162"]
  end

  defp add_default_statics_by_class(_system) do
    []
  end
end
