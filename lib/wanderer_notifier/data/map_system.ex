defmodule WandererNotifier.Data.MapSystem do
  @moduledoc """
  Struct and functions for managing map system data.

  This module standardizes the representation of solar systems from the map API,
  including proper name formatting and type classification.

  Implements the Access behaviour to allow map-like access with ["key"] syntax.
  """
  @behaviour Access

  alias WandererNotifier.Logger.Logger, as: AppLogger

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

  def new(map_response) do
    AppLogger.processor_debug("[MapSystem] Creating new system from response",
      response_keys: Map.keys(map_response),
      has_static_info: not is_nil(get_in(map_response, ["staticInfo"])),
      system_name: map_response["name"],
      system_id: map_response["solar_system_id"]
    )

    # Convert solar_system_id to integer if it's a string
    solar_system_id = parse_solar_system_id(map_response["solar_system_id"])

    AppLogger.processor_debug("[MapSystem] Parsed solar system ID",
      original: map_response["solar_system_id"],
      parsed: solar_system_id
    )

    # Determine the system_type based on the ID
    system_type = determine_system_type(solar_system_id)

    AppLogger.processor_debug("[MapSystem] Determined system type",
      system_id: solar_system_id,
      system_type: system_type
    )

    # Determine original_name (proper J-name for wormholes)
    original_name = determine_original_name(map_response, system_type, solar_system_id)

    AppLogger.processor_debug("[MapSystem] Determined original name",
      original_name: original_name
    )

    # Log the final system details before creation
    AppLogger.processor_debug("[MapSystem] Creating system with details",
      system_id: solar_system_id,
      system_type: system_type,
      original_name: original_name
    )

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
      # These fields will be populated by static info
      type_description: nil,
      class_title: nil,
      effect_name: nil,
      statics: [],
      static_details: [],
      region_name: nil,
      is_shattered: false,
      sun_type_id: nil
    }
  rescue
    e ->
      AppLogger.processor_error("[MapSystem] Error creating system",
        error: Exception.message(e),
        stacktrace: Exception.format_stacktrace(__STACKTRACE__),
        map_response: inspect(map_response, limit: 100)
      )

      reraise e, __STACKTRACE__
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
      AppLogger.processor_warn("[MapSystem] Invalid static info for system", %{
        system_name: system.name,
        static_info: inspect(static_info)
      })

      system
    end
  end

  # Check if static_info is valid for processing
  defp valid_static_info?(static_info) do
    not is_nil(static_info) and is_map(static_info)
  end

  # Update the system with extracted static information
  defp update_system_with_valid_info(system, static_info) do
    # Extract all necessary fields directly from static_info
    statics = Map.get(static_info, "statics", [])
    static_details = Map.get(static_info, "static_details", [])
    class_title = Map.get(static_info, "class_title")
    effect_name = Map.get(static_info, "effect_name")
    region_name = Map.get(static_info, "region_name")
    type_description = Map.get(static_info, "type_description")
    is_shattered = Map.get(static_info, "is_shattered", false)
    sun_type_id = Map.get(static_info, "sun_type_id")

    # Validate required fields
    if is_nil(type_description) do
      AppLogger.processor_error(
        "STATIC INFO ERROR - System: #{system.name} (#{system.id}) - Raw response: #{inspect(static_info, pretty: true, limit: :infinity)}"
      )

      raise "Missing required type_description for system #{system.name} (ID: #{system.id})"
    end

    # Update the system with new information
    updated_system = %__MODULE__{
      system
      | class_title: class_title,
        effect_name: effect_name,
        statics: statics,
        static_details: static_details,
        region_name: region_name,
        type_description: type_description,
        is_shattered: is_shattered,
        sun_type_id: sun_type_id
    }

    AppLogger.processor_debug("[MapSystem] Successfully updated system with static info",
      system_name: system.name,
      type_description: type_description,
      class_title: class_title,
      region_name: region_name
    )

    updated_system
  end

  @doc """
  Determines if a system is a wormhole based on its ID.

  ## Parameters
    - system: A MapSystem struct

  ## Returns
    - true if the system is a wormhole, false otherwise
  """
  def wormhole?(system) do
    AppLogger.processor_debug("[MapSystem] Checking if system is wormhole",
      system_id: system.solar_system_id,
      system_type: system.system_type,
      is_wormhole: system.system_type == :wormhole
    )

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
  defp determine_system_type(id) when is_integer(id) and id >= 31_000_000 and id < 32_000_000 do
    AppLogger.processor_debug("[MapSystem] System ID in wormhole range",
      system_id: id,
      type: :wormhole
    )

    :wormhole
  end

  defp determine_system_type(id) do
    AppLogger.processor_debug("[MapSystem] System ID not in wormhole range",
      system_id: id,
      type: :kspace
    )

    :kspace
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

      true ->
        []
    end
  end
end
