defmodule WandererNotifier.Killmail.Context do
  @moduledoc """
  Defines the context for killmail processing, containing all necessary information
  for processing a killmail through the pipeline.

  This module implements the Access behavior, allowing field access with pattern matching
  and providing a consistent interface for passing processing context through the
  killmail pipeline.
  """

  @type t :: %__MODULE__{
          # Essential killmail data
          killmail_id: String.t() | nil,
          system_name: String.t() | nil,
          # A simple map of additional options
          options: map()
        }

  defstruct [
    :killmail_id,
    :system_name,
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
  Creates a new context with the provided kill information.

  ## Parameters
  - `killmail_id` - The ID of the killmail being processed
  - `system_name` - The name of the system where the kill occurred
  - `options` - Map containing additional context information

  ## Examples
      iex> Context.new("12345", "Jita", %{source: :zkill_websocket})
      %Context{
        killmail_id: "12345",
        system_name: "Jita",
        options: %{source: :zkill_websocket}
      }
  """
  @spec new(String.t() | nil, String.t() | nil, map()) :: t()
  def new(killmail_id \\ nil, system_name \\ nil, options \\ %{}) do
    %__MODULE__{
      killmail_id: killmail_id,
      system_name: system_name,
      options: options
    }
  end
end
