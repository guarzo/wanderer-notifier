defmodule WandererNotifier.Map.MapCharacter do
  @moduledoc """
  Struct for standardizing character data from the map API (current flat format).

  Expects API payloads like:

  ```json
  {
    "data": [
      {
        "characters": [
          {
            "name": "Shiv Black",
            "corporation_id": 98801377,
            "alliance_id": null,
            "alliance_ticker": null,
            "corporation_ticker": "SAL.T",
            "eve_id": "2118083819"
          }
          // ... more characters ...
        ],
        "main_character_eve_id": "2117608364"
      }
    ]
  }
  ```

  Also implements character tracking functionality.
  """

  @behaviour Access
  @behaviour WandererNotifier.Map.CharacterBehaviour

  alias WandererNotifier.Cache.Keys, as: CacheKeys

  @typedoc "Type representing a tracked character"
  @type t :: %__MODULE__{
          character_id: integer(),
          name: String.t(),
          corporation_id: integer(),
          alliance_id: integer(),
          eve_id: integer(),
          corporation_ticker: String.t() | nil,
          alliance_ticker: String.t() | nil,
          tracked: boolean()
        }

  defstruct [
    :character_id,
    :name,
    :corporation_id,
    :alliance_id,
    :eve_id,
    :corporation_ticker,
    :alliance_ticker,
    tracked: false
  ]

  @impl true
  def is_tracked?(character_id) when is_integer(character_id) do
    character_id_str = Integer.to_string(character_id)
    is_tracked?(character_id_str)
  end

  def is_tracked?(character_id_str) when is_binary(character_id_str) do
    cache_name = Application.get_env(:wanderer_notifier, :cache_name, :wanderer_cache)

    case Cachex.get(cache_name, CacheKeys.character_list()) do
      {:ok, characters} when is_list(characters) ->
        Enum.any?(characters, fn char ->
          id = Map.get(char, :character_id) || Map.get(char, "character_id")
          to_string(id) == character_id_str
        end)

      _ ->
        {:ok, false}
    end
  end

  def is_tracked?(_), do: {:error, :invalid_character_id}

  @doc """
  Fetch a field via the Access behaviour (allows `struct["key"]` syntax).
  Supports special key mappings for compatibility with different API formats.
  """
  @impl true
  @spec fetch(t(), atom() | String.t()) :: {:ok, any()} | :error
  def fetch(struct, key) when is_atom(key) do
    struct
    |> Map.from_struct()
    |> Map.fetch(key)
  end

  def fetch(struct, "id"), do: fetch(struct, :character_id)
  def fetch(struct, "corporationID"), do: fetch(struct, :corporation_id)
  def fetch(struct, "corporationName"), do: fetch(struct, :corporation_ticker)
  def fetch(struct, "allianceID"), do: fetch(struct, :alliance_id)
  def fetch(struct, "allianceName"), do: fetch(struct, :alliance_ticker)

  def fetch(struct, key) when is_binary(key) do
    try do
      atom_key = String.to_existing_atom(key)
      fetch(struct, atom_key)
    rescue
      ArgumentError -> :error
    end
  end

  @doc """
  Get a field with a default via the Access behaviour.
  """
  @spec get(t(), atom() | String.t(), any()) :: any()
  def get(struct, key, default \\ nil) do
    case fetch(struct, key) do
      {:ok, val} -> val
      :error -> default
    end
  end

  @impl true
  @doc "get_and_update not supported for immutable struct"
  def get_and_update(_struct, _key, _fun), do: raise("not implemented")

  @impl true
  @doc "pop not supported for immutable struct"
  def pop(_struct, _key), do: raise("not implemented")

  @doc """
  Create a MapCharacter from the current flat API format.
  Expects a map with at least `"eve_id"` and `"name"` keys.
  """
  @spec new(map()) :: t()
  def new(%{"eve_id" => eve_id} = attrs) do
    attrs
    |> Map.put("character_id", normalize_character_id(eve_id))
    |> create_character()
  end

  def new(%{"character_id" => _} = attrs) do
    create_character(attrs)
  end

  def new(_) do
    raise ArgumentError, "Missing required character identification (eve_id or character_id)"
  end

  defp normalize_character_id(eve_id) when is_binary(eve_id), do: eve_id
  defp normalize_character_id(eve_id) when is_integer(eve_id), do: Integer.to_string(eve_id)

  defp create_character(attrs) do
    name = attrs["name"] || raise(ArgumentError, "Missing name for character")
    corp_id = parse_integer(attrs["corporation_id"])
    alliance_id = parse_integer(attrs["alliance_id"])

    %__MODULE__{
      character_id: attrs["character_id"],
      name: name,
      corporation_id: corp_id,
      alliance_id: alliance_id,
      eve_id: attrs["eve_id"],
      corporation_ticker: attrs["corporation_ticker"],
      alliance_ticker: attrs["alliance_ticker"],
      tracked: attrs["tracked"] || false
    }
  end

  # Parses integer or string to integer, returns nil on failure
  defp parse_integer(nil), do: nil
  defp parse_integer(val) when is_integer(val), do: val

  defp parse_integer(val) when is_binary(val) do
    case Integer.parse(val) do
      {int, _rem} -> int
      :error -> nil
    end
  end

  defp parse_integer(_), do: nil

  @doc "Checks if the character has both corporation ID and ticker"
  @spec has_corporation?(t()) :: boolean()
  def has_corporation?(%__MODULE__{corporation_id: corp_id, corporation_ticker: ticker}) do
    not is_nil(corp_id) and not is_nil(ticker)
  end

  def has_corporation?(_), do: false

  @doc """
  Gets a character by ID from the cache.
  """
  def get_character(character_id) do
    cache_name = Application.get_env(:wanderer_notifier, :cache_name, :wanderer_cache)

    case Cachex.get(cache_name, CacheKeys.character_list()) do
      {:ok, characters} when is_list(characters) ->
        Enum.find(characters, &(&1["id"] == character_id))

      _ ->
        nil
    end
  end

  @doc """
  Gets a character by name from the cache.
  """
  def get_character_by_name(character_name) do
    cache_name = Application.get_env(:wanderer_notifier, :cache_name, :wanderer_cache)

    case Cachex.get(cache_name, CacheKeys.character_list()) do
      {:ok, characters} when is_list(characters) ->
        Enum.find(characters, &(&1["name"] == character_name))

      _ ->
        nil
    end
  end
end
