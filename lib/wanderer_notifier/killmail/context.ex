defmodule WandererNotifier.Killmail.Context do
  @moduledoc """
  Defines the context for killmail processing, containing all necessary information
  for processing a killmail through the pipeline.

  This module implements the Access behaviour, allowing field access with pattern matching
  and providing a consistent interface for passing processing context through the
  killmail pipeline.
  """

  @type t :: %__MODULE__{
          # Essential killmail data
          killmail_id: String.t() | integer() | nil,
          system_id: integer() | nil,
          system_name: String.t() | nil,
          # A simple map of additional options
          options: map()
        }

  defstruct [
    :killmail_id,
    :system_id,
    :system_name,
    :options
  ]

  # Implement the Access behaviour for the Context struct
  @behaviour Access

  @impl Access
  @spec fetch(t(), atom()) :: {:ok, any()} | :error
  def fetch(struct, key) when is_atom(key) do
    Map.fetch(struct, key)
  end

  # This is not part of the Access behaviour, but a helpful utility function
  @spec get(t(), atom(), any()) :: any()
  def get(struct, key, default \\ nil) do
    Map.get(struct, key, default)
  end

  @impl Access
  @spec get_and_update(t(), atom(), (any() -> {any(), any()})) :: {any(), t()}
  def get_and_update(struct, key, fun) when is_atom(key) do
    current = Map.get(struct, key)
    {get, update} = fun.(current)
    {get, Map.put(struct, key, update)}
  end

  @impl Access
  @spec pop(t(), atom()) :: {any(), t()}
  def pop(struct, key) when is_atom(key) do
    value = Map.get(struct, key)
    {value, Map.put(struct, key, nil)}
  end

  @doc """
  Creates a new context for killmail processing.

  ## Parameters
  - killmail_id: The ID of the killmail
  - system_name: The name of the system where the kill occurred
  - options: Additional options for processing

  ## Returns
  A new context struct
  """
  @spec new(String.t() | integer() | nil, String.t() | nil, map()) :: t()
  def new(killmail_id \\ nil, system_name \\ nil, options \\ %{}) do
    %__MODULE__{
      killmail_id: killmail_id,
      system_id: nil,
      system_name: system_name || "Unknown",
      options: options
    }
  end
end
