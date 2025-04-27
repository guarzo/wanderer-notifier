defmodule WandererNotifier.Killmail.Context do
  @moduledoc """
  Defines the context for killmail processing, containing all necessary information
  for processing a killmail in either historical or realtime mode.
  """

  alias WandererNotifier.Killmail.Mode

  @type source :: :zkill_websocket | :zkill_api

  @type t :: %__MODULE__{
          mode: Mode.t(),
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

  @doc """
  Creates a new context for historical processing.
  """
  @spec new_historical(pos_integer(), String.t(), source(), String.t(), map()) :: t()
  def new_historical(character_id, character_name, source, batch_id, options \\ %{}) do
    %__MODULE__{
      mode: Mode.new(:historical),
      character_id: character_id,
      character_name: character_name,
      source: source,
      batch_id: batch_id,
      options: options
    }
  end

  @doc """
  Creates a new context for realtime processing.
  """
  @spec new_realtime(pos_integer(), String.t(), source(), map()) :: t()
  def new_realtime(character_id, character_name, source, options \\ %{}) do
    %__MODULE__{
      mode: Mode.new(:realtime),
      character_id: character_id,
      character_name: character_name,
      source: source,
      batch_id: nil,
      options: options
    }
  end

  @doc """
  Returns true if the context is for historical processing.
  """
  @spec historical?(t()) :: boolean()
  def historical?(%__MODULE__{mode: %{mode: :historical}}), do: true
  def historical?(_), do: false

  @doc """
  Returns true if the context is for realtime processing.
  """
  @spec realtime?(t()) :: boolean()
  def realtime?(%__MODULE__{mode: %{mode: :realtime}}), do: true
  def realtime?(_), do: false
end
