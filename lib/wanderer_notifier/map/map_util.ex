defmodule WandererNotifier.Map.MapUtil do
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
    Enum.reduce(field_mappings, %{}, fn mapping, acc ->
      {key, value} = extract_field(map, mapping)
      Map.put(acc, key, value)
    end)
  end

  defp extract_field(map, {dest_key, key_paths}) do
    {dest_key, get_value(map, key_paths)}
  end

  defp extract_field(map, {dest_key, key_paths, default_value}) do
    case get_value(map, key_paths) do
      nil -> {dest_key, default_value}
      value -> {dest_key, value}
    end
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

    Enum.reduce(map, %{}, fn {k, v}, acc ->
      {atom_key, processed_value} = atomize_key({k, v}, recursive, opts)
      Map.put(acc, atom_key, processed_value)
    end)
  end

  defp atomize_key({key, value}, recursive, opts) when is_atom(key) do
    process_value(key, value, recursive, opts)
  end

  # Whitelist of allowed string keys that can be converted to atoms
  # Using atom literals to ensure they exist at compile time
  @allowed_atoms %{
    "id" => :id,
    "name" => :name,
    "type" => :type,
    "class" => :class,
    "security" => :security,
    "region" => :region,
    "constellation" => :constellation,
    "solar_system_id" => :solar_system_id,
    "system_id" => :system_id,
    "character_id" => :character_id,
    "corporation_id" => :corporation_id,
    "alliance_id" => :alliance_id,
    "ship_type_id" => :ship_type_id,
    "position" => :position,
    "x" => :x,
    "y" => :y,
    "z" => :z,
    "killmail_id" => :killmail_id,
    "killmail_time" => :killmail_time,
    "victim" => :victim,
    "attackers" => :attackers,
    "final_blow" => :final_blow,
    "damage_taken" => :damage_taken,
    "corporation_name" => :corporation_name,
    "alliance_name" => :alliance_name,
    "character_name" => :character_name,
    "security_status" => :security_status,
    "effect" => :effect,
    "statics" => :statics,
    "static" => :static,
    "wanderer_id" => :wanderer_id,
    "is_shattered" => :is_shattered,
    "sun_type_id" => :sun_type_id,
    "radius" => :radius,
    "luminosity" => :luminosity,
    "temperature" => :temperature,
    "spectral_class" => :spectral_class,
    "age" => :age,
    "life" => :life,
    "anomaly_type_id" => :anomaly_type_id,
    "anomaly_name" => :anomaly_name,
    "ship_jumps" => :ship_jumps,
    "npc_kills" => :npc_kills,
    "pod_kills" => :pod_kills,
    "updated_at" => :updated_at,
    "created_at" => :created_at,
    "last_seen_at" => :last_seen_at,
    "online" => :online,
    "is_online" => :is_online,
    "main_id" => :main_id,
    "alt_id" => :alt_id,
    "tracked" => :tracked,
    "notification_enabled" => :notification_enabled,
    "notifications_enabled" => :notifications_enabled,
    "status" => :status,
    "message" => :message,
    "error" => :error,
    "reason" => :reason,
    "data" => :data,
    "meta" => :meta
  }

  defp atomize_key({key, value}, recursive, opts) when is_binary(key) do
    atom_key = Map.get(@allowed_atoms, key, key)
    process_value(atom_key, value, recursive, opts)
  end

  defp process_value(key, value, recursive, opts) do
    if recursive and is_map(value) do
      {key, atomize_keys(value, opts)}
    else
      {key, value}
    end
  end
end
