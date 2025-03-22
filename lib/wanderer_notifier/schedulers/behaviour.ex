defmodule WandererNotifier.Schedulers.Behaviour do
  @moduledoc """
  Behaviour module defining the interface for standardized schedulers.

  This module defines the common interface that all schedulers must implement.
  It provides a standardized way to start, stop, and manually trigger scheduled tasks.
  """

  @doc """
  Executes the scheduled task.
  This is the main function that performs the actual work.
  """
  @callback execute(state :: map()) ::
              {:ok, result :: any(), new_state :: map()}
              | {:error, reason :: any(), new_state :: map()}

  @doc """
  Determines if the scheduler should be enabled based on configuration.
  """
  @callback enabled?() :: boolean()

  @doc """
  Returns the scheduler's configuration.
  For interval-based schedulers, this would include the interval.
  For time-based schedulers, this would include the scheduled times.
  """
  @callback get_config() :: map()
end
