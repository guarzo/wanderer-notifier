defmodule WandererNotifier.Application.Services.NotificationService do
  @moduledoc """
  Enhanced notification service with priority system support.

  This service handles sending notifications with priority system logic that can
  override disabled notifications for critical systems. Priority systems receive
  @here mentions to ensure visibility.

  ## Priority System Logic

  - If notifications are enabled: Send all notifications normally
  - If notifications are disabled BUT system is priority: Send with @here mention
  - If notifications are disabled AND system is not priority: Skip notification

  ## Usage

      # Send a system notification
      WandererNotifier.Application.Services.NotificationService.notify_system("Jita")
      
      # Manage priority systems
      WandererNotifier.Application.Services.NotificationService.register_priority_system("Jita")
      WandererNotifier.Application.Services.NotificationService.unregister_priority_system("Jita")
      
      # Get priority systems list
      priority_systems = WandererNotifier.Application.Services.NotificationService.list_priority_systems()
  """

  require Logger

  alias WandererNotifier.Shared.Logger.Logger, as: AppLogger
  alias WandererNotifier.Domains.Notifications.NotificationService, as: DomainNotificationService
  alias WandererNotifier.Infrastructure.Adapters.Discord.VoiceParticipants
  alias WandererNotifier.PersistentValues
  alias WandererNotifier.Shared.Config

  @priority_systems_key :priority_systems

  @doc """
  Sends a system notification with priority system logic.

  The notification behavior depends on:
  1. System notification settings (enabled/disabled)
  2. Whether the system is in the priority list
  3. Priority-only mode setting

  Priority systems always send notifications with @here mentions,
  even if system notifications are disabled.

  If PRIORITY_SYSTEMS_ONLY is enabled, only priority systems will
  generate notifications regardless of other settings.
  """
  @spec notify_system(String.t()) :: :ok | :skip | {:error, term()}
  def notify_system(system_name) when is_binary(system_name) do
    notifications_enabled = Config.system_notifications_enabled?()
    is_priority = is_priority_system?(system_name)
    priority_only_mode = Config.priority_systems_only?()

    case {notifications_enabled, is_priority, priority_only_mode} do
      {_, true, _} ->
        # Priority systems always send notifications with @here mention
        AppLogger.processor_info("Sending priority system notification",
          system: system_name,
          priority_only_mode: priority_only_mode
        )

        send_system_notification(system_name, true)

      {true, false, false} ->
        # Regular notification path - send without @here (normal mode)
        AppLogger.processor_info("Sending system notification",
          system: system_name,
          priority: false
        )

        send_system_notification(system_name, false)

      {_, false, true} ->
        # Priority-only mode: skip non-priority systems
        AppLogger.processor_info("Skipping non-priority system notification (priority-only mode)",
          system: system_name
        )

        :skip

      {false, false, false} ->
        # Skip notification - disabled and not priority (normal mode)
        AppLogger.processor_info("Skipping system notification (disabled and not priority)",
          system: system_name
        )

        :skip
    end
  end

  @doc """
  Registers a system as priority.

  Priority systems receive @here notifications even when system notifications
  are disabled globally.
  """
  @spec register_priority_system(String.t()) :: :ok
  def register_priority_system(system_name) when is_binary(system_name) do
    system_hash = hash_system_name(system_name)
    current = PersistentValues.get(@priority_systems_key)

    if system_hash not in current do
      PersistentValues.add(@priority_systems_key, system_hash)

      AppLogger.config_info("Added priority system",
        system: system_name,
        hash: system_hash
      )
    end

    :ok
  end

  @doc """
  Unregisters a system from priority status.
  """
  @spec unregister_priority_system(String.t()) :: :ok
  def unregister_priority_system(system_name) when is_binary(system_name) do
    system_hash = hash_system_name(system_name)
    current = PersistentValues.get(@priority_systems_key)

    if system_hash in current do
      PersistentValues.remove(@priority_systems_key, system_hash)

      AppLogger.config_info("Removed priority system",
        system: system_name,
        hash: system_hash
      )
    end

    :ok
  end

  @doc """
  Checks if a system is marked as priority.
  """
  @spec is_priority_system?(String.t()) :: boolean()
  def is_priority_system?(system_name) when is_binary(system_name) do
    system_hash = hash_system_name(system_name)
    current = PersistentValues.get(@priority_systems_key)
    system_hash in current
  end

  @doc """
  Lists all priority systems by their hashes.

  Note: This returns hashes, not original system names, as we don't store
  a reverse mapping for security and storage efficiency.
  """
  @spec list_priority_systems() :: [integer()]
  def list_priority_systems do
    PersistentValues.get(@priority_systems_key)
  end

  @doc """
  Gets statistics about priority systems.
  """
  @spec priority_system_stats() :: %{
          count: non_neg_integer(),
          notifications_enabled: boolean()
        }
  def priority_system_stats do
    %{
      count: length(list_priority_systems()),
      notifications_enabled: Config.system_notifications_enabled?()
    }
  end

  @doc """
  Clears all priority systems.

  ⚠️ Warning: This operation is irreversible!
  """
  @spec clear_priority_systems() :: :ok
  def clear_priority_systems do
    PersistentValues.put(@priority_systems_key, [])
    AppLogger.config_info("Cleared all priority systems")
    :ok
  end

  @doc """
  Sends a character notification.

  This delegates to the existing character notification system.
  """
  @spec notify_character(map()) :: :ok | {:error, term()}
  def notify_character(character) do
    if Config.character_notifications_enabled?() do
      AppLogger.processor_info("Sending character notification",
        character_id: Map.get(character, :character_id),
        character_name: Map.get(character, :name)
      )

      # Create a character notification struct and send through the domain service
      character_notification = %{
        type: :character_notification,
        data: character
      }

      case DomainNotificationService.send_message(character_notification) do
        {:ok, :sent} -> :ok
        {:error, reason} -> {:error, reason}
        other -> other
      end
    else
      AppLogger.processor_info("Skipping character notification (disabled)")
      {:error, :notifications_disabled}
    end
  end

  @doc """
  Sends a killmail notification.

  This delegates to the existing killmail notification system.
  """
  @spec notify_kill(map()) :: :ok | {:error, term()}
  def notify_kill(kill_data) do
    if Config.kill_notifications_enabled?() do
      AppLogger.processor_info("Sending kill notification",
        killmail_id: Map.get(kill_data, :killmail_id)
      )

      # Create a kill notification struct and send through the domain service
      kill_notification = %{
        type: :kill_notification,
        data: %{killmail: kill_data}
      }

      case DomainNotificationService.send_message(kill_notification) do
        {:ok, :sent} -> :ok
        {:error, reason} -> {:error, reason}
        other -> other
      end
    else
      AppLogger.processor_info("Skipping kill notification (disabled)")
      {:error, :notifications_disabled}
    end
  end

  # Private Functions

  # Generates a consistent hash for system names
  defp hash_system_name(system_name) do
    # Use phash2 for consistent hashing across restarts
    system_name
    |> String.trim()
    |> String.downcase()
    |> :erlang.phash2()
  end

  # Sends a system notification to Discord
  defp send_system_notification(system_name, is_priority) do
    try do
      content = format_system_notification(system_name, is_priority)
      channel_id = get_system_channel_id()

      case send_to_discord(content, channel_id) do
        :ok ->
          AppLogger.processor_info("System notification sent successfully",
            system: system_name,
            priority: is_priority,
            channel: channel_id
          )

          :ok

        {:error, reason} ->
          AppLogger.processor_error("Failed to send system notification",
            system: system_name,
            error: inspect(reason),
            channel: channel_id
          )

          {:error, reason}
      end
    rescue
      error ->
        AppLogger.processor_error("Exception in send_system_notification",
          system: system_name,
          error: Exception.message(error),
          stacktrace: Exception.format_stacktrace(__STACKTRACE__)
        )

        {:error, error}
    end
  end

  # Formats a system notification message
  defp format_system_notification(system_name, is_priority) do
    base_message = "🗺️ System event detected: **#{system_name}**"

    if is_priority do
      priority_message = "#{base_message} (Priority System)"
      build_notification_with_mentions(priority_message)
    else
      base_message
    end
  end

  # Builds notification message with appropriate mentions (voice participants or @here)
  defp build_notification_with_mentions(message) do
    if Config.voice_participant_notifications_enabled?() do
      voice_mentions = VoiceParticipants.get_active_voice_mentions()

      case {voice_mentions, Config.fallback_to_here_enabled?()} do
        {[], true} ->
          # No voice participants, fallback to @here if enabled
          AppLogger.processor_info("No voice participants found, falling back to @here")
          "@here #{message}"

        {[], false} ->
          # No voice participants, no fallback
          AppLogger.processor_info("No voice participants found, no fallback enabled")
          message

        {mentions, _} when is_list(mentions) and length(mentions) > 0 ->
          # Found voice participants
          AppLogger.processor_info("Found voice participants", count: length(mentions))
          VoiceParticipants.build_voice_notification_message(message, mentions)
      end
    else
      # Voice participant notifications disabled, use @here
      "@here #{message}"
    end
  end

  # Gets the appropriate Discord channel for system notifications
  defp get_system_channel_id do
    Config.discord_system_channel_id() || Config.discord_channel_id()
  end

  # Sends content to Discord channel
  defp send_to_discord(content, channel_id) do
    if Application.get_env(:wanderer_notifier, :env) == :test do
      AppLogger.processor_info("TEST MODE: System notification",
        content: content,
        channel_id: channel_id
      )

      :ok
    else
      # Use the domain notification service
      case DomainNotificationService.send_message(content) do
        {:ok, :sent} -> :ok
        {:error, reason} -> {:error, reason}
        other -> other
      end
    end
  end
end
