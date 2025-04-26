defmodule WandererNotifier.Processing.Killmail.Core do
  @moduledoc """
  Core killmail processing functionality.
  Provides a standardized pipeline for processing killmails from any source.
  """

  alias WandererNotifier.Api.ESI.Service, as: ESIService
  alias WandererNotifier.Api.ZKill.Client, as: ZKillClient
  alias WandererNotifier.Data.{Killmail, Repository}
  alias WandererNotifier.Logger.Logger, as: AppLogger
  alias WandererNotifier.Notifications.Determiner.Kill, as: KillDeterminer
  alias WandererNotifier.Processing.Killmail.Enrichment

  @doc """
  Process a killmail with pre-fetched ZKillboard data.

  ## Parameters
    - kill_id: The killmail ID
    - hash: The killmail hash (from zKillboard)
    - zkb_data: Pre-fetched ZKillboard data
    - character_id: Optional character ID for persistence
    - character_name: Optional character name for logging

  ## Returns
    - {:ok, enriched_killmail} on success
    - {:error, reason} on failure
  """
  def process_kill_with_data(kill_id, hash, zkb_data, character_id, character_name) do
    _start_time = System.monotonic_time()

    with {:ok, enriched} <- ESIService.get_killmail(kill_id, hash),
         killmail <- create_killmail(kill_id, zkb_data, enriched),
         {:ok, result} <- process_enrichment(killmail),
         {:ok, final_result} <-
           handle_enrichment_result(result, killmail, character_id, character_name) do
      {:ok, final_result}
    else
      error ->
        log_error(error, kill_id, character_id, character_name)
        error
    end
  end

  defp create_killmail(kill_id, zkb_data, enriched) do
    zkb_map = Map.get(zkb_data, "zkb", %{})
    Killmail.new(kill_id, zkb_map, enriched)
  end

  defp process_enrichment(killmail) do
    case Enrichment.process_and_notify(killmail) do
      :ok -> {:ok, killmail}
      {:ok, :skipped} -> {:ok, :skipped}
      error -> error
    end
  end

  defp handle_enrichment_result(:skipped, _killmail, _character_id, _character_name) do
    {:ok, :skipped}
  end

  defp handle_enrichment_result(processed_killmail, _killmail, _character_id, _character_name) do
    with {:ok, %{should_notify: should_notify}} <- check_notification(processed_killmail) do
      {:ok, if(should_notify, do: :notified, else: :skipped)}
    end
  end

  defp check_notification(killmail) do
    KillDeterminer.should_notify?(killmail)
  end

  defp log_error(error, kill_id, character_id, character_name) do
    AppLogger.processor_error("Failed to process kill", %{
      kill_id: kill_id,
      character_id: character_id,
      character_name: character_name,
      error: inspect(error)
    })
  end

  defp fetch_zkb_data(kill_id) do
    with {:ok, [zkb_data | _]} <- ZKillClient.get_single_killmail(kill_id),
         zkb_map <- Map.get(zkb_data, "zkb", %{}),
         hash <- Map.get(zkb_map, "hash") do
      {:ok, {zkb_data, hash}}
    else
      error -> error
    end
  end

  @doc """
  Process a killmail through the standardized pipeline.

  ## Parameters
    - kill_id: The killmail ID
    - hash: The killmail hash (from zKillboard)
    - character_id: Optional character ID for persistence
    - character_name: Optional character name for logging

  ## Returns
    - {:ok, enriched_killmail} on success
    - {:error, reason} on failure
  """
  def process_kill(kill_id, hash, character_id, character_name) do
    with {:ok, [zkb_data | _]} <- ZKillClient.get_single_killmail(kill_id) do
      process_kill_with_data(kill_id, hash, zkb_data, character_id, character_name)
    end
  end

  @doc """
  Process a killmail from ZKillboard with character information.

  ## Parameters
    - kill_id: The killmail ID
    - character_id: Optional character ID for persistence

  ## Returns
    - {:ok, enriched_killmail} on success
    - {:error, reason} on failure
  """
  def process_kill_from_zkb(kill_id, character_id \\ nil) do
    character_name =
      case Repository.get_character_name(character_id) do
        {:ok, name} -> name
        _ -> "Unknown"
      end

    with {:ok, {zkb_data, hash}} <- fetch_zkb_data(kill_id) do
      process_kill_with_data(kill_id, hash, zkb_data, character_id, character_name)
    end
  end
end
