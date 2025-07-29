defmodule WandererNotifier.Domains.Tracking.Entities.Character do
  @moduledoc """
  Simplified character entity that removes Access behavior complexity.

  Provides essential character tracking functionality without unnecessary
  abstractions or complex behaviors.
  """

  @behaviour WandererNotifier.Map.TrackingBehaviour
  alias WandererNotifier.Infrastructure.Cache

  @type t :: %__MODULE__{
          character_id: String.t(),
          name: String.t(),
          corporation_id: integer() | nil,
          alliance_id: integer() | nil,
          eve_id: String.t(),
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

  # ══════════════════════════════════════════════════════════════════════════════
  # Constructor Functions
  # ══════════════════════════════════════════════════════════════════════════════

  @doc """
  Creates a new Character struct from attributes map.
  """
  @spec new(map()) :: t()
  def new(attrs) when is_map(attrs) do
    # Extract eve_id from either eve_id or character_id field
    eve_id = extract_eve_id(attrs)

    if is_nil(eve_id) do
      raise ArgumentError, "Character must have eve_id or character_id"
    end

    name = attrs["name"] || attrs[:name]

    if is_nil(name) or name == "" do
      raise ArgumentError, "Character must have a name"
    end

    %__MODULE__{
      character_id: normalize_id(eve_id),
      name: name,
      corporation_id: parse_integer(attrs["corporation_id"] || attrs[:corporation_id]),
      alliance_id: parse_integer(attrs["alliance_id"] || attrs[:alliance_id]),
      eve_id: normalize_id(eve_id),
      corporation_ticker: attrs["corporation_ticker"] || attrs[:corporation_ticker],
      alliance_ticker: attrs["alliance_ticker"] || attrs[:alliance_ticker],
      tracked: attrs["tracked"] || attrs[:tracked] || false
    }
  end

  # Helper functions for character creation
  defp extract_eve_id(attrs) do
    attrs["eve_id"] || attrs[:eve_id] || attrs["character_id"] || attrs[:character_id]
  end

  defp normalize_id(id) when is_integer(id), do: Integer.to_string(id)
  defp normalize_id(id) when is_binary(id), do: id
  defp normalize_id(_), do: nil

  defp parse_integer(nil), do: nil
  defp parse_integer(id) when is_integer(id), do: id

  defp parse_integer(id) when is_binary(id) do
    case Integer.parse(id) do
      {int_id, ""} -> int_id
      _ -> nil
    end
  end

  defp parse_integer(_), do: nil

  @doc """
  Safe constructor that returns {:ok, character} or {:error, reason}.
  """
  @spec new_safe(map()) :: {:ok, t()} | {:error, term()}
  def new_safe(attrs) when is_map(attrs) do
    try do
      character = new(attrs)
      {:ok, character}
    rescue
      e in ArgumentError -> {:error, e.message}
      e -> {:error, "Failed to create character: #{inspect(e)}"}
    end
  end

  # ══════════════════════════════════════════════════════════════════════════════
  # Entity Helper Functions
  # ══════════════════════════════════════════════════════════════════════════════

  @doc """
  Checks if the character has corporation information.
  """
  @spec has_corporation?(t()) :: boolean()
  def has_corporation?(%__MODULE__{} = character) do
    not is_nil(character.corporation_id) and not is_nil(character.corporation_ticker)
  end

  # ══════════════════════════════════════════════════════════════════════════════
  # TrackingBehaviour Implementation
  # ══════════════════════════════════════════════════════════════════════════════

  @impl true
  def is_tracked?(character_id) when is_binary(character_id) do
    case Cache.get("map:character_list") do
      {:ok, characters} when is_list(characters) ->
        tracked = Enum.any?(characters, &(&1["eve_id"] == character_id))
        {:ok, tracked}

      {:ok, _} ->
        {:ok, false}

      {:error, :not_found} ->
        {:ok, false}
    end
  end

  def is_tracked?(character_id) when is_integer(character_id) do
    is_tracked?(Integer.to_string(character_id))
  end

  @impl true
  def is_tracked?(_), do: {:error, :invalid_character_id}

  # ══════════════════════════════════════════════════════════════════════════════
  # Simple Constructor Functions
  # ══════════════════════════════════════════════════════════════════════════════

  @doc """
  Creates a character struct from API data.
  """
  @spec from_api_data(map()) :: t()
  def from_api_data(data) when is_map(data) do
    %__MODULE__{
      character_id: get_string(data, "eve_id"),
      name: get_string(data, "name"),
      corporation_id: get_integer(data, "corporation_id"),
      alliance_id: get_integer(data, "alliance_id"),
      eve_id: get_string(data, "eve_id"),
      corporation_ticker: get_string(data, "corporation_ticker"),
      alliance_ticker: get_string(data, "alliance_ticker"),
      tracked: true
    }
  end

  @doc """
  Gets character information from cache.
  """
  @spec get_character(String.t()) :: {:ok, t()} | {:error, term()}
  def get_character(character_id) when is_binary(character_id) do
    case Cache.get("map:character_list") do
      {:ok, characters} when is_list(characters) ->
        case Enum.find(characters, &(&1["eve_id"] == character_id)) do
          nil -> {:error, :not_found}
          character_data -> {:ok, from_api_data(character_data)}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  def get_character(character_id) when is_integer(character_id) do
    get_character(Integer.to_string(character_id))
  end

  # ══════════════════════════════════════════════════════════════════════════════
  # Utility Functions
  # ══════════════════════════════════════════════════════════════════════════════

  @spec get_string(map(), String.t()) :: String.t() | nil
  defp get_string(data, key) do
    case Map.get(data, key) do
      value when is_binary(value) -> value
      value when is_integer(value) -> Integer.to_string(value)
      _ -> nil
    end
  end

  @spec get_integer(map(), String.t()) :: integer() | nil
  defp get_integer(data, key) do
    case Map.get(data, key) do
      value when is_integer(value) ->
        value

      value when is_binary(value) ->
        case Integer.parse(value) do
          {int, ""} -> int
          _ -> nil
        end

      _ ->
        nil
    end
  end
end
