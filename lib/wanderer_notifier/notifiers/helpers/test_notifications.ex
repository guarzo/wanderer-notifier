defmodule WandererNotifier.Notifiers.Helpers.TestNotifications do
  @moduledoc """
  Helper module for sending test notifications.
  """

  alias WandererNotifier.Api.ESI.Service, as: ESIService
  alias WandererNotifier.Api.Map.SystemsClient
  alias WandererNotifier.Api.ZKill.Service, as: ZKillService
  alias WandererNotifier.Core.Stats
  alias WandererNotifier.Data.Cache.Keys, as: CacheKeys
  alias WandererNotifier.Data.Cache.Repository, as: CacheRepo
  alias WandererNotifier.KillmailProcessing.{KillmailData, Validator}
  alias WandererNotifier.Logger.Logger, as: AppLogger
  alias WandererNotifier.Notifiers.Factory, as: NotifierFactory
  alias WandererNotifier.Notifiers.StructuredFormatter
  alias WandererNotifier.Processing.Killmail.Enrichment
  alias WandererNotifier.Schedulers.WeeklyKillHighlightsScheduler

  @doc """
  Sends a test system notification.
  """
  def send_test_system_notification do
    AppLogger.info("Sending test system notification...")

    # Get a system from the cache for testing
    case SystemsClient.get_system_for_notification() do
      {:ok, system} ->
        # Format the notification
        generic_notification = StructuredFormatter.format_system_notification(system)
        discord_format = StructuredFormatter.to_discord_format(generic_notification)

        # Send notification
        case NotifierFactory.notify(:send_discord_embed, [discord_format]) do
          :ok ->
            AppLogger.info("Test system notification sent successfully")
            Stats.increment(:systems)
            Stats.increment(:kill_notified)
            {:ok, "Test system notification sent successfully"}

          {:ok, result} ->
            AppLogger.info("Test system notification sent successfully")
            Stats.increment(:systems)
            Stats.increment(:kill_notified)
            {:ok, result}

          {:error, reason} ->
            AppLogger.error("Failed to send test system notification: #{inspect(reason)}")
            {:error, reason}
        end

      {:error, :no_systems_in_cache} ->
        error_msg = "No systems found in cache for test notification"
        AppLogger.error(error_msg)
        {:error, error_msg}

      {:error, reason} ->
        AppLogger.error("Failed to get system for test notification: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Sends a test kill notification.
  """
  def send_test_kill_notification do
    # Get recent kills from ZKill
    case get_recent_kill() do
      {:ok, {kill_id, kill_data, hash}} ->
        process_kill_notification(kill_id, kill_data, hash)

      {:error, reason} ->
        handle_error("Failed to get recent kills", reason)
    end
  end

  # Get the most recent kill from ZKill
  defp get_recent_kill do
    case ZKillService.get_recent_kills(1) do
      {:ok, [kill | _]} ->
        kill_id = kill["killmail_id"]
        hash = get_in(kill, ["zkb", "hash"])
        AppLogger.kill_info("TEST NOTIFICATION: Using kill #{kill_id} for test notification")
        {:ok, {kill_id, kill, hash}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # Process a kill notification with the given kill data
  defp process_kill_notification(kill_id, kill_data, hash) do
    case get_enriched_killmail(kill_id, kill_data, hash) do
      {:ok, enriched_kill} ->
        send_kill_notification(enriched_kill, kill_id)

      {:error, reason} ->
        handle_error("Failed to get ESI data for kill #{kill_id}", reason)
    end
  end

  # Get and enrich killmail data
  defp get_enriched_killmail(kill_id, kill_data, hash) do
    case ESIService.get_killmail(kill_id, hash) do
      {:ok, esi_data} ->
        # Create a map with both ZKill and ESI data
        killmail_data = %WandererNotifier.Killmail.Core.Data{
          killmail_id: kill_id,
          raw_zkb_data: kill_data["zkb"],
          raw_esi_data: esi_data
        }

        # Enrich the killmail data first
        enriched_kill = Enrichment.enrich_killmail_data(killmail_data)

        # Now normalize the enriched data to ensure all fields are properly populated
        normalized_kill = Validator.normalize_killmail(enriched_kill)

        # Preserve the original ESI and ZKB data that might be lost during normalization
        final_kill =
          Map.merge(
            normalized_kill,
            Map.take(enriched_kill, [:raw_esi_data, :raw_zkb_data, :metadata])
          )

        # Extract victim information for additional ESI lookups
        victim = normalized_kill.victim || %{}
        corporation_id = Map.get(victim, "corporation_id")

        # Add corporation name if available but not already set
        final_kill_with_corp =
          case corporation_id do
            nil ->
              final_kill

            _ ->
              if !Map.get(final_kill, :victim_corporation_name) ||
                   Map.get(final_kill, :victim_corporation_name) == "Unknown Corp" do
                case ESIService.get_corporation_info(corporation_id) do
                  {:ok, corp_info} ->
                    corp_name = Map.get(corp_info, "name", "Unknown Corp")
                    Map.put(final_kill, :victim_corporation_name, corp_name)

                  _ ->
                    final_kill
                end
              else
                final_kill
              end
          end

        AppLogger.kill_debug(
          "TEST NOTIFICATION: Enriched and normalized killmail data: #{inspect(final_kill_with_corp)}"
        )

        {:ok, final_kill_with_corp}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # Send the actual kill notification
  defp send_kill_notification(enriched_kill, kill_id) do
    case validate_killmail_data(enriched_kill) do
      :ok ->
        AppLogger.kill_info(
          "TEST NOTIFICATION: Using normal notification flow for test kill notification"
        )

        send_formatted_notification(enriched_kill, kill_id)

      {:error, reason} ->
        handle_error("Cannot send test notification", reason)
    end
  end

  # Format and send the notification
  defp send_formatted_notification(enriched_kill, kill_id) do
    # Add detailed debugging of killmail fields
    AppLogger.kill_debug("TEST NOTIFICATION: Killmail fields before formatting:", %{
      killmail_id: kill_id,
      victim_name: Map.get(enriched_kill, :victim_name),
      victim_ship_name: Map.get(enriched_kill, :victim_ship_name),
      victim_corporation_name: Map.get(enriched_kill, :victim_corporation_name),
      solar_system_name: Map.get(enriched_kill, :solar_system_name),
      solar_system_security: Map.get(enriched_kill, :solar_system_security),
      final_blow_attacker_name: Map.get(enriched_kill, :final_blow_attacker_name),
      final_blow_ship_name: Map.get(enriched_kill, :final_blow_ship_name),
      attacker_count: Map.get(enriched_kill, :attacker_count),
      total_value: Map.get(enriched_kill, :total_value)
    })

    # Format the notification
    generic_notification = StructuredFormatter.format_kill_notification(enriched_kill)
    discord_format = StructuredFormatter.to_discord_format(generic_notification)

    # Send notification
    case NotifierFactory.notify(:send_discord_embed, [discord_format]) do
      :ok ->
        AppLogger.kill_info("Test kill notification sent successfully")
        # Increment both notifications.kills and processing.kills_notified
        Stats.increment(:kills)
        Stats.increment(:kill_notified)
        {:ok, kill_id}

      {:ok, result} ->
        AppLogger.kill_info("Test kill notification sent successfully")
        # Increment both notifications.kills and processing.kills_notified
        Stats.increment(:kills)
        Stats.increment(:kill_notified)
        {:ok, result}

      {:error, reason} ->
        handle_error("Failed to send kill notification", reason)
    end
  end

  # Handle errors consistently
  defp handle_error(message, reason) do
    error_message = "#{message}: #{inspect(reason)}"
    AppLogger.kill_error(error_message)
    NotifierFactory.notify(:send_message, [error_message])
    {:error, error_message}
  end

  @doc """
  Sends a test character notification.
  """
  def send_test_character_notification do
    AppLogger.info("Sending test character notification...")

    # Get tracked characters from cache
    case CacheRepo.get(CacheKeys.character_list()) do
      [character | _] when not is_nil(character) ->
        # Format the notification
        generic_notification = StructuredFormatter.format_character_notification(character)
        discord_format = StructuredFormatter.to_discord_format(generic_notification)

        # Send notification using a real character from cache
        case NotifierFactory.notify(:send_discord_embed, [discord_format]) do
          :ok ->
            AppLogger.info("Test character notification sent successfully")
            Stats.increment(:characters)
            Stats.increment(:kill_notified)
            {:ok, "Test character notification sent successfully"}

          {:ok, result} ->
            AppLogger.info("Test character notification sent successfully")
            Stats.increment(:characters)
            Stats.increment(:kill_notified)
            {:ok, result}

          {:error, reason} ->
            AppLogger.error("Failed to send test character notification: #{inspect(reason)}")
            {:error, reason}
        end

      _ ->
        error_msg = "No tracked characters found in cache for test notification"
        AppLogger.error(error_msg)
        {:error, error_msg}
    end
  end

  # Validate killmail has all required data for notification
  defp validate_killmail_data(killmail) do
    # First try using the Validator
    case Validator.validate_complete_data(killmail) do
      :ok -> :ok
      {:error, _} -> check_detailed_validation(killmail)
    end
  end

  # More detailed validation for specific field requirements
  defp check_detailed_validation(killmail) do
    # Convert to KillmailData first to ensure we can access fields directly
    killmail_data = WandererNotifier.KillmailProcessing.Transformer.to_killmail_data(killmail)

    cond do
      killmail_data.victim_id == nil ->
        {:error, "Killmail is missing victim data"}

      killmail_data.victim_name == nil ->
        {:error, "Victim is missing character name"}

      killmail_data.victim_ship_name == nil ->
        {:error, "Victim is missing ship type name"}

      killmail_data.solar_system_name == nil ->
        {:error, "Killmail is missing system name"}

      true ->
        :ok
    end
  end

  @doc """
  Sends a test kill highlights notification.
  This triggers the weekly best kill and worst loss notifications manually.
  """
  def send_test_kill_highlights do
    AppLogger.info("Sending test kill highlights notification...")

    # Execute the scheduler directly to generate the highlights
    case WeeklyKillHighlightsScheduler.execute(%{}) do
      {:ok, :completed, _state} ->
        AppLogger.info("Test kill highlights sent successfully")
        {:ok, "Test kill highlights sent successfully"}

      {:ok, :skipped, state} ->
        reason = Map.get(state, :reason, "unknown reason")
        message = "Kill highlights skipped: #{reason}"
        AppLogger.info(message)
        {:ok, message}

      {:error, reason, _state} ->
        AppLogger.error("Failed to send test kill highlights: #{inspect(reason)}")
        {:error, "Failed to send test kill highlights: #{inspect(reason)}"}
    end
  end
end
