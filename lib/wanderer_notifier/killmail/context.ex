defmodule WandererNotifier.Killmail.Context do
  @moduledoc """
  Defines the context for killmail processing, containing all necessary information
  for processing a killmail through the pipeline.

  This module implements the Access behavior, allowing field access with pattern matching
  and providing a consistent interface for passing processing context through the
  killmail pipeline.
  """

  @type source :: :zkill_websocket | :zkill_api

  @type t :: %__MODULE__{
          # All contexts use default mode, so we keep it simple
          character_id: pos_integer() | nil,
          character_name: String.t() | nil,
          source: source(),
          batch_id: String.t() | nil,
          options: map()
        }

  defstruct [
    :character_id,
    :character_name,
    :source,
    :batch_id,
    :options
  ]

  # Implement the Access behaviour for the Context struct
  @behaviour Access

  @impl Access
  def fetch(struct, key) when is_atom(key) do
    Map.fetch(struct, key)
  end

  # This is not part of the Access behaviour, but a helpful utility function
  def get(struct, key, default \\ nil) do
    Map.get(struct, key, default)
  end

  @impl Access
  def get_and_update(struct, key, fun) when is_atom(key) do
    current = Map.get(struct, key)
    {get, update} = fun.(current)
    {get, Map.put(struct, key, update)}
  end

  @impl Access
  def pop(struct, key) when is_atom(key) do
    value = Map.get(struct, key)
    {value, Map.put(struct, key, nil)}
  end

  @doc """
  Creates a new context with the provided parameters.

  ## Parameters

  - `character_id` - The character ID associated with the killmail
  - `character_name` - The character name associated with the killmail
  - `source` - The source of the killmail (`:zkill_websocket` or `:zkill_api`)
  - `options` - Additional options to be included in the context

  ## Examples

      iex> Context.new(123, "Player", :zkill_websocket, %{processing_info: "test"})
      %Context{
        character_id: 123,
        character_name: "Player",
        source: :zkill_websocket,
        batch_id: nil,
        options: %{processing_info: "test"}
      }
  """
  @spec new(pos_integer() | nil, String.t() | nil, source() | nil, map()) :: t()
  def new(character_id \\ nil, character_name \\ nil, source \\ nil, options \\ %{}) do
    %__MODULE__{
      character_id: character_id,
      character_name: character_name,
      source: source || :zkill_api,
      batch_id: nil,
      options: options
    }
  end
end
