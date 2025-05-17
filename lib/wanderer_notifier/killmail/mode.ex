defmodule WandererNotifier.Killmail.Mode do
  @moduledoc """
  Defines the processing modes for killmail processing.

  Note: This module is deprecated as the historical/realtime distinction is no longer used.
  It is maintained for backwards compatibility.
  """

  @type t :: :historical | :realtime | :default

  @type options :: %{
          optional(:batch_size) => pos_integer(),
          optional(:concurrency) => pos_integer(),
          optional(:retry_attempts) => non_neg_integer(),
          optional(:retry_delay) => pos_integer()
        }

  defstruct [:mode, :options]

  @doc """
  Creates a new mode struct with the given mode and options.

  Note: This function is deprecated but maintained for compatibility.
  """
  @spec new(t(), options()) :: %__MODULE__{}
  def new(mode, options \\ %{}) do
    %__MODULE__{
      mode: mode,
      options: Map.merge(default_options(mode), options)
    }
  end

  @doc """
  Returns the default options for a given mode.

  Note: This function is deprecated but maintained for compatibility.
  """
  @spec default_options(t()) :: options()
  def default_options(:historical) do
    %{
      batch_size: 100,
      concurrency: 5,
      retry_attempts: 3,
      retry_delay: 1000
    }
  end

  def default_options(:realtime) do
    %{
      batch_size: 1,
      concurrency: 1,
      retry_attempts: 3,
      retry_delay: 1000
    }
  end

  def default_options(:default) do
    %{
      batch_size: 1,
      concurrency: 1,
      retry_attempts: 3,
      retry_delay: 1000
    }
  end
end
