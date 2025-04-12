defmodule WandererNotifier.Killmail.Core.Mode do
  @moduledoc """
  Represents the processing mode for killmail data.

  This module defines a struct with the processing mode and any associated options.
  Processing modes include:
  - `:realtime` - for kills processed in real-time from the websocket
  - `:historical` - for kills processed from historical data
  - `:manual` - for kills processed via manual user action
  - `:batch` - for kills processed in a batch operation
  """

  @type t :: %__MODULE__{
          mode: atom(),
          options: options()
        }

  @type options :: %{
          optional(atom()) => any()
        }

  defstruct mode: :unknown, options: %{}

  @doc """
  Creates a new Mode struct with the specified mode and options.

  ## Parameters
    - mode: The processing mode (:realtime, :historical, :manual, :batch)
    - options: Map of options specific to the mode

  ## Returns
    - Mode struct
  """
  @spec new(atom(), options()) :: t()
  def new(mode, options \\ %{}) when is_atom(mode) and is_map(options) do
    # Merge passed options with defaults
    merged_options = Map.merge(default_options(mode), options)
    %__MODULE__{mode: mode, options: merged_options}
  end

  @doc """
  Returns the default options for a specific mode.

  ## Parameters
    - mode: The processing mode

  ## Returns
    - Map of default options for the mode
  """
  @spec default_options(atom()) :: options()
  def default_options(:realtime), do: %{persist: true, notify: true, cache: true}
  def default_options(:historical), do: %{persist: true, notify: false, cache: true}
  def default_options(:manual), do: %{persist: true, notify: true, cache: true}
  def default_options(:batch), do: %{persist: true, notify: false, cache: true}
  def default_options(_), do: %{persist: true, notify: false, cache: true}
end
