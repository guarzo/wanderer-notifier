defmodule WandererNotifier.Processing.Killmail.Notification do
  @moduledoc """
  Specialized module for processing kill notifications.
  Encapsulates all the notification handling logic for kills.
  """

  alias WandererNotifier.Data.Cache.Keys, as: CacheKeys
  alias WandererNotifier.Data.Cache.Repository, as: CacheRepo
  alias WandererNotifier.Logger.Logger, as: AppLogger
  alias WandererNotifier.Notifications.Determiner.Kill, as: KillDeterminer
  alias WandererNotifier.Notifiers.Factory, as: NotifierFactory
  alias WandererNotifier.Notifiers.StructuredFormatter
  alias WandererNotifier.Processing.Killmail.Enrichment
  alias WandererNotifier.Processing.Killmail.Stats

  @doc """
  Determines if a kill notification should be sent and sends it.

  ## Parameters
  - killmail: The killmail struct to process
  - system_id: Optional system ID (will extract from killmail if not provided)

  ## Returns
  - true if a notification was sent
  - false if notification was skipped
  """
  def should_notify_kill?(killmail, _system_id \\ nil) do
    # Delegate to the KillDeterminer module for notification logic
    KillDeterminer.should_notify?(killmail)
  end

  @doc """
  Sends a kill notification.
  """
  def send_kill_notification(enriched_killmail, kill_id, _bypass_dedup \\ false) do
    AppLogger.kill_info("Sending kill notification", %{kill_id: kill_id})

    # Create a generic notification that can be converted to various formats
    generic_notification = StructuredFormatter.format_kill_notification(enriched_killmail)
    discord_format = StructuredFormatter.to_discord_format(generic_notification)

    # Send notification via factory with correct type
    case NotifierFactory.notify(:send_discord_embed, [discord_format]) do
      :ok ->
        AppLogger.kill_info("Kill notification sent successfully", %{kill_id: kill_id})
        Stats.update(:notification_sent)
        {:ok, kill_id}

      {:ok, _} ->
        AppLogger.kill_info("Kill notification sent successfully", %{kill_id: kill_id})
        Stats.update(:notification_sent)
        {:ok, kill_id}

      {:error, reason} ->
        AppLogger.kill_error("Failed to send kill notification", %{
          kill_id: kill_id,
          error: inspect(reason)
        })

        {:error, reason}
    end
  end

  @doc """
  Sends a test kill notification using recent data.
  """
  def send_test do
    AppLogger.kill_info("Sending test kill notification...")

    # Get recent kills using proper cache key
    recent_kills = CacheRepo.get(CacheKeys.zkill_recent_kills())
    AppLogger.kill_debug("Found #{length(recent_kills)} recent kills in shared cache repository")

    if recent_kills == [] do
      error_message = "No recent kills available for test notification"
      AppLogger.kill_error(error_message)

      # Notify the user through Discord
      NotifierFactory.notify(:send_message, [
        "Error: #{error_message} - No test notification sent. Please wait for some kills to be processed."
      ])

      {:error, error_message}
    else
      # Get the first kill
      recent_kill = List.first(recent_kills)

      # Extract kill_id regardless of struct type
      kill_id = extract_kill_id(recent_kill)

      # Log what we're using for testing
      AppLogger.kill_debug("Using kill data for test notification with kill_id: #{kill_id}")

      # Create a Data.Killmail struct if needed
      killmail = ensure_data_killmail(recent_kill)

      # Make sure to enrich the killmail data before sending notification
      # This will try to get real data from APIs first
      enriched_kill = Enrichment.enrich_killmail_data(killmail)

      # Validate essential data is present - fail if not
      case validate_killmail_data(enriched_kill) do
        :ok ->
          # Use the normal notification flow but bypass deduplication
          AppLogger.kill_info(
            "TEST NOTIFICATION: Using normal notification flow for test kill notification"
          )

          send_kill_notification(enriched_kill, kill_id, true)
          {:ok, kill_id}

        {:error, reason} ->
          # Data validation failed, return error
          error_message = "Cannot send test notification: #{reason}"
          AppLogger.kill_error(error_message)

          # Notify the user through Discord
          NotifierFactory.notify(:send_message, [error_message])

          {:error, error_message}
      end
    end
  end

  # Helper to extract kill_id regardless of struct type
  defp extract_kill_id(kill) do
    cond do
      is_struct(kill, WandererNotifier.Data.Killmail) -> kill.killmail_id
      is_struct(kill, WandererNotifier.Resources.Killmail) -> kill.killmail_id
      is_map(kill) -> Map.get(kill, "killmail_id") || Map.get(kill, :killmail_id)
      true -> nil
    end
  end

  # Helper to ensure we have a Data.Killmail struct
  defp ensure_data_killmail(kill) do
    cond do
      is_struct(kill, WandererNotifier.Data.Killmail) ->
        # Already the right type
        kill

      is_struct(kill, WandererNotifier.Resources.Killmail) ->
        # Convert from Resources.Killmail to Data.Killmail
        WandererNotifier.Data.Killmail.new(
          kill.killmail_id,
          Map.get(kill, :zkb_data) || %{}
        )

      is_map(kill) ->
        # Convert from map to Data.Killmail
        WandererNotifier.Data.Killmail.new(
          Map.get(kill, "killmail_id") || Map.get(kill, :killmail_id),
          Map.get(kill, "zkb") || Map.get(kill, :zkb) || %{}
        )

      true ->
        # Default empty killmail as fallback
        WandererNotifier.Data.Killmail.new(nil, %{})
    end
  end

  # Validate killmail has all required data for notification
  defp validate_killmail_data(killmail) do
    # For Data.Killmail struct
    if is_struct(killmail, WandererNotifier.Data.Killmail) do
      # Check victim data
      victim = Map.get(killmail, :victim) || %{}

      # Check system name
      esi_data = Map.get(killmail, :esi_data) || %{}
      system_name = Map.get(esi_data, "solar_system_name")

      validate_fields(victim, system_name)
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
end
