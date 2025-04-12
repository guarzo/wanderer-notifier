defmodule WandererNotifier.Killmail.Processing.Enrichment do
  @moduledoc """
  Enriches Killmail data with additional information from various sources.
  This includes resolving names for entities using ESI, getting system and region names,
  and other enrichment tasks.
  """

  require Logger
  alias WandererNotifier.Killmail.Core.Data, as: KillmailData

  @doc """
  Enriches a KillmailData struct with additional information.

  ## Parameters
  - killmail: KillmailData struct to enrich

  ## Returns
  - {:ok, enriched_killmail} - Enriched KillmailData struct
  - {:error, reason} - If enrichment fails
  """
  @spec enrich(KillmailData.t()) :: {:ok, KillmailData.t()} | {:error, term()}
  def enrich(%KillmailData{} = killmail) do
    enriched =
      killmail
      |> enrich_system_info()
      |> enrich_character_names()
      |> enrich_ship_names()
      |> enrich_corporation_names()

    {:ok, enriched}
  end

  def enrich(_invalid_data) do
    {:error, :invalid_data_type}
  end

  @doc """
  Processes a KillmailData struct, enriches it, and checks if a notification should be sent.

  ## Parameters
  - killmail: KillmailData struct to process

  ## Returns
  - {:ok, enriched_killmail} - If the killmail should trigger a notification
  - {:ok, :skipped} - If the killmail should not trigger a notification
  - {:error, reason} - If processing fails
  """
  @spec process_and_notify(KillmailData.t()) ::
          {:ok, KillmailData.t() | :skipped} | {:error, term()}
  def process_and_notify(%KillmailData{} = killmail) do
    kill_determiner =
      Application.get_env(
        :wanderer_notifier,
        :kill_determiner_module,
        WandererNotifier.Notifications.Determiner.Kill
      )

    with {:ok, enriched} <- enrich(killmail),
         {:ok, %{should_notify: true}} <- kill_determiner.should_notify?(enriched) do
      {:ok, enriched}
    else
      {:ok, %{should_notify: false}} -> {:ok, :skipped}
      {:error, reason} -> {:error, reason}
    end
  end

  def process_and_notify(_invalid_data) do
    {:error, :invalid_data_type}
  end

  # Private helper functions

  defp enrich_system_info(%KillmailData{solar_system_id: nil} = killmail) do
    # If no system ID is available, skip this enrichment
    killmail
  end

  defp enrich_system_info(%KillmailData{solar_system_id: system_id} = killmail) do
    map_systems_module =
      Application.get_env(
        :wanderer_notifier,
        :map_systems_module,
        WandererNotifier.Api.Map.Systems
      )

    case map_systems_module.get_system_info(system_id) do
      {:ok, system_info} ->
        %KillmailData{
          killmail
          | solar_system_name: Map.get(system_info, "name"),
            region_id: Map.get(system_info, "region_id"),
            region_name: Map.get(system_info, "region_name")
        }

      {:error, reason} ->
        # Log error but continue with enrichment
        Logger.warning("Failed to get system info for system_id #{system_id}: #{inspect(reason)}")
        killmail
    end
  end

  defp enrich_character_names(killmail) do
    killmail
    |> enrich_victim_name()
    |> enrich_attacker_names()
  end

  defp enrich_victim_name(%KillmailData{victim_id: nil} = killmail), do: killmail

  defp enrich_victim_name(%KillmailData{victim_id: character_id} = killmail) do
    esi_service =
      Application.get_env(
        :wanderer_notifier,
        :esi_service_module,
        WandererNotifier.Api.ESI.Service
      )

    case esi_service.get_character_info(character_id) do
      {:ok, char_info} ->
        %KillmailData{killmail | victim_name: Map.get(char_info, "name")}

      {:error, reason} ->
        Logger.warning(
          "Failed to get character info for victim #{character_id}: #{inspect(reason)}"
        )

        killmail
    end
  end

  defp enrich_attacker_names(%KillmailData{attackers: nil} = killmail), do: killmail

  defp enrich_attacker_names(%KillmailData{attackers: attackers} = killmail) do
    esi_service =
      Application.get_env(
        :wanderer_notifier,
        :esi_service_module,
        WandererNotifier.Api.ESI.Service
      )

    # Get the final blow attacker if present
    final_blow_attacker =
      Enum.find(attackers, fn a -> Map.get(a, "final_blow", false) end)

    killmail =
      if final_blow_attacker && Map.has_key?(final_blow_attacker, "character_id") do
        character_id = Map.get(final_blow_attacker, "character_id")

        case esi_service.get_character_info(character_id) do
          {:ok, char_info} ->
            %KillmailData{killmail | final_blow_attacker_name: Map.get(char_info, "name")}

          {:error, reason} ->
            Logger.warning(
              "Failed to get character info for final blow attacker #{character_id}: #{inspect(reason)}"
            )

            killmail
        end
      else
        killmail
      end

    %KillmailData{killmail | attacker_count: length(attackers)}
  end

  defp enrich_ship_names(killmail) do
    killmail
    |> enrich_victim_ship_name()
    |> enrich_final_blow_ship_name()
  end

  defp enrich_victim_ship_name(%KillmailData{victim_ship_id: nil} = killmail), do: killmail

  defp enrich_victim_ship_name(%KillmailData{victim_ship_id: ship_type_id} = killmail) do
    esi_service =
      Application.get_env(
        :wanderer_notifier,
        :esi_service_module,
        WandererNotifier.Api.ESI.Service
      )

    case esi_service.get_type_info(ship_type_id) do
      {:ok, type_info} ->
        %KillmailData{killmail | victim_ship_name: Map.get(type_info, "name")}

      {:error, reason} ->
        Logger.warning(
          "Failed to get ship type info for victim ship #{ship_type_id}: #{inspect(reason)}"
        )

        killmail
    end
  end

  defp enrich_final_blow_ship_name(%KillmailData{attackers: nil} = killmail), do: killmail

  defp enrich_final_blow_ship_name(%KillmailData{attackers: attackers} = killmail) do
    esi_service =
      Application.get_env(
        :wanderer_notifier,
        :esi_service_module,
        WandererNotifier.Api.ESI.Service
      )

    # Get the final blow attacker's ship if present
    final_blow_attacker =
      Enum.find(attackers, fn a -> Map.get(a, "final_blow", false) end)

    if final_blow_attacker && Map.has_key?(final_blow_attacker, "ship_type_id") do
      ship_type_id = Map.get(final_blow_attacker, "ship_type_id")

      case esi_service.get_type_info(ship_type_id) do
        {:ok, type_info} ->
          %KillmailData{killmail | final_blow_ship_name: Map.get(type_info, "name")}

        {:error, reason} ->
          Logger.warning(
            "Failed to get ship type info for final blow ship #{ship_type_id}: #{inspect(reason)}"
          )

          killmail
      end
    else
      killmail
    end
  end

  defp enrich_corporation_names(killmail) do
    killmail
    |> enrich_victim_corporation_name()
  end

  defp enrich_victim_corporation_name(%KillmailData{victim_corporation_id: nil} = killmail),
    do: killmail

  defp enrich_victim_corporation_name(
         %KillmailData{victim_corporation_id: corporation_id} = killmail
       ) do
    esi_service =
      Application.get_env(
        :wanderer_notifier,
        :esi_service_module,
        WandererNotifier.Api.ESI.Service
      )

    case esi_service.get_corporation_info(corporation_id) do
      {:ok, corp_info} ->
        %KillmailData{killmail | victim_corporation_name: Map.get(corp_info, "name")}

      {:error, reason} ->
        Logger.warning(
          "Failed to get corporation info for victim corp #{corporation_id}: #{inspect(reason)}"
        )

        killmail
    end
  end
end
