defmodule WandererNotifier.Utils.TypeHelpers do
  @moduledoc """
  Common type-related utility functions.
  Used across the application for consistent type checking and formatting.
  """

  @doc """
  Returns a string representation of a term's type.
  More detailed than Elixir's built-in typeof, includes struct names.

  ## Examples
      iex> TypeHelpers.typeof("hello")
      "string"
      iex> TypeHelpers.typeof(%MyApp.User{})
      "struct:MyApp.User"
  """
  def typeof(nil), do: "nil"
  def typeof(term) when is_binary(term), do: "string"
  def typeof(term) when is_boolean(term), do: "boolean"
  def typeof(term) when is_integer(term), do: "integer"
  def typeof(term) when is_float(term), do: "float"
  def typeof(term) when is_map(term) and not is_struct(term), do: "map"
  def typeof(term) when is_list(term), do: "list"
  def typeof(term) when is_atom(term), do: "atom"
  def typeof(term) when is_function(term), do: "function"
  def typeof(term) when is_pid(term), do: "pid"
  def typeof(term) when is_reference(term), do: "reference"
  def typeof(term) when is_tuple(term), do: "tuple"
  def typeof(term) when is_struct(term), do: "struct:#{term.__struct__}"
  def typeof(_), do: "unknown"

  @doc """
  Checks if a term is a struct of a specific type.

  ## Examples
      iex> TypeHelpers.struct_of?(%User{}, User)
      true
      iex> TypeHelpers.struct_of?(%{}, User)
      false
  """
  def struct_of?(term, module) when is_atom(module) do
    is_struct(term) and term.__struct__ == module
  end

  def struct_of?(_, _), do: false

  @doc """
  Safely extracts a value from a map or struct using a list of possible keys.
  Returns the first found value or the default.

  ## Examples
      iex> TypeHelpers.extract_field_value(%{name: "John"}, [:name, "name"], "Unknown")
      "John"
      iex> TypeHelpers.extract_field_value(%{"age" => 30}, [:age, "age"], 0)
      30
  """
  def extract_field_value(data, field_names, default \\ nil) do
    Enum.find_value(field_names, default, fn field ->
      cond do
        is_struct(data) and Map.has_key?(data, field) -> Map.get(data, field)
        is_map(data) and Map.has_key?(data, field) -> Map.get(data, field)
        true -> nil
      end
    end)
  end
end
