defmodule WandererNotifier.Killmail.Processing.EnrichmentBehaviour do
  @moduledoc """
  Behaviour definition for killmail enrichment implementations.
  """

  alias WandererNotifier.Killmail.Core.Data

  @doc """
  Enriches a killmail with additional data.
  """
  @callback enrich(Data.t()) :: {:ok, Data.t()} | {:error, any()}
end
