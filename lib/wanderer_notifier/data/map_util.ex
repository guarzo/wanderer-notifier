defmodule WandererNotifier.Data.MapUtil do
  @moduledoc """
  Utility functions for working with maps consistently across the application.
  """

  @doc """
  Gets a value from a map trying multiple possible keys.
  Useful for handling maps with string or atom keys, or different naming conventions.

  ## Parameters
    - `map` - The map to search in
    - `keys` - List of keys to try

  ## Returns
    - The value of the first key that exists in the map
    - nil if none of the keys exist

  ## Examples
      iex> get_value(%{"name" => "John"}, ["name", :name])
      "John"

      iex> get_value(%{name: "John"}, ["name", :name])
      "John"

      iex> get_value(%{}, ["name", :name])
      nil

      iex> get_value(%{"user_id" => 123}, ["id", "user_id", :id, :user_id])
      123
  """
  @spec get_value(map(), list(String.t() | atom())) :: any()
  def get_value(map, keys) when is_map(map) and is_list(keys) do
    Enum.find_value(keys, fn key -> Map.get(map, key) end)
  end

  @doc """
  Safely extracts values from a map using a list of key paths, and constructs a struct.

  ## Parameters
    - `map` - Source map
    - `module` - Module name for the struct to create
    - `mappings` - List of {dest_key, key_paths} tuples, where key_paths is a list of possible keys to try

  ## Returns
    - A struct of the specified module with values extracted from the map

  ## Examples
      iex> extract_to_struct(%{"name" => "John", "age" => 30}, MyModule, [
      ...>   {:name, ["name", :name]},
      ...>   {:age, ["age", :age]}
      ...> ])
      %MyModule{name: "John", age: 30}
  """
  @spec extract_to_struct(map(), module(), list({atom(), list(String.t() | atom())})) :: struct()
  def extract_to_struct(map, module, mappings)
      when is_map(map) and is_atom(module) and is_list(mappings) do
    attrs =
      Enum.reduce(mappings, %{}, fn {dest_key, key_paths}, acc ->
        Map.put(acc, dest_key, get_value(map, key_paths))
      end)

    struct(module, attrs)
  end

  @doc """
  Extracts data from a map using specified field mappings.
  Similar to extract_to_struct but returns a map instead of a struct.

  ## Parameters
    - `map` - Source map
    - `field_mappings` - List of {dest_key, key_paths, default_value} tuples
      or {dest_key, key_paths} if no default value is needed

  ## Returns
    - A map with extracted values

  ## Examples
      iex> extract_map(%{"name" => "John", "age" => 30}, [
      ...>   {:name, ["name", :name]},
      ...>   {:age, ["age", :age], 0},
      ...>   {:email, ["email", :email], nil}
      ...> ])
      %{name: "John", age: 30, email: nil}
  """
  @spec extract_map(
          map(),
          list({atom(), list(String.t() | atom())} | {atom(), list(String.t() | atom()), any()})
        ) :: map()
  def extract_map(map, field_mappings) when is_map(map) and is_list(field_mappings) do
    Enum.reduce(field_mappings, %{}, fn
      # With default value
      {dest_key, key_paths, default}, acc when is_list(key_paths) ->
        value = get_value(map, key_paths) || default
        Map.put(acc, dest_key, value)

      # Without default value
      {dest_key, key_paths}, acc when is_list(key_paths) ->
        Map.put(acc, dest_key, get_value(map, key_paths))
    end)
  end

  @doc """
  Converts a map with potentially mixed string/atom keys to one with only atom keys.

  ## Parameters
    - `map` - Source map with string or atom keys
    - `opts` - Options list:
      - `:recursive` - Whether to recursively convert nested maps (default: false)

  ## Returns
    - A new map with atom keys

  ## Examples
      iex> atomize_keys(%{"name" => "John", :age => 30})
      %{name: "John", age: 30}
  """
  @spec atomize_keys(map(), keyword()) :: map()
  def atomize_keys(map, opts \\ []) when is_map(map) do
    recursive = Keyword.get(opts, :recursive, false)

    Enum.reduce(map, %{}, fn
      # Atom key
      {key, value}, acc when is_atom(key) ->
        if recursive and is_map(value) do
          Map.put(acc, key, atomize_keys(value, opts))
        else
          Map.put(acc, key, value)
        end

      # String key
      {key, value}, acc when is_binary(key) ->
        atom_key = String.to_atom(key)

        if recursive and is_map(value) do
          Map.put(acc, atom_key, atomize_keys(value, opts))
        else
          Map.put(acc, atom_key, value)
        end
    end)
  end
end
