defmodule WandererNotifier.Processing.Killmail.Enrichment do
  @moduledoc """
  DEPRECATED: This module is deprecated and will be removed in a future version.

  Please use WandererNotifier.Killmail.Processing.Enrichment instead.

  Module for enriching killmail data with additional information.

  This module provides functions to enhance killmail data with information from
  external sources like ESI, including:

  - Solar system names
  - Character names
  - Ship type names
  - Corporation names
  - Alliance names

  All enrichment functions operate on and return KillmailData structs.
  """

  @deprecated "Use WandererNotifier.Killmail.Processing.Enrichment instead"

  alias WandererNotifier.Killmail.Processing.Enrichment, as: NewEnrichment
  alias WandererNotifier.KillmailProcessing.KillmailData

  @doc """
  Main enrichment function that performs all enrichment steps in sequence.

  DEPRECATED: Use WandererNotifier.Killmail.Processing.Enrichment.enrich/1 instead.

  This is the primary entry point for enrichment that other modules should call.

  ## Parameters
    - killmail: A KillmailData struct to enrich

  ## Returns
    - {:ok, killmail} with the enriched KillmailData struct
    - {:error, reason} if any enrichment step fails
  """
  @deprecated "Use WandererNotifier.Killmail.Processing.Enrichment.enrich/1 instead"
  @spec enrich(KillmailData.t()) :: {:ok, KillmailData.t()} | {:error, any()}
  def enrich(%KillmailData{} = killmail) do
    NewEnrichment.enrich(killmail)
  end

  def enrich(other) do
    NewEnrichment.enrich(other)
  end

  @doc """
  Enriches system data in the killmail, ensuring system name is present.

  DEPRECATED: Use WandererNotifier.Killmail.Processing.Enrichment instead.

  ## Parameters
    - killmail: A KillmailData struct

  ## Returns
    - {:ok, killmail} with enriched system data
    - {:error, reason} if enrichment fails
  """
  @deprecated "Use WandererNotifier.Killmail.Processing.Enrichment instead"
  @spec enrich_system_data(KillmailData.t()) :: {:ok, KillmailData.t()} | {:error, any()}
  def enrich_system_data(%KillmailData{} = killmail) do
    # Delegate to the new enrich method - we don't have direct access to the system data function
    # but we can enrich and return
    case NewEnrichment.enrich(killmail) do
      {:ok, enriched} -> {:ok, enriched}
      error -> error
    end
  end

  @doc """
  Enriches victim data in the killmail, adding character and ship names.

  DEPRECATED: Use WandererNotifier.Killmail.Processing.Enrichment instead.

  ## Parameters
    - killmail: A KillmailData struct

  ## Returns
    - {:ok, killmail} with enriched victim data
    - {:error, reason} if critical enrichment fails
  """
  @deprecated "Use WandererNotifier.Killmail.Processing.Enrichment instead"
  @spec enrich_victim_data(KillmailData.t()) :: {:ok, KillmailData.t()} | {:error, any()}
  def enrich_victim_data(%KillmailData{} = killmail) do
    # Delegate to the new enrich method - we don't have direct access to the victim data function
    # but we can enrich and return
    case NewEnrichment.enrich(killmail) do
      {:ok, enriched} -> {:ok, enriched}
      error -> error
    end
  end

  @doc """
  Enriches attacker data in the killmail, adding character and ship names.

  DEPRECATED: Use WandererNotifier.Killmail.Processing.Enrichment instead.

  ## Parameters
    - killmail: A KillmailData struct

  ## Returns
    - {:ok, killmail} with enriched attacker data
    - {:error, reason} if critical enrichment fails
  """
  @deprecated "Use WandererNotifier.Killmail.Processing.Enrichment instead"
  @spec enrich_attacker_data(KillmailData.t()) :: {:ok, KillmailData.t()} | {:error, any()}
  def enrich_attacker_data(%KillmailData{} = killmail) do
    # Delegate to the new enrich method - we don't have direct access to the attacker data function
    # but we can enrich and return
    case NewEnrichment.enrich(killmail) do
      {:ok, enriched} -> {:ok, enriched}
      error -> error
    end
  end

  @doc """
  Processes and enriches a killmail, then checks if notification is needed.

  DEPRECATED: Use WandererNotifier.Killmail.Processing.Enrichment.process_and_notify/1 instead.

  ## Parameters
    - killmail: A KillmailData struct

  ## Returns
    - {:ok, killmail} with the enriched KillmailData that should be notified
    - {:ok, :skipped} when notification is not needed
    - {:error, reason} if processing fails
  """
  @deprecated "Use WandererNotifier.Killmail.Processing.Enrichment.process_and_notify/1 instead"
  @spec process_and_notify(KillmailData.t()) ::
          {:ok, KillmailData.t()} | {:ok, :skipped} | {:error, any()}
  def process_and_notify(%KillmailData{} = killmail) do
    NewEnrichment.process_and_notify(killmail)
  end

  def process_and_notify(other) do
    NewEnrichment.process_and_notify(other)
  end
end
