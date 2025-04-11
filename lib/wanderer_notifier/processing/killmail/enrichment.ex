defmodule WandererNotifier.Processing.Killmail.Enrichment do
  @moduledoc """
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

  alias WandererNotifier.Api.ESI.Service, as: ESIService
  alias WandererNotifier.KillmailProcessing.KillmailData
  alias WandererNotifier.Logger.Logger, as: AppLogger

  @doc """
  Main enrichment function that performs all enrichment steps in sequence.

  This is the primary entry point for enrichment that other modules should call.

  ## Parameters
    - killmail: A KillmailData struct to enrich

  ## Returns
    - {:ok, killmail} with the enriched KillmailData struct
    - {:error, reason} if any enrichment step fails
  """
  @spec enrich(KillmailData.t()) :: {:ok, KillmailData.t()} | {:error, any()}
  def enrich(%KillmailData{} = killmail) do
    AppLogger.kill_debug("Starting enrichment for killmail ##{killmail.killmail_id}")

    with {:ok, with_system} <- enrich_system_data(killmail),
         {:ok, with_victim} <- enrich_victim_data(with_system),
         {:ok, with_attackers} <- enrich_attacker_data(with_victim) do
      AppLogger.kill_debug("Successfully enriched killmail ##{killmail.killmail_id}")
      {:ok, with_attackers}
    else
      {:error, stage, reason} ->
        AppLogger.kill_error("Enrichment failed at #{stage} stage: #{inspect(reason)}")
        {:error, {stage, reason}}

      error ->
        AppLogger.kill_error("Unexpected error during enrichment: #{inspect(error)}")
        {:error, {:unexpected, error}}
    end
  end

  def enrich(other) do
    AppLogger.kill_error("Cannot enrich non-KillmailData value: #{inspect(other)}")
    {:error, {:invalid_data_type, "Expected KillmailData struct"}}
  end

  @doc """
  Enriches system data in the killmail, ensuring system name is present.

  ## Parameters
    - killmail: A KillmailData struct

  ## Returns
    - {:ok, killmail} with enriched system data
    - {:error, reason} if enrichment fails
  """
  @spec enrich_system_data(KillmailData.t()) :: {:ok, KillmailData.t()} | {:error, any()}
  def enrich_system_data(%KillmailData{} = killmail) do
    # If we already have a system name, just return the killmail
    if is_binary(killmail.solar_system_name) && killmail.solar_system_name != "" do
      {:ok, killmail}
    else
      # If we have a system ID but no name, look up the name
      case killmail.solar_system_id do
        nil ->
          {:error, :system, "Missing solar system ID"}

        system_id ->
          case ESIService.get_solar_system_name(system_id) do
            {:ok, %{"name" => name}} when is_binary(name) and name != "" ->
              {:ok, %{killmail | solar_system_name: name}}

            error ->
              AppLogger.kill_error(
                "Failed to get system name for ID #{system_id}: #{inspect(error)}"
              )

              # Set a placeholder name but return success - this is non-critical
              {:ok, %{killmail | solar_system_name: "Unknown System"}}
          end
      end
    end
  end

  @doc """
  Enriches victim data in the killmail, adding character and ship names.

  ## Parameters
    - killmail: A KillmailData struct

  ## Returns
    - {:ok, killmail} with enriched victim data
    - {:error, reason} if critical enrichment fails
  """
  @spec enrich_victim_data(KillmailData.t()) :: {:ok, KillmailData.t()} | {:error, any()}
  def enrich_victim_data(%KillmailData{} = killmail) do
    # Start with the original killmail for enrichment
    enriched_killmail = killmail

    # Enrich character name if we have an ID but no name
    enriched_killmail =
      if is_nil(enriched_killmail.victim_name) && !is_nil(enriched_killmail.victim_id) do
        case get_character_name(enriched_killmail.victim_id) do
          {:ok, name} when is_binary(name) ->
            %{enriched_killmail | victim_name: name}

          _ ->
            %{enriched_killmail | victim_name: "Unknown Pilot"}
        end
      else
        # We already have a name or no ID to look up - ensure a default if nil
        if is_nil(enriched_killmail.victim_name) do
          %{enriched_killmail | victim_name: "Unknown Pilot"}
        else
          enriched_killmail
        end
      end

    # Enrich ship name if we have an ID but no name
    enriched_killmail =
      if is_nil(enriched_killmail.victim_ship_name) && !is_nil(enriched_killmail.victim_ship_id) do
        case get_ship_name(enriched_killmail.victim_ship_id) do
          {:ok, name} when is_binary(name) ->
            %{enriched_killmail | victim_ship_name: name}

          _ ->
            %{enriched_killmail | victim_ship_name: "Unknown Ship"}
        end
      else
        # We already have a name or no ID to look up - ensure a default if nil
        if is_nil(enriched_killmail.victim_ship_name) do
          %{enriched_killmail | victim_ship_name: "Unknown Ship"}
        else
          enriched_killmail
        end
      end

    # Return the enriched killmail
    {:ok, enriched_killmail}
  end

  @doc """
  Enriches attacker data in the killmail, adding character and ship names.

  ## Parameters
    - killmail: A KillmailData struct

  ## Returns
    - {:ok, killmail} with enriched attacker data
    - {:error, reason} if critical enrichment fails
  """
  @spec enrich_attacker_data(KillmailData.t()) :: {:ok, KillmailData.t()} | {:error, any()}
  def enrich_attacker_data(%KillmailData{} = killmail) do
    # If we don't have any attackers, just return the killmail
    if is_nil(killmail.attackers) || killmail.attackers == [] do
      {:ok, killmail}
    else
      # Process each attacker to add names
      enriched_attackers =
        Enum.map(killmail.attackers, fn attacker ->
          enrich_attacker(attacker)
        end)

      # Update the attackers list and count
      enriched_killmail = %{
        killmail
        | attackers: enriched_attackers,
          attacker_count: length(enriched_attackers)
      }

      # Find final blow attacker
      final_blow =
        Enum.find(enriched_attackers, fn attacker ->
          Map.get(attacker, "final_blow", false) == true
        end)

      # Ensure final blow attacker data is at the top level
      enriched_killmail =
        if final_blow do
          %{
            enriched_killmail
            | final_blow_attacker_id: Map.get(final_blow, "character_id"),
              final_blow_attacker_name: Map.get(final_blow, "character_name"),
              final_blow_ship_id: Map.get(final_blow, "ship_type_id"),
              final_blow_ship_name: Map.get(final_blow, "ship_type_name")
          }
        else
          enriched_killmail
        end

      {:ok, enriched_killmail}
    end
  end

  # Helper to enrich a single attacker map with names
  defp enrich_attacker(attacker) when is_map(attacker) do
    # Enrich with character name if needed
    attacker =
      if !Map.has_key?(attacker, "character_name") || Map.get(attacker, "character_name") == nil do
        character_id = Map.get(attacker, "character_id")

        if character_id do
          case get_character_name(character_id) do
            {:ok, name} when is_binary(name) ->
              Map.put(attacker, "character_name", name)

            _ ->
              Map.put(attacker, "character_name", "Unknown Attacker")
          end
        else
          Map.put(attacker, "character_name", "Unknown Attacker")
        end
      else
        attacker
      end

    # Enrich with ship name if needed
    attacker =
      if !Map.has_key?(attacker, "ship_type_name") || Map.get(attacker, "ship_type_name") == nil do
        ship_id = Map.get(attacker, "ship_type_id")

        if ship_id do
          case get_ship_name(ship_id) do
            {:ok, name} when is_binary(name) ->
              Map.put(attacker, "ship_type_name", name)

            _ ->
              Map.put(attacker, "ship_type_name", "Unknown Ship")
          end
        else
          Map.put(attacker, "ship_type_name", "Unknown Ship")
        end
      else
        attacker
      end

    attacker
  end

  defp enrich_attacker(nil),
    do: %{"character_name" => "Unknown Attacker", "ship_type_name" => "Unknown Ship"}

  # Helper functions for external API calls

  # Get character name from ESI or cache
  defp get_character_name(character_id)
       when is_integer(character_id) or is_binary(character_id) do
    # Check if we have it in the repository first (which includes cache)
    case WandererNotifier.Data.Repository.get_character_name(character_id) do
      {:ok, name} when is_binary(name) and name != "" ->
        {:ok, name}

      _ ->
        # Fall back to direct ESI call
        case ESIService.get_character_name(character_id) do
          {:ok, %{"name" => name}} when is_binary(name) and name != "" ->
            {:ok, name}

          {:ok, %{name: name}} when is_binary(name) and name != "" ->
            {:ok, name}

          _ ->
            {:error, :not_found}
        end
    end
  end

  defp get_character_name(_), do: {:error, :invalid_character_id}

  # Get ship name from ESI or cache
  defp get_ship_name(ship_id) when is_integer(ship_id) or is_binary(ship_id) do
    case ESIService.get_type_name(ship_id) do
      {:ok, %{"name" => name}} when is_binary(name) and name != "" ->
        {:ok, name}

      _ ->
        {:error, :not_found}
    end
  end

  defp get_ship_name(_), do: {:error, :invalid_ship_id}
end
