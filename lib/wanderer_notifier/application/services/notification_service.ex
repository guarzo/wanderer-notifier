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
  alias WandererNotifier.Domains.Notifications.NotificationService, as: DomainNotificationService
  alias WandererNotifier.Domains.Notifications.Notifiers.Discord.Notifier, as: DiscordNotifier
  alias WandererNotifier.PersistentValues
  alias WandererNotifier.Shared.Config
  alias WandererNotifier.Domains.Tracking.Entities.System

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
  @spec notify_system(map() | String.t()) :: :ok | :skip | {:error, term()}
  # Handle System struct
  def notify_system(%System{} = system) do
    system_name = system.name || "Unknown System"
    handle_system_notification(system, system_name)
  end

  def notify_system(system) when is_map(system) do
    system_name = system["name"] || "Unknown System"
    handle_system_notification(system, system_name)
  end

  # Legacy support for string input
  def notify_system(system_name) when is_binary(system_name) do
    # Convert string to basic system map
    system = %{"name" => system_name}
    notify_system(system)
  end

  @spec send_domain_system_notification(map() | System.t(), boolean()) :: :ok | {:error, term()}
  defp send_domain_system_notification(system, is_priority) do
    # Create a system notification struct and send through the domain service
    # Preserve the original system data (struct or map)
    system_with_priority =
      case system do
        %System{} = s -> Map.put(s, :priority, is_priority)
        map -> Map.put(map, :priority, is_priority)
      end

    system_notification = %WandererNotifier.Domains.Notifications.Notification{
      type: :system_notification,
      data: system_with_priority
    }

    case DomainNotificationService.send(system_notification) do
      {:ok, _notification} -> :ok
      {:error, reason} -> {:error, reason}
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
    current = PersistentValues.get(@priority_systems_key)

    if system_hash in current do
      PersistentValues.remove(@priority_systems_key, system_hash)

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
    Logger.info("Cleared all priority systems", category: :config)
    :ok
  end

  @doc """
  Sends a character notification.

  This delegates to the existing character notification system.
  """
  @spec notify_character(map()) :: :ok | {:error, term()}
  def notify_character(character) do
    if Config.character_notifications_enabled?() do
      Logger.info("Sending character notification",
        character_id: Map.get(character, :character_id),
        character_name: Map.get(character, :name),
        category: :processor
      )

      # Create a character notification struct and send through the domain service
      character_notification = %WandererNotifier.Domains.Notifications.Notification{
        type: :character_notification,
        data: character
      }

      case DomainNotificationService.send(character_notification) do
        {:ok, _notification} -> :ok
        {:error, reason} -> {:error, reason}
      end
    else
      Logger.info("Skipping character notification (disabled, category: :processor)")
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
      Logger.info("Sending kill notification",
        killmail_id: Map.get(kill_data, :killmail_id),
        category: :processor
      )

      # Create a kill notification struct and send through the domain service
      kill_notification = %WandererNotifier.Domains.Notifications.Notification{
        type: :kill_notification,
        data: %{killmail: kill_data}
      }

      case DomainNotificationService.send(kill_notification) do
        {:ok, _notification} -> :ok
        {:error, reason} -> {:error, reason}
      end
    else
      Logger.info("Skipping kill notification (disabled, category: :processor)")
      {:error, :notifications_disabled}
    end
  end

  # Private Functions

  @spec handle_system_notification(map() | System.t(), String.t()) ::
          :ok | :skip | {:error, term()}
  defp handle_system_notification(system, system_name) do
    notifications_enabled = Config.system_notifications_enabled?()
    is_priority = is_priority_system?(system_name)
    priority_only_mode = Config.priority_systems_only?()

    case {notifications_enabled, is_priority, priority_only_mode} do
      {_, true, _} ->
        # Priority systems always send notifications with @here mention
        Logger.info("Sending priority system notification",
          system: system_name,
          priority_only_mode: priority_only_mode,
          category: :processor
        )

        send_domain_system_notification(system, true)

      {true, false, false} ->
        # Regular notification path - send without @here (normal mode)
        Logger.info("Sending system notification",
          system: system_name,
          priority: false,
          category: :processor
        )

        send_domain_system_notification(system, false)

      {_, false, true} ->
        # Priority-only mode: skip non-priority systems
        Logger.info("Skipping non-priority system notification (priority-only mode)",
          system: system_name,
          category: :processor
        )

        :skip

      {false, false, false} ->
        # Skip notification - disabled and not priority (normal mode)
        Logger.info("Skipping system notification (disabled and not priority)",
          system: system_name,
          category: :processor
        )

        :skip
    end
  end

  # Generates a consistent hash for system names
  defp hash_system_name(system_name) do
    # Use phash2 for consistent hashing across restarts
    system_name
    |> String.trim()
    |> String.downcase()
    |> :erlang.phash2()
  end

  @doc """
  Sends a rally point notification.
  """
  def notify_rally_point(rally_point) do
    if Config.rally_notifications_enabled?() do
      Logger.info("Sending rally point notification",
        system: rally_point.system_name,
        character: rally_point.character_name,
        category: :processor
      )

      # Send rally point notification through Discord notifier
      DiscordNotifier.send_rally_point_notification(rally_point)
    else
      Logger.info("Rally point notifications disabled, skipping",
        category: :processor
      )

      :skip
    end
  end

  # Legacy text-based notification functions removed - using domain service with rich embeds
end
