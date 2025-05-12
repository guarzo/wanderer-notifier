defmodule WandererNotifier.Killmail.Context do
  @moduledoc """
  Defines the context for killmail processing, containing all necessary information
  for processing a killmail.
  """

  @type source :: :zkill_websocket | :zkill_api

  @type t :: %__MODULE__{
          mode: map(),
          character_id: pos_integer() | nil,
          character_name: String.t() | nil,
          source: source(),
          batch_id: String.t() | nil,
          options: map()
        }

  defstruct [
    :mode,
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
  Creates a new context.
  """
  @spec new(pos_integer() | nil, String.t() | nil, source() | nil, map()) :: t()
  def new(character_id \\ nil, character_name \\ nil, source \\ nil, options \\ %{}) do
    %__MODULE__{
      mode: %{mode: :default},
      character_id: character_id,
      character_name: character_name,
      source: source || :zkill_api,
      batch_id: nil,
      options: options
    }
  end

  @doc """
  Helper function to check if the context is for realtime processing.
  Always returns true as the system now only operates in realtime mode.
  Kept for compatibility with existing code.
  """
  @spec realtime?(t()) :: boolean()
  def realtime?(_ctx), do: true
end
