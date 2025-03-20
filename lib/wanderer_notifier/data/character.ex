defmodule WandererNotifier.Data.Character do
  @moduledoc """
  Struct and functions for managing tracked character data from the map API.
  
  This module standardizes the representation of characters from the map API,
  ensuring consistent field names and handling of optional fields.
  
  Implements the Access behaviour to allow map-like access with ["key"] syntax.
  """
  @behaviour Access

  @typedoc "Type representing a tracked character"
  @type t :: %__MODULE__{
    eve_id: String.t(),              # EVE Online character ID (primary identifier)
    name: String.t(),                # Character name
    corporation_id: integer() | nil, # Corporation ID
    corporation_ticker: String.t() | nil,  # Corporation ticker (used as name)
    alliance_id: integer() | nil,    # Alliance ID
    alliance_ticker: String.t() | nil,     # Alliance ticker (used as name)
    tracked: boolean()               # Whether character is being tracked
  }

  defstruct [
    :eve_id,
    :name,
    :corporation_id,
    :corporation_ticker,
    :alliance_id,
    :alliance_ticker,
    :tracked
  ]
  
  # Implement Access behaviour methods to allow map-like access
  
  @doc """
  Implements the Access behaviour fetch method.
  Allows accessing fields with map["key"] syntax.
  
  ## Examples
      iex> character = %Character{eve_id: "123", name: "Test"}
      iex> character["eve_id"]
      "123"
      iex> character["name"]
      "Test"
  """
  @spec fetch(t(), atom() | String.t()) :: {:ok, any()} | :error
  def fetch(struct, key) when is_atom(key) do
    Map.fetch(Map.from_struct(struct), key)
  end
  
  def fetch(struct, key) when is_binary(key) do
    # Handle special field name conversions
    case key do
      # Handle special case for character_id which is accessed in the API controller
      "character_id" -> {:ok, struct.eve_id}
      
      # Legacy field names
      "id" -> {:ok, struct.eve_id}
      "corporationID" -> {:ok, struct.corporation_id}
      "corporationName" -> {:ok, struct.corporation_ticker}
      "allianceID" -> {:ok, struct.alliance_id}
      "allianceName" -> {:ok, struct.alliance_ticker}
      
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
  
  @doc """
  Implements the Access behaviour get method.
  
  ## Examples
      iex> character = %Character{eve_id: "123", name: "Test"}
      iex> character["missing_key", :default]
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
    raise "get_and_update not implemented for immutable Character struct"
  end
  
  @doc """
  Implements the Access behaviour pop method.
  Not fully implemented since structs are intended to be immutable.
  """
  @spec pop(t(), any()) :: {any(), t()}
  def pop(_struct, _key) do
    raise "pop not implemented for immutable Character struct"
  end
  
  @doc """
  Creates a new Character struct from map API response data.
  
  ## Parameters
    - map_response: Raw API response data for a single character
    
  ## Returns
    - A new Character struct with standardized fields
  """
  def new(map_response) do
    # Extract nested character data if present
    character_data = Map.get(map_response, "character", %{})
    
    # Convert IDs to proper types
    corporation_id = parse_integer(character_data["corporation_id"])
    alliance_id = parse_integer(character_data["alliance_id"])
    
    # For API responses with non-nested character data, make sure we can still access name and ids
    name = character_data["name"] || map_response["name"]
    eve_id = character_data["eve_id"] || map_response["eve_id"] || map_response["id"]
    corporation_ticker = character_data["corporation_ticker"] || map_response["corporation_ticker"]
    alliance_ticker = character_data["alliance_ticker"] || map_response["alliance_ticker"]
    
    # Create the struct with all fields
    %__MODULE__{
      eve_id: eve_id,
      name: name,
      corporation_id: corporation_id,
      corporation_ticker: corporation_ticker,
      alliance_id: alliance_id,
      alliance_ticker: alliance_ticker,
      tracked: Map.get(map_response, "tracked", true)  # Default to true for characters returned by API
    }
  end
  
  @doc """
  Check if a character has an alliance.
  
  ## Parameters
    - character: A Character struct
    
  ## Returns
    - true if the character has alliance data, false otherwise
  """
  def has_alliance?(%__MODULE__{alliance_id: id, alliance_ticker: ticker}) do
    id != nil && ticker != nil && ticker != ""
  end
  
  @doc """
  Check if a character has corporation data.
  
  ## Parameters
    - character: A Character struct
    
  ## Returns
    - true if the character has corporation data, false otherwise
  """
  def has_corporation?(%__MODULE__{corporation_id: id, corporation_ticker: ticker}) do
    id != nil && ticker != nil && ticker != ""
  end
  
  @doc """
  Formats a character's name including corporation and alliance if available.
  
  ## Parameters
    - character: A Character struct
    
  ## Returns
    - Formatted character name with corporation/alliance info
  """
  def format_name(%__MODULE__{} = character) do
    base_name = character.name || "Unknown Character"
    
    cond do
      has_alliance?(character) && has_corporation?(character) ->
        "#{base_name} [#{character.corporation_ticker}] <#{character.alliance_ticker}>"
        
      has_corporation?(character) ->
        "#{base_name} [#{character.corporation_ticker}]"
        
      true ->
        base_name
    end
  end
  
  # Private helper functions
  
  # Parse a value to integer, handling nil and strings
  defp parse_integer(nil), do: nil
  defp parse_integer(val) when is_integer(val), do: val
  defp parse_integer(val) when is_binary(val) do
    case Integer.parse(val) do
      {int, _} -> int
      :error -> nil
    end
  end
  defp parse_integer(_), do: nil
end
