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
  - region_id: ID of the system's region
  - triglavian_invasion_status: Invasion status of the system
  - constellation_id: ID of the system's constellation
  - constellation_name: Name of the system's constellation
  """

  @behaviour WandererNotifier.Map.TrackingBehaviour

  alias WandererNotifier.Cache.Keys, as: CacheKeys
  alias WandererNotifier.Cache.Config, as: CacheConfig
  alias WandererNotifier.Cache.Adapter

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

  @impl true
  def is_tracked?(system_id) when is_integer(system_id) do
    system_id_str = Integer.to_string(system_id)
    is_tracked?(system_id_str)
  end

  def is_tracked?(system_id_str) when is_binary(system_id_str) do
    cache_name = CacheConfig.cache_name()

    case Adapter.get(cache_name, CacheKeys.map_systems()) do
      {:ok, systems} when is_list(systems) ->
        result =
          Enum.any?(systems, fn system ->
            id = Map.get(system, :solar_system_id) || Map.get(system, "solar_system_id")
            to_string(id) == system_id_str
          end)

        {:ok, result}

      _ ->
        {:ok, false}
    end
  end

  def is_tracked?(_), do: {:error, :invalid_system_id}

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
    # Define field mappings for extraction
    field_mappings = [
      # Required fields
      {:solar_system_id, ["solar_system_id", :solar_system_id]},
      {:name, ["name", :name]},
      # Optional fields
      {:id, ["id", :id]},
      {:region_name, ["region_name", :region_name]},
      {:statics, ["statics", :statics]},
      {:static_details, ["static_details", :static_details]},
      {:system_class, ["system_class", :system_class]},
      {:class_title, ["class_title", :class_title]},
      {:type_description, ["type_description", :type_description]},
      {:is_shattered, ["is_shattered", :is_shattered]},
      {:effect_name, ["effect_name", :effect_name]},
      {:sun_type_id, ["sun_type_id", :sun_type_id]},
      {:temporary_name, ["temporary_name", :temporary_name]},
      {:original_name, ["original_name", :original_name]},
      {:security_status, ["security_status", :security_status]},
      {:effect_power, ["effect_power", :effect_power]},
      {:region_id, ["region_id", :region_id]},
      {:triglavian_invasion_status, ["triglavian_invasion_status", :triglavian_invasion_status]},
      {:constellation_id, ["constellation_id", :constellation_id]},
      {:constellation_name, ["constellation_name", :constellation_name]},
      {:system_type, ["system_type", :system_type]}
    ]

    # Extract fields using the mappings
    attrs = extract_fields(data, field_mappings)

    # Create the struct
    struct(__MODULE__, attrs)
  end

  # Helper function to extract fields from data using mappings
  defp extract_fields(data, mappings) do
    Enum.reduce(mappings, %{}, fn {field, keys}, acc ->
      case get_first_valid_value(data, keys) do
        nil -> acc
        value -> Map.put(acc, field, value)
      end
    end)
  end

  # Helper function to get the first valid value from a list of possible keys
  defp get_first_valid_value(data, keys) do
    Enum.find_value(keys, fn key ->
      Map.get(data, key)
    end)
  end

  @doc """
  Checks if a system is a wormhole system.

  ## Parameters
    - system: MapSystem struct to check

  ## Returns
    - true if the system is a wormhole system
    - false otherwise
  """
  @spec wormhole?(t()) :: boolean()
  def wormhole?(%__MODULE__{system_type: type}) do
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
  Updates a MapSystem struct with static system information.
  """
  @spec update_with_static_info(t() | map(), map()) :: t()
  def update_with_static_info(system, static_info) when is_map(static_info) do
    valid_fields = get_valid_fields()

    # Convert and normalize inputs
    atomized_static_info = atomize_and_filter_keys(static_info, valid_fields)
    system_map = convert_system_to_map(system, valid_fields)

    # Normalize system_class fields
    system_map = normalize_system_class(system_map)
    atomized_static_info = normalize_system_class(atomized_static_info)

    # Merge and create final struct
    system_map
    |> Map.merge(atomized_static_info)
    |> then(&struct(__MODULE__, &1))
    |> tap(&validate_types/1)
  end

  # Extract valid fields list to separate function
  defp get_valid_fields do
    [
      :id,
      :solar_system_id,
      :name,
      :original_name,
      :type_description,
      :class_title,
      :effect_name,
      :effect_power,
      :region_id,
      :region_name,
      :security_status,
      :sun_type_id,
      :system_class,
      :system_type,
      :temporary_name,
      :triglavian_invasion_status,
      :static_details,
      :statics,
      :is_shattered,
      :locked,
      :constellation_id,
      :constellation_name
    ]
  end

  # Convert system to map and filter keys
  defp convert_system_to_map(system, valid_fields) do
    system_map =
      case system do
        %__MODULE__{} -> Map.from_struct(system)
        %{} -> system
      end

    atomize_and_filter_keys(system_map, valid_fields)
  end

  # Normalize system_class field from integer to string
  defp normalize_system_class(map) do
    case Map.get(map, :system_class) do
      n when is_integer(n) -> Map.put(map, :system_class, Integer.to_string(n))
      _ -> map
    end
  end

  # Helper function to atomize and filter keys
  defp atomize_and_filter_keys(map, valid_fields) do
    Enum.reduce(map, %{}, fn entry, acc ->
      process_map_entry(entry, acc, valid_fields)
    end)
  end

  # Process individual map entries
  defp process_map_entry({k, v}, acc, valid_fields) when is_binary(k) do
    process_binary_key(k, v, acc, valid_fields)
  end

  defp process_map_entry({k, v}, acc, valid_fields) when is_atom(k) do
    process_atom_key(k, v, acc, valid_fields)
  end

  defp process_map_entry(_, acc, _valid_fields), do: acc

  # Process binary keys by converting to atoms
  defp process_binary_key(key, value, acc, valid_fields) do
    try do
      atom = String.to_existing_atom(key)
      if atom in valid_fields, do: Map.put(acc, atom, value), else: acc
    rescue
      ArgumentError -> acc
    end
  end

  # Process atom keys directly
  defp process_atom_key(key, value, acc, valid_fields) do
    if key in valid_fields, do: Map.put(acc, key, value), else: acc
  end

  @doc """
  Validates the types of all fields in a MapSystem struct.
  Raises ArgumentError if any field is the wrong type.
  """
  @spec validate_types(t()) :: :ok
  def validate_types(%__MODULE__{} = system) do
    validate_string_fields(system)
    validate_numeric_fields(system)
    validate_boolean_fields(system)
    validate_list_fields(system)
    validate_optional_fields(system)
    :ok
  end

  # Required string fields
  defp validate_string_fields(system) do
    validate_field(system, :name, &is_binary/1, "string")
  end

  # Optional string fields
  defp validate_optional_fields(system) do
    optional_string_fields = [
      :original_name,
      :type_description,
      :class_title,
      :effect_name,
      :region_name,
      :system_class,
      :temporary_name,
      :triglavian_invasion_status,
      :constellation_name
    ]

    Enum.each(optional_string_fields, fn field ->
      validate_optional_field(system, field, &is_binary/1, "string")
    end)

    # Special case for system_type which can be string, atom, or nil
    validate_optional_field(
      system,
      :system_type,
      &(&1 == nil or is_binary(&1) or is_atom(&1)),
      "string, atom, or nil"
    )
  end

  # Numeric fields
  defp validate_numeric_fields(system) do
    # Integer fields
    integer_fields = [:sun_type_id, :effect_power, :region_id, :constellation_id]

    Enum.each(integer_fields, fn field ->
      validate_optional_field(system, field, &is_integer/1, "integer")
    end)

    # Float fields
    validate_optional_field(system, :security_status, &is_float/1, "float")

    # Fields that can be integer or string
    mixed_id_fields = [:solar_system_id, :id]

    Enum.each(mixed_id_fields, fn field ->
      validate_optional_field(
        system,
        field,
        &(&1 == nil or is_integer(&1) or is_binary(&1)),
        "integer or string"
      )
    end)
  end

  # Boolean fields
  defp validate_boolean_fields(system) do
    boolean_fields = [:is_shattered, :locked]

    Enum.each(boolean_fields, fn field ->
      validate_optional_field(system, field, &is_boolean/1, "boolean")
    end)
  end

  # List fields
  defp validate_list_fields(system) do
    list_fields = [:static_details, :statics]

    Enum.each(list_fields, fn field ->
      validate_optional_field(system, field, &is_list/1, "list")
    end)
  end

  # Helper function for required fields
  defp validate_field(system, field, validator, expected_type) do
    value = Map.get(system, field)

    if !validator.(value) do
      raise ArgumentError, "MapSystem.#{field} must be a #{expected_type}, got: #{inspect(value)}"
    end
  end

  # Helper function for optional fields
  defp validate_optional_field(system, field, validator, expected_type) do
    value = Map.get(system, field)

    if !(value == nil or validator.(value)) do
      raise ArgumentError,
            "MapSystem.#{field} must be a #{expected_type} or nil, got: #{inspect(value)}"
    end
  end

  @doc """
  Gets a system by ID from the cache.
  """
  def get_system(system_id) do
    cache_name = CacheConfig.cache_name()

    case Adapter.get(cache_name, CacheKeys.map_systems()) do
      {:ok, systems} when is_list(systems) ->
        Enum.find(systems, &(&1["id"] == system_id))

      _ ->
        nil
    end
  end

  @doc """
  Gets a system by name from the cache.
  """
  def get_system_by_name(system_name) do
    cache_name = CacheConfig.cache_name()

    case Adapter.get(cache_name, CacheKeys.map_systems()) do
      {:ok, systems} when is_list(systems) ->
        Enum.find(systems, &(&1["name"] == system_name))

      _ ->
        nil
    end
  end

  @doc """
  Checks if a system is in k-space.
  """
  def kspace?(%__MODULE__{system_class: cls}), do: cls in ["K", "HS", "LS", "NS"]
  def kspace?(map), do: Map.get(map, :system_class) in ["K", "HS", "LS", "NS"]
end
