defmodule WandererNotifier.Domains.Tracking.Entities.System do
  @moduledoc """
  Simplified system entity that removes Access behavior complexity.

  Provides essential system tracking functionality without unnecessary
  abstractions or complex behaviors.
  """

  @behaviour WandererNotifier.Map.TrackingBehaviour
  alias WandererNotifier.Infrastructure.Cache
  require Logger

  @type t :: %__MODULE__{
          solar_system_id: String.t() | integer() | nil,
          name: String.t(),
          original_name: String.t() | nil,
          system_type: String.t() | nil,
          type_description: String.t() | nil,
          class_title: String.t() | nil,
          region_name: String.t() | nil,
          security_status: float() | nil,
          is_shattered: boolean() | nil,
          statics: list(String.t()) | nil,
          effect_name: String.t() | nil,
          tracked: boolean()
        }

  defstruct [
    :solar_system_id,
    :name,
    :original_name,
    :system_type,
    :type_description,
    :class_title,
    :region_name,
    :security_status,
    :is_shattered,
    :statics,
    :effect_name,
    tracked: false
  ]

  # ══════════════════════════════════════════════════════════════════════════════
  # Constructor Functions
  # ══════════════════════════════════════════════════════════════════════════════

  @doc """
  Creates a new System struct from attributes map.
  Raises ArgumentError if required fields are missing or invalid.
  """
  @spec new(map()) :: t() | no_return()
  def new(attrs) when is_map(attrs) do
    system_id = validate_system_id(attrs)
    name = validate_name(attrs)

    %__MODULE__{
      solar_system_id: system_id,
      name: name,
      original_name: extract_simple_field(attrs, [:original_name]),
      system_type: extract_simple_field(attrs, [:system_type]),
      type_description: extract_simple_field(attrs, [:type_description]),
      class_title: extract_class_title_field(attrs),
      region_name: extract_simple_field(attrs, [:region_name]),
      security_status: extract_security_status_field(attrs),
      is_shattered: extract_simple_field(attrs, [:is_shattered]),
      statics: extract_simple_field(attrs, [:statics]),
      effect_name: extract_simple_field(attrs, [:effect_name]),
      tracked: extract_tracked_field(attrs)
    }
  end

  # Validation helpers for new/1
  defp validate_system_id(attrs) do
    system_id = extract_system_id(attrs)

    if is_nil(system_id) do
      raise ArgumentError, "System must have solar_system_id"
    end

    system_id
  end

  defp validate_name(attrs) do
    name = extract_simple_field(attrs, [:name, :id])

    if is_nil(name) or name == "" do
      raise ArgumentError, "System must have a name"
    end

    name
  end

  # Field extraction helpers for new/1
  defp extract_simple_field(attrs, keys) do
    Enum.find_value(keys, fn key ->
      attrs[Atom.to_string(key)] || attrs[key]
    end)
  end

  defp extract_class_title_field(attrs) do
    extract_simple_field(attrs, [:class_title, :system_class])
  end

  defp extract_security_status_field(attrs) do
    value = extract_simple_field(attrs, [:security_status])
    parse_float(value)
  end

  defp extract_tracked_field(attrs) do
    extract_simple_field(attrs, [:tracked]) || false
  end

  # Helper functions for system creation
  defp extract_system_id(attrs) do
    system_id = attrs["solar_system_id"] || attrs[:solar_system_id] || attrs["id"] || attrs[:id]
    normalize_system_id(system_id)
  end

  defp normalize_system_id(id) when is_integer(id), do: id

  defp normalize_system_id(id) when is_binary(id) do
    case Integer.parse(id) do
      {int_id, ""} -> int_id
      _ -> nil
    end
  end

  defp normalize_system_id(_), do: nil

  defp parse_float(nil), do: nil
  defp parse_float(value) when is_float(value), do: value
  defp parse_float(value) when is_integer(value), do: value / 1.0

  defp parse_float(value) when is_binary(value) do
    case Float.parse(value) do
      {float_val, ""} -> float_val
      _ -> nil
    end
  end

  defp parse_float(_), do: nil

  @doc """
  Safe constructor that returns {:ok, system} or {:error, reason}.
  """
  @spec new_safe(map()) :: {:ok, t()} | {:error, term()}
  def new_safe(attrs) when is_map(attrs) do
    try do
      system = new(attrs)
      {:ok, system}
    rescue
      e in ArgumentError -> {:error, {:validation_error, e.message}}
      e -> {:error, {:system_creation_failed, inspect(e)}}
    end
  end

  # ══════════════════════════════════════════════════════════════════════════════
  # TrackingBehaviour Implementation
  # ══════════════════════════════════════════════════════════════════════════════

  @impl true
  def is_tracked?(system_id) when is_binary(system_id) do
    case Cache.get("map:systems") do
      {:ok, systems} when is_list(systems) ->
        tracked = Enum.any?(systems, &(&1["solar_system_id"] == system_id))
        {:ok, tracked}

      {:ok, _} ->
        {:ok, false}

      {:error, :not_found} ->
        {:ok, false}
    end
  end

  def is_tracked?(system_id) when is_integer(system_id) do
    is_tracked?(Integer.to_string(system_id))
  end

  @impl true
  def is_tracked?(_), do: {:error, :invalid_system_id}

  # ══════════════════════════════════════════════════════════════════════════════
  # Simple Constructor Functions
  # ══════════════════════════════════════════════════════════════════════════════

  @doc """
  Creates a system struct from API data.

  Note: This function assumes the API data is valid and does not perform validation.
  Use `new/1` or `new_safe/1` for validated construction.
  """
  @spec from_api_data(map()) :: t() | no_return()
  def from_api_data(data) when is_map(data) do
    log_api_data(data)
    build_system_struct(data)
  end

  defp build_system_struct(data) do
    %__MODULE__{
      solar_system_id: extract_system_id(data),
      name: extract_name(data),
      original_name: get_string(data, "original_name"),
      system_type: extract_system_type(data),
      type_description: extract_type_description(data),
      class_title: extract_class_title(data),
      region_name: extract_region_name(data),
      security_status: extract_security_status(data),
      is_shattered: extract_is_shattered(data),
      statics: extract_statics(data),
      effect_name: extract_effect_name(data),
      tracked: true
    }
  end

  defp log_api_data(data) do
    Logger.debug("Creating system from API data",
      data_keys: Map.keys(data),
      solar_system_id: Map.get(data, "solar_system_id"),
      id: Map.get(data, "id"),
      system_id: Map.get(data, "system_id"),
      category: :api
    )
  end

  defp extract_name(data) do
    extract_field(data, ["name", "system_name"], &get_string/2)
  end

  defp extract_field(data, keys, extractor) when is_list(keys) do
    Enum.find_value(keys, fn key -> extractor.(data, key) end)
  end

  defp extract_system_type(data) do
    extract_field(data, ["system_type", "type"], &get_string/2)
  end

  defp extract_type_description(data) do
    extract_field(data, ["type_description", "class_title"], &get_string/2)
  end

  defp extract_class_title(data) do
    extract_field(data, ["class_title", "class"], &get_string/2)
  end

  defp extract_region_name(data) do
    extract_field(data, ["region_name", "region"], &get_string/2)
  end

  defp extract_security_status(data) do
    extract_field(data, ["security_status", "security"], &get_float/2)
  end

  defp extract_is_shattered(data) do
    extract_field(data, ["is_shattered", "shattered"], &get_boolean/2)
  end

  defp extract_statics(data) do
    extract_field(data, ["statics", "static_wormholes"], &get_list/2)
  end

  defp extract_effect_name(data) do
    extract_field(data, ["effect_name", "effect"], &get_string/2)
  end

  @doc """
  Gets system information from cache.
  """
  @spec get_system(String.t()) :: {:ok, t()} | {:error, term()}
  def get_system(system_id) when is_binary(system_id) do
    case Cache.get("map:systems") do
      {:ok, systems} when is_list(systems) ->
        case Enum.find(systems, &(&1["solar_system_id"] == system_id)) do
          nil -> {:error, :not_found}
          system_data -> {:ok, from_api_data(system_data)}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  def get_system(system_id) when is_integer(system_id) do
    get_system(Integer.to_string(system_id))
  end

  @doc """
  Gets system by name from cache.
  """
  @spec get_system_by_name(String.t()) :: {:ok, t()} | {:error, term()}
  def get_system_by_name(system_name) when is_binary(system_name) do
    case Cache.get("map:systems") do
      {:ok, systems} when is_list(systems) ->
        case Enum.find(systems, &(&1["name"] == system_name)) do
          nil -> {:error, :not_found}
          system_data -> {:ok, from_api_data(system_data)}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Checks if a system is a wormhole system.
  """
  @spec wormhole?(t()) :: boolean()
  def wormhole?(%__MODULE__{system_type: type}) do
    type == "wormhole" or type == :wormhole
  end

  # ══════════════════════════════════════════════════════════════════════════════
  # Utility Functions
  # ══════════════════════════════════════════════════════════════════════════════

  @spec get_string(map(), String.t()) :: String.t() | nil
  defp get_string(data, key) do
    case Map.get(data, key) do
      value when is_binary(value) -> value
      value when is_integer(value) -> Integer.to_string(value)
      _ -> nil
    end
  end

  @spec get_float(map(), String.t()) :: float() | nil
  defp get_float(data, key) do
    case Map.get(data, key) do
      value when is_float(value) ->
        value

      value when is_integer(value) ->
        value / 1.0

      value when is_binary(value) ->
        case Float.parse(value) do
          {float, ""} -> float
          _ -> nil
        end

      _ ->
        nil
    end
  end

  @spec get_boolean(map(), String.t()) :: boolean() | nil
  defp get_boolean(data, key) do
    case Map.get(data, key) do
      value when is_boolean(value) -> value
      "true" -> true
      "false" -> false
      1 -> true
      0 -> false
      _ -> nil
    end
  end

  @spec get_list(map(), String.t()) :: list(String.t()) | nil
  defp get_list(data, key) do
    case Map.get(data, key) do
      value when is_list(value) ->
        Enum.map(value, &to_string/1)

      _ ->
        nil
    end
  end
end
