defmodule WandererNotifier.Map.MapSystem do
  @moduledoc """
  Struct and functions for managing map system data.

  This module standardizes the representation of solar systems from the map API,
  including proper name formatting and type classification.

  Implements the Access behaviour to allow map-like access with ["key"] syntax.
  """
  @behaviour Access

  alias WandererNotifier.Logger.Logger, as: AppLogger

  @enforce_keys [:id]
  defstruct [
    :id,
    :name,
    :security_status,
    :region_id,
    :region_name,
    :constellation_id,
    :constellation_name,
    :updated_at,
    :status,
    jumps: 0,
    npc_kills: 0,
    pod_kills: 0,
    ship_kills: 0,
    tracked: false
  ]

  @type t :: %__MODULE__{
          id: integer(),
          name: String.t() | nil,
          security_status: float() | nil,
          region_id: integer() | nil,
          region_name: String.t() | nil,
          constellation_id: integer() | nil,
          constellation_name: String.t() | nil,
          updated_at: DateTime.t() | nil,
          status: atom() | nil,
          jumps: integer(),
          npc_kills: integer(),
          pod_kills: integer(),
          ship_kills: integer(),
          tracked: boolean()
        }

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

  @doc false
  # This function exists for backwards compatibility but is unused in the current codebase
  def parse_solar_system_id(solar_system_id) when is_binary(solar_system_id) do
    String.to_integer(solar_system_id)
  end

  def parse_solar_system_id(solar_system_id) when is_integer(solar_system_id) do
    solar_system_id
  end

  def parse_solar_system_id(_), do: nil

  @doc false
  # These functions exist for backwards compatibility but are unused in the current codebase
  def determine_original_name(map_response, system_type, solar_system_id) do
    # Implementation for legacy system
    cond do
      system_type == "wormhole" ->
        map_response["name"] || "J#{solar_system_id}"

      true ->
        map_response["name"]
    end
  end

  @doc false
  def determine_temporary_name(map_response, original_name) do
    # Implementation for legacy system
    Map.get(map_response, "temporary_name", original_name)
  end

  def new(attrs) when is_map(attrs) or is_list(attrs) do
    # Convert string keys to atoms and build the struct
    struct!(__MODULE__, attrs)
  end

  @doc """
  Returns a human-readable formatted display name for the system.

  ## Examples
      iex> format_display_name(%MapSystem{name: "Jita", system_type: :highsec})
      "Jita (HS)"

      iex> format_display_name(%MapSystem{name: "J123456", system_type: :wormhole, class_title: "C3"})
      "J123456 (C3)"
  """
  def format_display_name(system) do
    type_indicator =
      case system.system_type do
        :wormhole ->
          if system.class_title, do: "(#{system.class_title})", else: "(WH)"

        :highsec ->
          "(HS)"

        :lowsec ->
          "(LS)"

        :nullsec ->
          "(NS)"

        :pochven ->
          "(Pochven)"

        :abyssal ->
          "(Abyssal)"

        _ ->
          ""
      end

    "#{system.name} #{type_indicator}"
  end

  @doc """
  Checks if a system is a wormhole system.

  ## Examples
      iex> is_wormhole?(%MapSystem{system_type: :wormhole})
      true

      iex> is_wormhole?(%MapSystem{system_type: :highsec})
      false
  """
  def is_wormhole?(system) do
    system.system_type == :wormhole
  end

  @doc """
  Gets the class number for a wormhole system.

  Returns an integer class number (1-6) for wormhole systems,
  or nil for non-wormhole systems.

  ## Examples
      iex> get_class_number(%MapSystem{system_type: :wormhole, class_title: "C3"})
      3

      iex> get_class_number(%MapSystem{system_type: :highsec})
      nil
  """
  def get_class_number(system) do
    if is_wormhole?(system) && system.class_title do
      case system.class_title do
        "C" <> class_str ->
          case Integer.parse(class_str) do
            {num, _} -> num
            :error -> nil
          end

        _ ->
          nil
      end
    else
      nil
    end
  end

  @doc """
  Gets information about static wormholes in a system.

  Returns a formatted list of static wormhole types and their destination types.

  ## Examples
      iex> get_statics_info(%MapSystem{statics: [%{"type" => "K162"}, %{"type" => "H900"}]})
      "K162, H900"
  """
  def get_statics_info(system) do
    if is_list(system.statics) do
      static_types =
        Enum.map(system.statics, fn static ->
          static["type"]
        end)
        |> Enum.filter(& &1)
        |> Enum.join(", ")

      if static_types != "", do: static_types, else: nil
    else
      nil
    end
  end

  @doc """
  Gets a detailed description of the system's statics.

  Returns a formatted string with information about each static wormhole,
  including their type and destination.

  ## Examples
      iex> get_statics_description(%MapSystem{static_details: [
      ...>   %{"type" => "K162", "destination" => "Highsec"},
      ...>   %{"type" => "H900", "destination" => "C5 Wormhole"}
      ...> ]})
      "K162 → Highsec, H900 → C5 Wormhole"
  """
  def get_statics_description(system) do
    if is_list(system.static_details) && length(system.static_details) > 0 do
      system.static_details
      |> Enum.map(fn static ->
        type = static["type"]
        destination = static["destination"]

        if type && destination do
          "#{type} → #{destination}"
        else
          nil
        end
      end)
      |> Enum.filter(& &1)
      |> Enum.join(", ")
    else
      nil
    end
  end

  @doc """
  Converts a MapSystem struct to a simplified map representation.

  ## Parameters
  - system: The MapSystem struct to convert
  - include_details: Whether to include detailed information (default: false)

  ## Returns
  A map with selected fields from the MapSystem
  """
  def to_map(system, include_details \\ false) do
    base_map = %{
      "id" => system.id,
      "solar_system_id" => system.solar_system_id,
      "name" => system.name,
      "original_name" => system.original_name,
      "locked" => system.locked,
      "system_type" => Atom.to_string(system.system_type),
      "type_description" => system.type_description,
      "is_shattered" => system.is_shattered
    }

    if include_details do
      Map.merge(base_map, %{
        "temporary_name" => system.temporary_name,
        "class_title" => system.class_title,
        "effect_name" => system.effect_name,
        "region_name" => system.region_name,
        "statics" => system.statics,
        "static_details" => system.static_details,
        "sun_type_id" => system.sun_type_id
      })
    else
      base_map
    end
  end

  @doc """
  Creates a new MapSystem struct from a map of data.

  ## Parameters
    - map: A map containing system data

  ## Returns
    - A new MapSystem struct
  """
  @spec new_from_map(map()) :: t()
  def new_from_map(map) when is_map(map) do
    try do
      # Extract the system ID, which is required
      system_id = extract_id(map)

      # Build the struct directly to avoid issues with missing keys
      %__MODULE__{
        id: system_id,
        name: Map.get(map, "name"),
        security_status: Map.get(map, "security") || Map.get(map, "security_status"),
        region_id: Map.get(map, "region_id"),
        region_name: Map.get(map, "region"),
        constellation_id: Map.get(map, "constellation_id"),
        constellation_name: Map.get(map, "constellation"),
        jumps: Map.get(map, "jumps") || 0,
        npc_kills: Map.get(map, "npc_kills") || 0,
        pod_kills: Map.get(map, "pod_kills") || 0,
        ship_kills: Map.get(map, "ship_kills") || 0,
        status: extract_status(map),
        tracked: Map.get(map, "tracked") || false,
        updated_at: extract_updated_at(map)
      }
    rescue
      e ->
        AppLogger.api_error("[MapSystem] Failed to create system from map",
          error: Exception.message(e),
          data: inspect(map)
        )

        # Reraise to ensure caller handles this properly
        reraise e, __STACKTRACE__
    end
  end

  # Extract the system ID from various possible formats
  defp extract_id(map) do
    cond do
      Map.has_key?(map, "id") -> Map.get(map, "id")
      Map.has_key?(map, "system_id") -> Map.get(map, "system_id")
      true -> raise "System data does not contain an ID field"
    end
  end

  # Extract status from string or default to :unknown
  defp extract_status(map) do
    case Map.get(map, "status") do
      nil -> :unknown
      "clear" -> :clear
      "danger" -> :danger
      "warning" -> :warning
      other when is_binary(other) -> String.to_atom(other)
      other -> other
    end
  end

  # Extract and parse the updated_at timestamp
  defp extract_updated_at(map) do
    case Map.get(map, "updated_at") do
      nil ->
        nil

      timestamp when is_binary(timestamp) ->
        case DateTime.from_iso8601(timestamp) do
          {:ok, dt, _} -> dt
          {:error, _} -> nil
        end

      _ ->
        nil
    end
  end
end
