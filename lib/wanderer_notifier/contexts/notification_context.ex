defmodule WandererNotifier.Contexts.NotificationContext do
  @moduledoc """
  Context module for all notification-related operations.

  Provides a unified interface for sending notifications across different channels
  and types. This context consolidates notification logic that was previously
  scattered across multiple modules and provides a clean API for:

  - Kill notifications
  - System notifications  
  - Character notifications
  - Status messages and alerts
  - Discord integration
  - Notification formatting and delivery

  This context acts as the single entry point for all notification operations,
  abstracting the complexity of different notification types and channels.
  """

  require Logger
  alias WandererNotifier.Application.Services.ApplicationService
  alias WandererNotifier.Domains.Notifications.Notifiers.Discord.{NeoClient, Notifier}
  alias WandererNotifier.Shared.Config
  alias WandererNotifier.Domains.Tracking.Entities.System

  # ──────────────────────────────────────────────────────────────────────────────
  # High-Level Notification API
  # ──────────────────────────────────────────────────────────────────────────────

  @doc """
  Sends a notification of any type through the appropriate channels.

  This is the main entry point for notification processing. It automatically
  determines the notification type and routes it to the correct handler.

  ## Examples

      # Kill notification
      NotificationContext.send_notification(%{killmail_id: 123, ...})
      
      # System notification
      NotificationContext.send_notification(%{solar_system_id: 30000142, ...})
      
      # Character notification
      NotificationContext.send_notification(%{character_id: 456, ...})
  """
  @spec send_notification(map(), keyword()) :: {:ok, atom()} | {:error, term()}
  def send_notification(notification, opts \\ []) do
    Logger.debug("Processing notification through NotificationContext",
      notification_keys: Map.keys(notification),
      opts: opts,
      category: :notification
    )

    case ApplicationService.process_notification(notification, opts) do
      {:ok, result} ->
        Logger.debug("Notification processed successfully",
          result: result,
          category: :notification
        )

        {:ok, result}

      {:error, reason} = error ->
        Logger.warning("Failed to process notification",
          reason: inspect(reason),
          notification_keys: Map.keys(notification),
          category: :notification
        )

        error
    end
  end

  # ──────────────────────────────────────────────────────────────────────────────
  # Specific Notification Types
  # ──────────────────────────────────────────────────────────────────────────────

  @doc """
  Sends a kill notification through the notification system.
  """
  @spec send_kill_notification(map()) :: {:ok, atom()} | {:error, term()}
  def send_kill_notification(killmail_data) do
    # Check if we're in the startup suppression period
    if WandererNotifier.Shared.Utils.Startup.in_suppression_period?() do
      Logger.info("Skipping kill notification during startup suppression period",
        killmail_id:
          Map.get(killmail_data, :killmail_id) || Map.get(killmail_data, "killmail_id"),
        category: :notification
      )

      {:ok, :skipped_startup_suppression}
    else
      killmail_id = Map.get(killmail_data, :killmail_id) || Map.get(killmail_data, "killmail_id")
      Logger.info("[Notification] Sending kill #{killmail_id}")

      case ApplicationService.notify_kill(killmail_data) do
        {:ok, result} ->
          # Track the notification in metrics
          ApplicationService.increment_metric(:notification_sent)
          {:ok, result}

        {:error, reason} = error ->
          Logger.warning("Kill notification failed",
            reason: inspect(reason),
            killmail_id: Map.get(killmail_data, :killmail_id),
            category: :notification
          )

          error
      end
    end
  end

  @doc """
  Sends a system notification with priority system logic.

  This handles the complex priority system logic where certain systems
  can override global notification settings.
  """
  @spec send_system_notification(map(), keyword()) :: {:ok, atom()} | {:error, term()}
  def send_system_notification(system_data, opts \\ []) do
    system = ensure_system_struct(system_data)
    system_name = system.name || "Unknown System"
    notifications_enabled = system_notifications_enabled?()
    is_priority = is_priority_system?(system_name)
    priority_only_mode = Config.get(:priority_systems_only, false)

    case {notifications_enabled, is_priority, priority_only_mode} do
      {_, true, _} ->
        # Priority systems always send notifications
        Logger.info("Sending priority system notification",
          system: system_name,
          priority_only_mode: priority_only_mode,
          category: :notification
        )

        # Add priority flag to system data
        system_map = Map.from_struct(system) |> Map.put(:priority, true)
        send_system_notification_impl(system_map, opts)

      {true, false, false} ->
        # Regular notification path
        Logger.info("[Notification] Sending system #{system_name}")

        system_map = Map.from_struct(system) |> Map.put(:priority, false)
        send_system_notification_impl(system_map, opts)

      {_, false, true} ->
        # Priority-only mode: skip non-priority systems
        Logger.info("Skipping non-priority system notification (priority-only mode)",
          system: system_name,
          category: :notification
        )

        {:ok, :skipped}

      {false, false, false} ->
        # Skip notification - disabled and not priority
        Logger.info("Skipping system notification (disabled and not priority)",
          system: system_name,
          category: :notification
        )

        {:error, :notifications_disabled}
    end
  end

  defp send_system_notification_impl(system_data, opts) do
    Logger.debug(
      "send_system_notification_impl called with system_data type: #{inspect(Map.get(system_data, :__struct__, "no struct"))}"
    )

    Logger.debug("System data keys: #{inspect(Map.keys(system_data))}")

    case send_notification(system_data, opts) do
      {:ok, result} ->
        ApplicationService.increment_metric(:notification_sent)
        {:ok, result}

      {:error, reason} = error ->
        Logger.warning("System notification failed: #{inspect(reason)}")
        Logger.warning("System name: #{Map.get(system_data, :name, "Unknown")}")
        error
    end
  end

  @doc """
  Sends a character notification.
  """
  @spec send_character_notification(map(), keyword()) :: {:ok, atom()} | {:error, term()}
  def send_character_notification(character_data, opts \\ []) do
    character_id =
      Map.get(character_data, :character_id) || Map.get(character_data, "character_id")

    character_name = Map.get(character_data, :name) || Map.get(character_data, "name")

    Logger.info("Sending character notification",
      character_id: character_id,
      character_name: character_name,
      category: :notification
    )

    case send_notification(character_data, opts) do
      {:ok, result} ->
        ApplicationService.increment_metric(:notification_sent)
        {:ok, result}

      {:error, reason} = error ->
        Logger.warning("Character notification failed",
          reason: inspect(reason),
          character_id: character_id,
          category: :notification
        )

        error
    end
  end

  # ──────────────────────────────────────────────────────────────────────────────
  # Discord Integration
  # ──────────────────────────────────────────────────────────────────────────────

  @doc """
  Sends a formatted embed to Discord.

  This is a lower-level function for sending pre-formatted Discord embeds.
  For most use cases, prefer the higher-level notification functions above.
  """
  @spec send_discord_embed(map(), keyword()) :: {:ok, atom()} | {:error, term()}
  def send_discord_embed(embed, opts \\ []) do
    channel_id = Keyword.get(opts, :channel_id, get_default_discord_channel())

    Logger.debug("Sending Discord embed",
      embed_type: Map.get(embed, :type),
      channel_id: channel_id,
      category: :notification
    )

    case NeoClient.send_embed(embed, channel_id) do
      :ok ->
        Logger.debug("Discord embed sent successfully", category: :notification)
        {:ok, :sent}

      {:error, reason} = error ->
        Logger.warning("Failed to send Discord embed",
          reason: inspect(reason),
          embed_type: Map.get(embed, :type),
          category: :notification
        )

        error
    end
  end

  @doc """
  Sends a simple text message to Discord.

  For status updates, alerts, and other simple notifications that don't
  require rich embed formatting.
  """
  @spec send_status_message(String.t(), keyword()) :: {:ok, atom()} | {:error, term()}
  def send_status_message(message, _opts \\ []) do
    Logger.info("Sending status message to Discord",
      message_length: String.length(message),
      category: :notification
    )

    case Notifier.send_message(message) do
      :ok ->
        Logger.debug("Status message sent successfully", category: :notification)
        {:ok, :sent}

      {:error, reason} = error ->
        Logger.warning("Failed to send status message",
          reason: inspect(reason),
          message_preview: String.slice(message, 0, 50),
          category: :notification
        )

        error
    end
  end

  @doc """
  Sends a rally point notification.
  """
  @spec send_rally_point_notification(map()) :: {:ok, atom()} | {:error, term()}
  def send_rally_point_notification(rally_point) do
    Logger.info("Rally point notification requested",
      rally_enabled: Config.rally_notifications_enabled?(),
      notifications_enabled: notifications_enabled?(),
      rally_point: inspect(rally_point)
    )

    if notifications_enabled?() do
      # Create notification data
      notification = %{
        type: :rally_point,
        rally_point: rally_point,
        system_name: rally_point.system_name,
        system_id: rally_point.system_id
      }

      # Process through ApplicationService
      case ApplicationService.process_notification(notification) do
        {:ok, result} ->
          Logger.info("Rally point notification sent",
            system: rally_point.system_name,
            category: :notification
          )

          # Track metrics
          :telemetry.execute(
            [:wanderer_notifier, :notification, :rally_point],
            %{count: 1},
            %{system: rally_point.system_name}
          )

          {:ok, result}

        {:error, reason} = error ->
          Logger.error("Failed to send rally point notification: #{inspect(reason)}",
            rally_point: inspect(rally_point),
            notification: inspect(notification),
            category: :notification
          )

          error
      end
    else
      {:error, :notifications_disabled}
    end
  end

  # ──────────────────────────────────────────────────────────────────────────────
  # Priority System Management
  # ──────────────────────────────────────────────────────────────────────────────

  @priority_systems_key :priority_systems

  @doc """
  Registers a system as priority.
  """
  @spec register_priority_system(String.t()) :: :ok
  def register_priority_system(system_name) when is_binary(system_name) do
    system_hash = hash_system_name(system_name)
    current = WandererNotifier.PersistentValues.get(@priority_systems_key)

    if system_hash not in current do
      WandererNotifier.PersistentValues.add(@priority_systems_key, system_hash)

      Logger.info("Added priority system",
        system: system_name,
        hash: system_hash,
        category: :config
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
    current = WandererNotifier.PersistentValues.get(@priority_systems_key)

    if system_hash in current do
      WandererNotifier.PersistentValues.remove(@priority_systems_key, system_hash)

      Logger.info("Removed priority system",
        system: system_name,
        hash: system_hash,
        category: :config
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
    current = WandererNotifier.PersistentValues.get(@priority_systems_key)
    system_hash in current
  end

  @doc """
  Lists all priority systems by their hashes.
  """
  @spec list_priority_systems() :: [integer()]
  def list_priority_systems do
    WandererNotifier.PersistentValues.get(@priority_systems_key)
  end

  @doc """
  Gets statistics about priority systems.
  """
  @spec priority_system_stats() :: %{count: non_neg_integer(), notifications_enabled: boolean()}
  def priority_system_stats do
    %{
      count: length(list_priority_systems()),
      notifications_enabled: Config.get(:system_notifications_enabled, true)
    }
  end

  @doc """
  Clears all priority systems.
  """
  @spec clear_priority_systems() :: :ok
  def clear_priority_systems do
    WandererNotifier.PersistentValues.put(@priority_systems_key, [])
    Logger.info("Cleared all priority systems", category: :config)
    :ok
  end

  defp hash_system_name(system_name) do
    system_name
    |> String.trim()
    |> String.downcase()
    |> :erlang.phash2()
  end

  defp ensure_system_struct(%System{} = system), do: system

  defp ensure_system_struct(data) when is_map(data) do
    %System{
      solar_system_id: extract_system_id(data),
      name: extract_system_name(data),
      tracked: Map.get(data, :tracked, true),
      system_type: extract_field(data, :system_type),
      type_description: extract_field(data, :type_description),
      class_title: extract_field(data, :class_title),
      region_name: extract_field(data, :region_name),
      security_status: extract_field(data, :security_status),
      is_shattered: extract_field(data, :is_shattered),
      statics: extract_field(data, :statics),
      effect_name: extract_field(data, :effect_name),
      original_name: extract_field(data, :original_name)
    }
  end

  defp extract_system_id(data) do
    Map.get(data, :solar_system_id) ||
      Map.get(data, "solar_system_id") ||
      Map.get(data, :id) ||
      Map.get(data, "id")
  end

  defp extract_system_name(data) do
    Map.get(data, :name) || Map.get(data, "name") || "Unknown System"
  end

  defp extract_field(data, field) do
    Map.get(data, field) || Map.get(data, to_string(field))
  end

  # ──────────────────────────────────────────────────────────────────────────────
  # Configuration and Status
  # ──────────────────────────────────────────────────────────────────────────────

  @doc """
  Gets the configured Discord channel ID for notifications.
  """
  @spec get_discord_channel() :: String.t() | nil
  def get_discord_channel do
    NeoClient.channel_id()
  end

  @doc """
  Checks if notifications are currently enabled.
  """
  @spec notifications_enabled?() :: boolean()
  def notifications_enabled? do
    Config.get(:notifications_enabled, true)
  end

  @doc """
  Checks if kill notifications are enabled.
  """
  @spec kill_notifications_enabled?() :: boolean()
  def kill_notifications_enabled? do
    Config.kill_notifications_enabled?()
  end

  @doc """
  Checks if system notifications are enabled.
  """
  @spec system_notifications_enabled?() :: boolean()
  def system_notifications_enabled? do
    Config.system_notifications_enabled?()
  end

  @doc """
  Checks if character notifications are enabled.
  """
  @spec character_notifications_enabled?() :: boolean()
  def character_notifications_enabled? do
    Config.character_notifications_enabled?()
  end

  @doc """
  Gets comprehensive notification status and statistics.
  """
  @spec get_notification_status() :: map()
  def get_notification_status do
    stats = ApplicationService.get_stats()

    %{
      enabled: notifications_enabled?(),
      kills_enabled: kill_notifications_enabled?(),
      systems_enabled: system_notifications_enabled?(),
      characters_enabled: character_notifications_enabled?(),
      discord_channel: get_discord_channel(),
      metrics: %{
        total_sent: get_in(stats, [:notifications, :total]) || 0,
        kills_sent: get_in(stats, [:notifications, :kills]) || 0,
        systems_sent: get_in(stats, [:notifications, :systems]) || 0,
        characters_sent: get_in(stats, [:notifications, :characters]) || 0
      }
    }
  end

  # ──────────────────────────────────────────────────────────────────────────────
  # Private Helpers
  # ──────────────────────────────────────────────────────────────────────────────

  defp get_default_discord_channel do
    Config.discord_channel_id()
  end
end
