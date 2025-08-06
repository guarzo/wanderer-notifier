defmodule WandererNotifier.Shared.Utils.EntityUtils do
  @moduledoc """
  Centralized entity ID extraction and validation utilities.

  This module consolidates all ID extraction, normalization, and validation logic
  to ensure consistent handling of EVE Online entity IDs across the application.
  """

  # EVE Online ID ranges
  @min_system_id 30_000_000
  @max_system_id 40_000_000
  @min_character_id 90_000_000
  @max_character_id 100_000_000_000
  @min_corporation_id 98_000_000
  @max_corporation_id 99_000_000
  @min_alliance_id 99_000_000
  @max_alliance_id 100_000_000

  # ============================================================================
  # System ID Functions
  # ============================================================================

  @doc """
  Extracts system ID from various data structures.

  Handles structs, maps with string/atom keys, and looks for common field names:
  - solar_system_id
  - system_id
  - id

  ## Examples
      iex> extract_system_id(%{solar_system_id: 30000142})
      30000142
      
      iex> extract_system_id(%{"system_id" => "30000142"})
      30000142
  """
  @spec extract_system_id(any()) :: integer() | nil
  def extract_system_id(system) when is_struct(system) do
    Map.get(system, :solar_system_id) ||
      Map.get(system, :system_id) ||
      Map.get(system, :id)
  end

  def extract_system_id(system) when is_map(system) do
    value =
      system["solar_system_id"] || system[:solar_system_id] ||
        system["system_id"] || system[:system_id] ||
        system["id"] || system[:id]

    normalize_id(value)
  end

  def extract_system_id(_), do: nil

  @doc """
  Validates if a system ID is within EVE Online's valid range.

  ## Examples
      iex> valid_system_id?(30000142)
      true
      
      iex> valid_system_id?(20000000)
      false
  """
  @spec valid_system_id?(any()) :: boolean()
  def valid_system_id?(system_id) when is_integer(system_id) do
    system_id >= @min_system_id and system_id <= @max_system_id
  end

  def valid_system_id?(_), do: false

  # ============================================================================
  # Character ID Functions
  # ============================================================================

  @doc """
  Extracts character ID from various data structures.

  Handles nested structures like %{"character" => %{"eve_id" => id}} as well as
  flat structures with character_id fields.

  ## Examples
      iex> extract_character_id(%{"character" => %{"eve_id" => 95123456}})
      95123456
      
      iex> extract_character_id(%{character_id: "95123456"})
      95123456
  """
  @spec extract_character_id(any()) :: integer() | nil
  def extract_character_id(data) when is_map(data) do
    # Handle nested character structure
    if is_map(data["character"]) and data["character"]["eve_id"] do
      normalize_id(data["character"]["eve_id"])
    else
      # Handle flat structure with various key formats
      value =
        data["character_id"] || data[:character_id] ||
          data["eve_id"] || data[:eve_id] ||
          data["id"] || data[:id]

      normalize_id(value)
    end
  end

  def extract_character_id(_), do: nil

  @doc """
  Validates if a character ID is within EVE Online's valid range.

  ## Examples
      iex> valid_character_id?(95123456)
      true
      
      iex> valid_character_id?(50000000)
      false
  """
  @spec valid_character_id?(any()) :: boolean()
  def valid_character_id?(char_id) when is_integer(char_id) do
    char_id >= @min_character_id and char_id <= @max_character_id
  end

  def valid_character_id?(_), do: false

  # ============================================================================
  # Corporation ID Functions
  # ============================================================================

  @doc """
  Extracts corporation ID from various data structures.
  """
  @spec extract_corporation_id(any()) :: integer() | nil
  def extract_corporation_id(data) when is_map(data) do
    value =
      data["corporation_id"] || data[:corporation_id] ||
        data["corp_id"] || data[:corp_id]

    normalize_id(value)
  end

  def extract_corporation_id(_), do: nil

  @doc """
  Validates if a corporation ID is within EVE Online's valid range.
  """
  @spec valid_corporation_id?(any()) :: boolean()
  def valid_corporation_id?(corp_id) when is_integer(corp_id) do
    corp_id >= @min_corporation_id and corp_id <= @max_corporation_id
  end

  def valid_corporation_id?(_), do: false

  # ============================================================================
  # Alliance ID Functions
  # ============================================================================

  @doc """
  Extracts alliance ID from various data structures.
  """
  @spec extract_alliance_id(any()) :: integer() | nil
  def extract_alliance_id(data) when is_map(data) do
    value = data["alliance_id"] || data[:alliance_id]
    normalize_id(value)
  end

  def extract_alliance_id(_), do: nil

  @doc """
  Validates if an alliance ID is within EVE Online's valid range.
  """
  @spec valid_alliance_id?(any()) :: boolean()
  def valid_alliance_id?(alliance_id) when is_integer(alliance_id) do
    alliance_id >= @min_alliance_id and alliance_id <= @max_alliance_id
  end

  def valid_alliance_id?(_), do: false

  # ============================================================================
  # Generic Functions
  # ============================================================================

  @doc """
  Extracts a value from a map/struct with fallback to atom/string keys.

  ## Examples
      iex> get_value(%{test: 123}, "test")
      123
      
      iex> get_value(%{"test" => 123}, :test)
      123
  """
  @spec get_value(map(), String.t() | atom()) :: any()
  def get_value(data, key) when is_map(data) and is_binary(key) do
    data[key] || data[String.to_atom(key)]
  end

  def get_value(data, key) when is_map(data) and is_atom(key) do
    data[key] || data[Atom.to_string(key)]
  end

  def get_value(_, _), do: nil

  @doc """
  Normalizes an ID value to integer or nil.

  Handles strings, integers, and floats.

  ## Examples
      iex> normalize_id(123)
      123
      
      iex> normalize_id("123")
      123
      
      iex> normalize_id(123.0)
      123
      
      iex> normalize_id("invalid")
      nil
  """
  @spec normalize_id(any()) :: integer() | nil
  def normalize_id(id) when is_integer(id), do: id
  def normalize_id(id) when is_float(id), do: trunc(id)

  def normalize_id(id) when is_binary(id) do
    case Integer.parse(id, 10) do
      {int_id, ""} -> int_id
      _ -> nil
    end
  end

  def normalize_id(_), do: nil

  @doc """
  Parses a value to integer with optional default.

  ## Examples
      iex> parse_integer("123")
      123
      
      iex> parse_integer("invalid", 0)
      0
  """
  @spec parse_integer(any(), integer() | nil) :: integer() | nil
  def parse_integer(value, default \\ nil)
  def parse_integer(value, _default) when is_integer(value), do: value

  def parse_integer(value, default) when is_binary(value) do
    case Integer.parse(value, 10) do
      {int_val, _} -> int_val
      :error -> default
    end
  end

  def parse_integer(_, default), do: default

  @doc """
  Parses a value to float with optional default.

  ## Examples
      iex> parse_float("123.45")
      123.45
      
      iex> parse_float("invalid", 0.0)
      0.0
  """
  @spec parse_float(any(), float() | nil) :: float() | nil
  def parse_float(value, default \\ nil)
  def parse_float(value, _default) when is_float(value), do: value
  def parse_float(value, _default) when is_integer(value), do: value / 1

  def parse_float(value, default) when is_binary(value) do
    case Float.parse(value) do
      {float_val, _} -> float_val
      :error -> default
    end
  end

  def parse_float(_, default), do: default
end
