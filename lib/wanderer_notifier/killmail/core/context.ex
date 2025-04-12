defmodule WandererNotifier.Killmail.Core.Context do
  @moduledoc """
  Context information for killmail processing.

  This module provides a structured way to pass context information through
  the killmail processing pipeline, including:
  - Source of the killmail (websocket, API, etc.)
  - Processing mode (realtime, historical, etc.)
  - Character information if applicable
  - Additional metadata
  """

  alias WandererNotifier.Killmail.Core.Mode

  @type source :: :websocket | :api | :test | :manual | atom()
  @type mode :: :realtime | :historical | :batch | :test | atom()

  @type t :: %__MODULE__{
          character_id: integer() | nil,
          character_name: String.t() | nil,
          source: source(),
          mode: Mode.t(),
          metadata: map(),
          batch_id: String.t() | nil
        }

  defstruct character_id: nil,
            character_name: nil,
            source: :unknown,
            mode: :unknown,
            metadata: %{},
            batch_id: nil

  @doc """
  Creates a new context for historical processing.

  ## Parameters
    - character_id: Optional character ID associated with the killmail
    - character_name: Optional character name
    - source: Source of the killmail
    - batch_id: ID of the processing batch
    - options: Additional options

  ## Returns
    - New Context struct
  """
  @spec new_historical(integer() | nil, String.t() | nil, source(), String.t(), map()) :: t()
  def new_historical(character_id, character_name, source, batch_id, options \\ %{}) do
    # Extract metadata from options if present
    metadata = Map.get(options, :metadata, %{})

    # Extract mode_options if present, otherwise use empty map
    mode_options = Map.get(options, :mode_options, %{})

    %__MODULE__{
      character_id: character_id,
      character_name: character_name,
      source: source,
      mode: Mode.new(:historical, mode_options),
      metadata: metadata,
      batch_id: batch_id
    }
  end

  @doc """
  Creates a new context for realtime processing.

  ## Parameters
    - character_id: Optional character ID associated with the killmail
    - character_name: Optional character name
    - source: Source of the killmail
    - options: Additional options

  ## Returns
    - New Context struct
  """
  @spec new_realtime(integer() | nil, String.t() | nil, source(), map()) :: t()
  def new_realtime(character_id, character_name, source, options \\ %{}) do
    # Extract metadata from options if present
    metadata = Map.get(options, :metadata, %{})

    # Extract mode_options if present, otherwise use empty map
    mode_options = Map.get(options, :mode_options, %{})

    %__MODULE__{
      character_id: character_id,
      character_name: character_name,
      source: source,
      mode: Mode.new(:realtime, mode_options),
      metadata: metadata,
      batch_id: nil
    }
  end

  @doc """
  Checks if the context is for historical processing.

  ## Parameters
    - context: The context to check

  ## Returns
    - true if historical, false otherwise
  """
  @spec historical?(t()) :: boolean()
  def historical?(%__MODULE__{mode: %Mode{mode: :historical}}), do: true
  def historical?(%__MODULE__{mode: :historical}), do: true
  def historical?(_), do: false

  @doc """
  Checks if the context is for realtime processing.

  ## Parameters
    - context: The context to check

  ## Returns
    - true if realtime, false otherwise
  """
  @spec realtime?(t()) :: boolean()
  def realtime?(%__MODULE__{mode: %Mode{mode: :realtime}}), do: true
  def realtime?(%__MODULE__{mode: :realtime}), do: true
  def realtime?(_), do: false
end
