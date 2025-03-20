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
    id: String.t(),               # Map system ID
    solar_system_id: integer(),   # EVE Online system ID
    name: String.t(),             # Display name (properly formatted)
    original_name: String.t(),    # Original EVE name
    temporary_name: String.t() | nil, # User-assigned nickname
    locked: boolean(),            # Whether the system is locked
    class_title: String.t() | nil,# Class designation (e.g., "C3")
    effect_name: String.t() | nil,# System effect name (if any)
    statics: list(map()),         # List of static wormhole types with destination info
    system_type: atom()           # :wormhole, :highsec, :lowsec, etc.
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
    :statics,         
    :system_type      
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
    # Handle special field name conversions
    case key do
      # Handle special case for "staticInfo" which is accessed in the API controller
      "staticInfo" -> 
        # Return a synthetic statics info structure from the system's data
        {:ok, %{
          "statics" => struct.statics || [],
          "typeDescription" => struct.class_title || get_class_description(struct.system_type)
        }}
        
      # Use pattern matching for field mapping (legacy names -> new struct names)
      "systemId" -> {:ok, struct.solar_system_id}
      "systemName" -> {:ok, struct.name}
      "alias" -> {:ok, struct.temporary_name}
      "id" -> {:ok, struct.id}
        
      # For any other field, try to convert to atom
      _ ->
        try do
          atom_key = String.to_existing_atom(key)
          Map.fetch(Map.from_struct(struct), atom_key)
        rescue
          ArgumentError -> :error
        end
    end
  end
  
  # Helper to get a default class description based on system type
  defp get_class_description(:wormhole), do: "Wormhole"
  defp get_class_description(_), do: "K-Space"
  
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
    solar_system_id = case map_response["solar_system_id"] do
      id when is_binary(id) -> 
        case Integer.parse(id) do
          {num, _} -> num
          :error -> nil
        end
      id when is_integer(id) -> id
      _ -> nil
    end
    
    # Handle ID field with fallbacks
    id = map_response["id"] || map_response["systemId"] || "sys-#{:rand.uniform(1000000)}"
    
    # Handle name fields with fallbacks
    original_name = map_response["original_name"] || map_response["systemName"] || map_response["name"]
    temporary_name = map_response["temporary_name"] || map_response["alias"]
    
    # Create the struct with basic information
    %__MODULE__{
      id: id,
      solar_system_id: solar_system_id,
      name: format_system_name(%{"temporary_name" => temporary_name, "original_name" => original_name, "name" => map_response["name"]}),
      original_name: original_name,
      temporary_name: temporary_name,
      locked: map_response["locked"] || false,
      system_type: determine_system_type(solar_system_id),
      class_title: nil, # Will be populated if system-static-info is called
      effect_name: nil, # Will be populated if system-static-info is called
      statics: []       # Will be populated if system-static-info is called
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
    # Extract key details from static_info
    statics = case static_info["static_details"] do
      details when is_list(details) -> 
        details
      _ -> []
    end
    
    # Update the system with additional information
    %__MODULE__{system |
      class_title: static_info["class_title"],
      effect_name: static_info["effect_name"],
      statics: statics
    }
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
      is_map(system) && system.temporary_name && system.temporary_name != "" && system.original_name ->
        "#{system.temporary_name} (#{system.original_name})"
      
      is_map(system) && system.original_name && system.original_name != "" ->
        system.original_name
      
      is_map(system) && Map.get(system, :name) ->
        system.name
      
      true ->
        "Unknown System"
    end
  end

  # Private helper functions
  
  # Format system name based on temporary_name and original_name
  defp format_system_name(%{"temporary_name" => temp_name, "original_name" => orig_name})
       when not is_nil(temp_name) and temp_name != "" and not is_nil(orig_name) do
    "#{temp_name} (#{orig_name})"
  end
  
  defp format_system_name(%{"original_name" => orig_name}) when not is_nil(orig_name) and orig_name != "" do
    orig_name
  end
  
  defp format_system_name(%{"name" => name}) when not is_nil(name) and name != "" do
    name
  end
  
  defp format_system_name(_), do: "Unknown System"
  
  # Determine system type based on solar_system_id
  defp determine_system_type(id) when is_integer(id) and id >= 31000000 and id < 32000000, do: :wormhole
  defp determine_system_type(_), do: :kspace
end