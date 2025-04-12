defmodule WandererNotifier.Killmail.Processing.ApiProcessor do
  @moduledoc """
  API-based killmail processing functionality.
  Provides a standardized pipeline for processing killmails from ZKillboard and ESI.
  """

  alias WandererNotifier.Api.ESI.Service, as: ESIService
  alias WandererNotifier.Api.ZKill.Client, as: ZKillClient
  alias WandererNotifier.Data.Repository

  alias WandererNotifier.Killmail.Core.Data, as: KillmailData
  alias WandererNotifier.Logger.Logger, as: AppLogger
  alias WandererNotifier.Notifications.Determiner.Kill, as: KillDeterminer
  alias WandererNotifier.Killmail.Processing.{Enrichment, Persistence}

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

    %KillmailData{
      killmail_id: kill_id,
      raw_zkb_data: zkb_map,
      raw_esi_data: enriched,
      metadata: %{source: :api_processor}
    }
  end

  defp process_enrichment(killmail) do
    case Enrichment.process_and_notify(killmail) do
      {:ok, enriched_killmail = %KillmailData{}} -> {:ok, enriched_killmail}
      {:ok, :skipped} -> {:ok, :skipped}
      error -> error
    end
  end

  defp handle_enrichment_result(:skipped, _killmail, _character_id, _character_name) do
    {:ok, :skipped}
  end

  defp handle_enrichment_result(processed_killmail, _killmail, character_id, character_name) do
    with {:ok, _} <- persist_killmail(processed_killmail, character_id, character_name),
         {:ok, %{should_notify: should_notify}} <- check_notification(processed_killmail) do
      {:ok, if(should_notify, do: :notified, else: :skipped)}
    end
  end

  defp persist_killmail(killmail, character_id, character_name) do
    case Persistence.persist_killmail(killmail, character_id) do
      {:ok, persisted_killmail, _} ->
        {:ok, persisted_killmail}

      {:error, _reason} = error ->
        log_error(error, killmail.killmail_id, character_id, character_name)
        error
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

  @doc """
  Fetches killmail data from zKillboard.

  ## Parameters
    - kill_id: The killmail ID to fetch

  ## Returns
    - {:ok, kill_data} on success where kill_data is the raw API response
    - {:error, reason} on failure
  """
  @spec get_zkill_data(integer()) :: {:ok, map()} | {:error, any()}
  def get_zkill_data(kill_id) do
    AppLogger.processor_debug("Fetching kill data from ZKillboard", kill_id: kill_id)

    case ZKillClient.get_single_killmail(kill_id) do
      {:ok, [kill_data | _]} ->
        # If it returns a list, take the first item
        {:ok, kill_data}

      {:ok, kill_data} when is_map(kill_data) ->
        # If it returns a single map
        {:ok, kill_data}

      {:error, reason} = error ->
        AppLogger.processor_error("Failed to fetch kill from ZKillboard", %{
          kill_id: kill_id,
          error: inspect(reason)
        })

        error
    end
  end

  defp fetch_zkb_data(kill_id) do
    with {:ok, zkb_data} <- get_zkill_data(kill_id),
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
    with {:ok, zkb_data} <- get_zkill_data(kill_id) do
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
