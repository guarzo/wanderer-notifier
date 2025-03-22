defmodule WandererNotifier.Data.Character do
  @moduledoc """
  Struct and functions for managing tracked character data from the map API.

  This module standardizes the representation of characters from the map API,
  ensuring consistent field names and handling of optional fields.

  ## Core Principles
  - Single Source of Truth: Character struct is the canonical representation
  - Early Conversion: API responses are converted to structs immediately
  - No Silent Renaming: Field names are preserved consistently
  - Clear Contracts: Each function has explicit input/output contracts
  - Explicit Error Handling: Validation errors are raised explicitly

  Implements the Access behaviour to allow map-like access with ["key"] syntax.
  """
  @behaviour Access

  @typedoc "Type representing a tracked character"
  @type t :: %__MODULE__{
          # EVE Online character ID (primary identifier)
          eve_id: String.t(),
          # Character name
          name: String.t(),
          # Corporation ID
          corporation_id: integer() | nil,
          # Corporation ticker (used as name)
          corporation_ticker: String.t() | nil,
          # Alliance ID
          alliance_id: integer() | nil,
          # Alliance ticker (used as name)
          alliance_ticker: String.t() | nil,
          # Whether character is being tracked
          tracked: boolean()
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
      "character_id" ->
        {:ok, struct.eve_id}

      "id" ->
        {:ok, struct.eve_id}

      "corporationID" ->
        {:ok, struct.corporation_id}

      "corporationName" ->
        {:ok, struct.corporation_ticker}

      "allianceID" ->
        {:ok, struct.alliance_id}

      "allianceName" ->
        {:ok, struct.alliance_ticker}

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
  Validates required fields and standardizes the data structure.

  ## Parameters
    - map_response: Raw API response data for a single character

  ## Returns
    - A new Character struct with standardized fields

  ## Raises
    - ArgumentError: If required fields (eve_id, name) are missing
  """
  @spec new(map()) :: t()
  def new(map_response) when is_map(map_response) do
    require Logger

    # Extract nested character data if present
    character_data = Map.get(map_response, "character", %{})

    # Log the incoming data structure at debug level
    Logger.debug(
      "[Character.new] Processing character data: #{inspect(map_response, limit: 500)}"
    )

    # Extract required fields with clear validation
    name =
      character_data["name"] ||
        map_response["name"] ||
        map_response["character_name"]

    # IMPORTANT: For character IDs, we prioritize eve_id as the canonical identifier
    # and only fall back to character_id if eve_id is not available
    eve_id =
      character_data["eve_id"] ||
        map_response["eve_id"] ||
        map_response["id"] ||
        map_response["character_id"]

    # Log the extracted ID for debugging
    Logger.debug("[Character.new] Extracted eve_id: #{inspect(eve_id)} from data")

    # Validate required fields
    unless eve_id && name do
      Logger.error(
        "[Character.new] Missing required fields: eve_id=#{inspect(eve_id)}, name=#{inspect(name)}"
      )

      raise ArgumentError, "Missing required fields for Character: eve_id and name are required"
    end

    # Parse corporation ID with explicit validation
    corp_id_raw =
      character_data["corporation_id"] ||
        map_response["corporation_id"] ||
        character_data["corporationID"] ||
        map_response["corporationID"]

    corporation_id = parse_integer(corp_id_raw)

    # Look for corporation ticker in various formats
    corporation_ticker =
      character_data["corporation_ticker"] ||
        map_response["corporation_ticker"] ||
        map_response["corporation_name"] ||
        character_data["corporation_name"]

    # Parse alliance ID with explicit validation
    alliance_id_raw =
      character_data["alliance_id"] ||
        map_response["alliance_id"] ||
        character_data["allianceID"] ||
        map_response["allianceID"]

    alliance_id = parse_integer(alliance_id_raw)

    # Look for alliance ticker in various formats
    alliance_ticker =
      character_data["alliance_ticker"] ||
        map_response["alliance_ticker"] ||
        map_response["alliance_name"] ||
        character_data["alliance_name"]

    # Create the struct with all fields
    %__MODULE__{
      eve_id: eve_id,
      name: name,
      corporation_id: corporation_id,
      corporation_ticker: corporation_ticker,
      alliance_id: alliance_id,
      alliance_ticker: alliance_ticker,
      # Default to true for characters returned by API
      tracked: Map.get(map_response, "tracked", true)
    }
  end

  def new(invalid_input) do
    raise ArgumentError, "Expected map for Character.new, got: #{inspect(invalid_input)}"
  end

  @doc """
  Creates a Character struct from a simplified map with exact field names.
  Useful for tests and internal data creation.

  ## Parameters
    - attrs: Map with exact field names matching the struct

  ## Returns
    - A new Character struct
  """
  @spec from_map(map()) :: t()
  def from_map(attrs) when is_map(attrs) do
    # Validate required fields
    unless Map.has_key?(attrs, :eve_id) && Map.has_key?(attrs, :name) do
      raise ArgumentError, "Missing required fields for Character: eve_id and name are required"
    end

    struct(__MODULE__, attrs)
  end

  @doc """
  Check if a character has an alliance.

  ## Parameters
    - character: A Character struct

  ## Returns
    - true if the character has alliance data, false otherwise
  """
  @spec has_alliance?(t()) :: boolean()
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
  @spec has_corporation?(t()) :: boolean()
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
  @spec format_name(t()) :: String.t()
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

  @doc """
  Validates a Character struct to ensure it has all required fields.

  ## Parameters
    - character: A Character struct to validate

  ## Returns
    - {:ok, character} if valid
    - {:error, reason} if invalid
  """
  @spec validate(t()) :: {:ok, t()} | {:error, String.t()}
  def validate(%__MODULE__{} = character) do
    cond do
      is_nil(character.eve_id) ->
        {:error, "Character is missing required eve_id field"}

      is_nil(character.name) ->
        {:error, "Character is missing required name field"}

      true ->
        {:ok, character}
    end
  end

  # Private helper functions

  # Parse a value to integer, handling nil and strings
  defp parse_integer(nil), do: nil
  defp parse_integer(val) when is_integer(val), do: val

  defp parse_integer(val) when is_binary(val) do
    # Remove underscores from strings like "67_890" before parsing
    formatted_val = String.replace(val, "_", "")

    case Integer.parse(formatted_val) do
      {int, _} ->
        int

      :error ->
        require Logger
        Logger.debug("[Character.parse_integer] Failed to parse '#{val}' as integer")
        nil
    end
  end

  defp parse_integer(val) do
    require Logger
    Logger.debug("[Character.parse_integer] Unhandled value type: #{inspect(val)}")
    nil
  end
end
