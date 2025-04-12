defmodule WandererNotifier.Killmail.Processing.ProcessorBehaviour do
  @moduledoc """
  Behaviour module defining the contract for killmail processors.
  This ensures consistent interfaces for all implementations.
  """

  alias WandererNotifier.Killmail.Core.Data

  @doc """
  Processes a killmail through the complete pipeline.

  ## Parameters
    - killmail: The killmail data to process (Data struct or compatible map)
    - context: Optional processing context with metadata

  ## Returns
    - {:ok, processed_killmail} on successful processing
    - {:ok, :skipped} if the killmail was skipped
    - {:error, reason} on processing failure
  """
  @callback process_killmail(Data.t() | map(), map()) ::
              {:ok, Data.t()} | {:ok, :skipped} | {:error, any()}
end
