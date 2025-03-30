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

  ## Map API Response Structure
  ```json
  "data": [
    {
      "id": "4712b7b0-37a0-42a6-91ba-1a5bf747d1a0",
      "character": {
        "name": "Nimby Karen",
        "alliance_id": null,
        "alliance_ticker": null,
        "corporation_id": 1000167,
        "corporation_ticker": "SWA",
        "eve_id": "2123019188"
      },
      "inserted_at": "2025-01-01T03:32:51.041452Z",
      "updated_at": "2025-01-01T03:32:51.044408Z",
      "tracked": true,
      "map_id": "678c43cf-f71f-4e14-932d-0545465cdff0",
      "character_id": "90ff63d4-28f3-4071-8717-da1d0d39990e"
    }
  ]
  ```

  IMPORTANT: Note that the character data is nested under the "character" key, and
  eve_id is specifically inside this nested structure. The map_response["character_id"]
  at the top level is a UUID and not the EVE Online ID.
  """
  @behaviour Access
  require Logger
  alias WandererNotifier.Logger, as: AppLogger

  @typedoc "Type representing a tracked character"
  @type t :: %__MODULE__{
          # EVE Online character ID (primary identifier)
          character_id: String.t(),
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
    :character_id,
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
      iex> character = %Character{character_id: "123", name: "Test"}
      iex> character["character_id"]
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
      # No longer needed - eve_id is only used at map API conversion point
      "id" ->
        {:ok, struct.character_id}

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
        atom_key = String.to_existing_atom(key)
        Map.fetch(Map.from_struct(struct), atom_key)
    end
  rescue
    ArgumentError -> :error
  end

  @doc """
  Implements the Access behaviour get method.

  ## Examples
      iex> character = %Character{character_id: "123", name: "Test"}
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

  # Extract character name from character data (nested structure)
  defp extract_character_name(character_data, _map_response) do
    character_data["name"]
  end

  # Extract corporation ID from character data (nested structure)
  defp extract_corporation_id(character_data, _map_response) do
    parse_integer(character_data["corporation_id"])
  end

  # Extract corporation ticker from character data (nested structure)
  defp extract_corporation_ticker(character_data, _map_response) do
    character_data["corporation_ticker"]
  end

  # Extract alliance ID from character data (nested structure)
  defp extract_alliance_id(character_data, _map_response) do
    parse_integer(character_data["alliance_id"])
  end

  # Extract alliance ticker from character data (nested structure)
  defp extract_alliance_ticker(character_data, _map_response) do
    character_data["alliance_ticker"]
  end

  # Validate required fields are present
  defp validate_required_fields(character_id, name) do
    require Logger

    if !(character_id && name) do
      AppLogger.processor_error(
        "Missing required character fields",
        character_id: inspect(character_id),
        name: inspect(name)
      )

      raise ArgumentError,
            "Missing required fields for Character: character_id and name are required"
    end
  end

  @spec new(map()) :: t()
  def new(map_response) when is_map(map_response) do
    # Extract nested character data if present
    character_data = Map.get(map_response, "character", %{})

    # Character data processing can be verbose - only log rarely
    # Add random logging to reduce verbosity (only log ~5% of character data processing)
    if :rand.uniform(100) <= 5 do
      AppLogger.processor_debug(
        "Processing character data (sampled 5%)",
        data: inspect(map_response, limit: 300)
      )
    end

    # Get eve_id and validate it
    eve_id = extract_eve_id(character_data, map_response)

    # Extract name and other attributes
    name = extract_character_name(character_data, map_response)

    # Create the Character struct with all fields
    create_character_struct(
      eve_id,
      name,
      character_data,
      map_response
    )
  end

  def new(invalid_input) do
    raise ArgumentError, "Expected map for Character.new, got: #{inspect(invalid_input)}"
  end

  # Extract eve_id from character data (nested structure)
  defp extract_eve_id(character_data, _map_response) do
    # Extract eve_id directly from character data - no fallbacks
    eve_id = character_data["eve_id"]

    # Validate eve_id exists
    if is_nil(eve_id) do
      AppLogger.processor_error("Missing required eve_id field in character data",
        character_data: inspect(character_data, limit: 200)
      )

      raise ArgumentError, "Missing required eve_id field in character data"
    end

    eve_id
  end

  # Create the Character struct with all extracted fields
  defp create_character_struct(eve_id, name, character_data, map_response) do
    # Validate required fields
    validate_required_fields(eve_id, name)

    # Extract additional fields
    corporation_id = extract_corporation_id(character_data, map_response)
    corporation_ticker = extract_corporation_ticker(character_data, map_response)
    alliance_id = extract_alliance_id(character_data, map_response)
    alliance_ticker = extract_alliance_ticker(character_data, map_response)

    # Create the struct with all fields - using eve_id as the character_id
    %__MODULE__{
      character_id: eve_id,
      name: name,
      corporation_id: corporation_id,
      corporation_ticker: corporation_ticker,
      alliance_id: alliance_id,
      alliance_ticker: alliance_ticker,
      # Default to true for characters returned by API
      tracked: Map.get(map_response, "tracked", true)
    }
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
    if !(Map.has_key?(attrs, :character_id) && Map.has_key?(attrs, :name)) do
      raise ArgumentError,
            "Missing required fields for Character: character_id and name are required"
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
      is_nil(character.character_id) ->
        {:error, "Character is missing required character_id field"}

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
        AppLogger.processor_debug("Failed to parse integer", value: val)
        nil
    end
  end

  defp parse_integer(val) do
    require Logger
    AppLogger.processor_debug("Unhandled value type in parse_integer", value: inspect(val))
    nil
  end

  @doc """
  Ensures input is a list of Character structs.

  ## Parameters
    - input: Can be nil, a list of Characters, or a tuple like {:ok, list}

  ## Returns
    - A list of Character structs (possibly empty)
  """
  def ensure_list(nil), do: []
  def ensure_list(characters) when is_list(characters), do: characters
  def ensure_list({:ok, characters}) when is_list(characters), do: characters

  def ensure_list({:error, {_reason_type, _reason, characters}}) when is_list(characters),
    do: characters

  def ensure_list({:error, _}), do: []
  def ensure_list({_, characters}) when is_list(characters), do: characters
  def ensure_list(_), do: []
end
