defmodule WandererNotifier.Map.MapCharacter do
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
  alias WandererNotifier.Logger.Logger, as: AppLogger

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
      AppLogger.processor_debug("Processing character data",
        raw_character: inspect(character_data),
        map_response: inspect(map_response)
      )
    end

    # Extract character_id (EVE ID) from nested structure
    eve_id =
      case character_data do
        # Character data is a nested object with an eve_id field
        %{"eve_id" => eve_id} when is_binary(eve_id) ->
          eve_id

        # Character data contains eve_id as integer
        %{"eve_id" => eve_id} when is_integer(eve_id) ->
          Integer.to_string(eve_id)

        # Empty or missing eve_id - try other fields
        _ ->
          nil
      end

    # Fallback to character_id in the map_response if eve_id is not available
    character_id = eve_id || Map.get(map_response, "character_id")

    # Extract character name from nested structure
    name = extract_character_name(character_data, map_response)

    # Validate required fields
    validate_required_fields(character_id, name)

    # Extract other fields
    corporation_id = extract_corporation_id(character_data, map_response)
    corporation_ticker = extract_corporation_ticker(character_data, map_response)
    alliance_id = extract_alliance_id(character_data, map_response)
    alliance_ticker = extract_alliance_ticker(character_data, map_response)

    # Get tracked status
    tracked = Map.get(map_response, "tracked", false)

    # Create the character struct
    %__MODULE__{
      character_id: character_id,
      name: name,
      corporation_id: corporation_id,
      corporation_ticker: corporation_ticker,
      alliance_id: alliance_id,
      alliance_ticker: alliance_ticker,
      tracked: tracked
    }
  end

  @doc """
  Creates a character struct from a map with direct field mappings.
  Used for simpler maps that don't have nested character data.

  ## Examples
      iex> simple_map = %{
      ...>   "character_id" => "123",
      ...>   "name" => "Test Character",
      ...>   "corporation_id" => 456,
      ...>   "corporation_ticker" => "CORP"
      ...> }
      iex> Character.from_map(simple_map)
      %Character{
        character_id: "123",
        name: "Test Character",
        corporation_id: 456,
        corporation_ticker: "CORP",
        alliance_id: nil,
        alliance_ticker: nil,
        tracked: false
      }
  """
  @spec from_map(map()) :: t()
  def from_map(map) when is_map(map) do
    # Define field mappings for extraction
    field_mappings = [
      {:character_id, ["character_id", "eve_id", :character_id, :eve_id]},
      {:name, ["name", "character_name", :name, :character_name]},
      {:corporation_id, ["corporation_id", "corporationID", :corporation_id, :corporationID]},
      {:corporation_ticker,
       ["corporation_ticker", "corporationName", :corporation_ticker, :corporationName]},
      {:alliance_id, ["alliance_id", "allianceID", :alliance_id, :allianceID]},
      {:alliance_ticker, ["alliance_ticker", "allianceName", :alliance_ticker, :allianceName]},
      {:tracked, ["tracked", :tracked], false}
    ]

    # Extract fields using MapUtil
    attrs = WandererNotifier.Map.MapUtil.extract_map(map, field_mappings)

    # Ensure character_id is a string
    attrs =
      if is_integer(attrs.character_id) do
        Map.put(attrs, :character_id, Integer.to_string(attrs.character_id))
      else
        attrs
      end

    # Ensure corporation_id is an integer if present
    attrs =
      if is_binary(attrs.corporation_id) do
        Map.put(attrs, :corporation_id, parse_integer(attrs.corporation_id))
      else
        attrs
      end

    # Ensure alliance_id is an integer if present
    attrs =
      if is_binary(attrs.alliance_id) do
        Map.put(attrs, :alliance_id, parse_integer(attrs.alliance_id))
      else
        attrs
      end

    struct(__MODULE__, attrs)
  end

  # Convert string to integer, handling nil and other values gracefully
  defp parse_integer(nil), do: nil
  defp parse_integer(val) when is_integer(val), do: val

  defp parse_integer(val) when is_binary(val) do
    case Integer.parse(val) do
      {int, _} -> int
      :error -> nil
    end
  end

  defp parse_integer(_), do: nil

  @doc """
  Ensures the given value is a list of Character structs.

  ## Parameters
    - input: Can be nil, a Character struct, a list of Character structs,
            or a tuple containing a list of Character structs

  ## Returns
    - A list of Character structs, or empty list if the input is invalid
  """
  @spec ensure_list(nil | t() | [t()] | {:ok, [t()]}) :: [t()]
  def ensure_list(nil), do: []
  def ensure_list(char) when is_struct(char, __MODULE__), do: [char]

  def ensure_list(chars) when is_list(chars) do
    Enum.filter(chars, &is_struct(&1, __MODULE__))
  end

  def ensure_list({:ok, chars}) when is_list(chars), do: ensure_list(chars)
  def ensure_list(_), do: []

  @doc """
  Checks if a character has corporation information.

  ## Parameters
    - character: The character struct to check

  ## Returns
    - true if the character has corporation data, false otherwise
  """
  @spec has_corporation?(t()) :: boolean()
  def has_corporation?(%__MODULE__{} = character) do
    not is_nil(character.corporation_id) and not is_nil(character.corporation_ticker)
  end

  def has_corporation?(_), do: false
end
