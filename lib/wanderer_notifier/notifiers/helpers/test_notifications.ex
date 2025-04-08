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
        killmail_data = %{
          killmail_id: kill_id,
          zkb_data: kill_data["zkb"],
          esi_data: esi_data
        }

        # Enrich the killmail data
        enriched_kill = Enrichment.enrich_killmail_data(killmail_data)

        AppLogger.kill_debug(
          "TEST NOTIFICATION: Enriched killmail data: #{inspect(enriched_kill)}"
        )

        {:ok, enriched_kill}

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
    # For Resources.Killmail struct
    if is_struct(killmail, WandererNotifier.Resources.Killmail) do
      # Check for required fields directly in the resource
      cond do
        is_nil(killmail.victim_name) ->
          {:error, "Killmail is missing victim name"}

        is_nil(killmail.victim_ship_name) ->
          {:error, "Victim is missing ship type name"}

        is_nil(killmail.solar_system_name) ->
          {:error, "Killmail is missing system name"}

        true ->
          :ok
      end
    else
      # Fall back to treating it as a generic map
      victim = Map.get(killmail, :victim_data) || %{}
      system_name = Map.get(killmail, :solar_system_name)

      validate_fields(victim, system_name)
    end
  end

  # Validate the required fields
  defp validate_fields(victim, system_name) do
    cond do
      victim == nil || victim == %{} ->
        {:error, "Killmail is missing victim data"}

      Map.get(victim, "character_name") == nil ->
        {:error, "Victim is missing character name"}

      Map.get(victim, "ship_type_name") == nil ->
        {:error, "Victim is missing ship type name"}

      system_name == nil ->
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
