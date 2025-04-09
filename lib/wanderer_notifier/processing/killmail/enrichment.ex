defmodule WandererNotifier.Processing.Killmail.Enrichment do
  @moduledoc """
  Module for enriching killmail data with additional information.
  Retrieves solar system names, character names, and other details.
  """

  alias WandererNotifier.Api.ESI.Service, as: ESIService
  alias WandererNotifier.Logger.Logger, as: AppLogger
  alias WandererNotifier.KillmailProcessing.{Extractor, KillmailData}
  alias WandererNotifier.Data.Cache.Keys, as: CacheKeys
  alias WandererNotifier.Data.Cache.Repository, as: CacheRepo
  alias WandererNotifier.Processing.Killmail.Notification

  @doc """
  Process the killmail for enrichment and notification.
  Called by the Core module to process enrichment and send notification.

  ## Parameters
    - killmail: The killmail data structure

  ## Returns
    - {:ok, killmail} if processed successfully
    - {:ok, :skipped} if skipped
    - {:error, reason} if an error occurred
  """
  @spec process_and_notify(map()) :: {:ok, map() | :skipped} | {:error, any()}
  def process_and_notify(killmail) do
    # First enrich the killmail data
    enriched_killmail = enrich_killmail_data(killmail)

    # Check if notification should be sent
    case Notification.send_kill_notification(enriched_killmail, enriched_killmail.killmail_id) do
      :ok ->
        AppLogger.kill_info("[Enrichment] Successfully processed and notified killmail", %{
          killmail_id: enriched_killmail.killmail_id
        })

        {:ok, enriched_killmail}

      {:ok, :skipped} ->
        AppLogger.kill_info("[Enrichment] Killmail notification skipped", %{
          killmail_id: enriched_killmail.killmail_id
        })

        {:ok, :skipped}

      error ->
        AppLogger.kill_error("[Enrichment] Failed to process killmail notification", %{
          killmail_id: enriched_killmail.killmail_id,
          error: inspect(error)
        })

        {:error, error}
    end
  rescue
    e ->
      AppLogger.kill_error("[Enrichment] Exception in enrichment processing", %{
        killmail_id: Map.get(killmail, :killmail_id, "unknown"),
        error: Exception.message(e),
        stacktrace: Exception.format_stacktrace(__STACKTRACE__)
      })

      {:error, Exception.message(e)}
  end

  @doc """
  Enriches killmail data with additional information from ESI API.
  Retrieves solar system names, character information, etc.
  """
  @spec enrich_killmail_data(map()) :: map()
  def enrich_killmail_data(killmail) do
    # Add debug logging
    AppLogger.kill_info("[Enrichment] Starting killmail enrichment", %{
      killmail_id: Map.get(killmail, :killmail_id) || "unknown"
    })

    # Get ESI data from killmail if available
    esi_data = Map.get(killmail, :esi_data) || %{}

    # Add system name if needed
    enriched_esi_data = enrich_with_system_name(esi_data)

    # Ensure all data is complete and consistent
    complete_esi_data = ensure_complete_enrichment(enriched_esi_data)

    # Return updated killmail with enriched ESI data
    Map.put(killmail, :esi_data, complete_esi_data)
  rescue
    e ->
      AppLogger.kill_error("[Enrichment] Error enriching killmail data", %{
        error: Exception.message(e),
        stacktrace: Exception.format_stacktrace(__STACKTRACE__),
        killmail_id: Map.get(killmail, :killmail_id) || "unknown"
      })

      # Return original killmail to prevent pipeline failure
      killmail
  end

  # Enrich with system name if needed
  defp enrich_with_system_name(esi_data) when is_map(esi_data) do
    system_id = Map.get(esi_data, "solar_system_id")

    # Log the actual system ID and type for debugging
    log_system_id_info(system_id)

    if is_nil(system_id) do
      # No system ID available, can't enrich
      esi_data
    else
      # Get normalized system ID and enrich with system name
      normalized_id = normalize_system_id(system_id)
      add_system_name_to_data(esi_data, normalized_id)
    end
  end

  defp enrich_with_system_name(data), do: data

  # Log system ID type and value for debugging
  defp log_system_id_info(system_id) do
    system_type =
      cond do
        is_integer(system_id) -> "integer"
        is_binary(system_id) -> "string"
        true -> "other: #{inspect(system_id)}"
      end

    AppLogger.kill_info(
      "[Enrichment] System ID for enrichment: #{inspect(system_id)} (type: #{system_type})"
    )
  end

  # Convert system_id to integer if needed
  defp normalize_system_id(system_id) when is_binary(system_id) do
    case Integer.parse(system_id) do
      {id, _} -> id
      :error -> nil
    end
  end

  defp normalize_system_id(system_id) when is_integer(system_id), do: system_id
  defp normalize_system_id(_), do: nil

  # Add system name to ESI data
  defp add_system_name_to_data(esi_data, normalized_id) when is_integer(normalized_id) do
    case ESIService.get_solar_system_name(normalized_id) do
      {:ok, %{"name" => name}} when is_binary(name) and name != "" ->
        # Set the system name in ESI data and ensure system_id is stored as integer
        esi_data
        |> Map.put("solar_system_name", name)
        |> Map.put("solar_system_id", normalized_id)

      _ ->
        # Could not get system name, use a placeholder
        Map.put(esi_data, "solar_system_name", "Unknown System")
    end
  end

  defp add_system_name_to_data(esi_data, _) do
    Map.put(esi_data, "solar_system_name", "Unknown System")
  end

  # Ensure all enriched data is complete and consistent across the structure
  defp ensure_complete_enrichment(esi_data) when is_map(esi_data) do
    # Copy system info to victim data if needed
    system_name = Map.get(esi_data, "solar_system_name")
    victim = Map.get(esi_data, "victim")

    if is_binary(system_name) && is_map(victim) && !Map.has_key?(victim, "solar_system_name") do
      # Add system name to victim data
      updated_victim = Map.put(victim, "solar_system_name", system_name)
      Map.put(esi_data, "victim", updated_victim)
    else
      # No changes needed
      esi_data
    end
  end

  defp ensure_complete_enrichment(data), do: data

  # Direct resolution for character name
  defp apply_direct_character_resolution(entity) when is_map(entity) do
    if character_id = Map.get(entity, "character_id") do
      # Use direct ESI service call to bypass caching issues
      case ESIService.get_character_info(character_id) do
        {:ok, %{"name" => name}} when is_binary(name) and name != "" ->
          AppLogger.kill_info(
            "[Enrichment] Direct character resolution succeeded for character_id #{character_id}",
            %{
              character_id: character_id,
              old_name: Map.get(entity, "character_name"),
              new_name: name
            }
          )

          # Always update the cache with this fresh data
          cache_key = CacheKeys.character_info(character_id)
          CacheRepo.set(cache_key, %{"name" => name}, 86_400)

          # Return entity with updated name
          Map.put(entity, "character_name", name)

        error ->
          AppLogger.kill_error("[Enrichment] Direct character resolution failed", %{
            character_id: character_id,
            error: inspect(error)
          })

          entity
      end
    else
      entity
    end
  end

  defp apply_direct_character_resolution(entity), do: entity
end
