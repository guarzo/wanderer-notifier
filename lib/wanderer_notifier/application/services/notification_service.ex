defmodule WandererNotifier.Application.Services.NotificationService do
  @moduledoc """
  Backward compatibility adapter for the NotificationService.
  
  This module maintains the existing NotificationService API while delegating
  to the new ApplicationService's NotificationCoordinator for actual functionality.
  
  The original NotificationService mixed priority system logic with notification
  coordination. The new architecture separates these concerns:
  - Priority system logic remains here for backward compatibility
  - Notification coordination is handled by ApplicationService.NotificationCoordinator
  """
  
  require Logger
  alias WandererNotifier.Application.Services.ApplicationService
  alias WandererNotifier.PersistentValues
  alias WandererNotifier.Shared.Config
  alias WandererNotifier.Domains.Tracking.Entities.System
  
  @priority_systems_key :priority_systems
  
  # ──────────────────────────────────────────────────────────────────────────────
  # Notification API - delegated to ApplicationService
  # ──────────────────────────────────────────────────────────────────────────────
  
  @doc """
  Sends a system notification with priority system logic.
  """
  @spec notify_system(map() | String.t() | System.t()) :: :ok | :skip | {:error, term()}
  def notify_system(%System{} = system) do
    system_name = system.name || "Unknown System"
    handle_system_notification(system, system_name)
  end
  
  def notify_system(system) when is_map(system) do
    system_name = system["name"] || "Unknown System"
    handle_system_notification(system, system_name)
  end
  
  def notify_system(system_name) when is_binary(system_name) do
    system = %{"name" => system_name}
    notify_system(system)
  end
  
  @doc """
  Sends a character notification.
  """
  @spec notify_character(map()) :: :ok | {:error, term()}
  def notify_character(character) do
    if Config.character_notifications_enabled?() do
      Logger.info("Sending character notification",
        character_id: Map.get(character, :character_id),
        character_name: Map.get(character, :name),
        category: :processor
      )
      
      case ApplicationService.process_notification(character) do
        {:ok, :sent} -> :ok
        {:ok, :skipped} -> :ok
        {:error, reason} -> {:error, reason}
      end
    else
      Logger.info("Skipping character notification (disabled)", category: :processor)
      {:error, :notifications_disabled}
    end
  end
  
  @doc """
  Sends a killmail notification.
  """
  @spec notify_kill(map()) :: :ok | {:error, term()}
  def notify_kill(kill_data) do
    if Config.kill_notifications_enabled?() do
      Logger.info("Sending kill notification",
        killmail_id: Map.get(kill_data, :killmail_id),
        category: :processor
      )
      
      case ApplicationService.notify_kill(kill_data) do
        {:ok, :sent} -> :ok
        {:ok, :skipped} -> :ok
        {:error, reason} -> {:error, reason}
      end
    else
      Logger.info("Skipping kill notification (disabled)", category: :processor)
      {:error, :notifications_disabled}
    end
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
      
      # For now, handle rally points through the original Discord notifier
      # This could be migrated to ApplicationService in the future
      alias WandererNotifier.Domains.Notifications.Notifiers.Discord.Notifier, as: DiscordNotifier
      DiscordNotifier.send_rally_point_notification(rally_point)
    else
      Logger.info("Rally point notifications disabled, skipping", category: :processor)
      :skip
    end
  end
  
  # ──────────────────────────────────────────────────────────────────────────────
  # Priority System Management (unchanged)
  # ──────────────────────────────────────────────────────────────────────────────
  
  @doc """
  Registers a system as priority.
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
  """
  @spec list_priority_systems() :: [integer()]
  def list_priority_systems do
    PersistentValues.get(@priority_systems_key)
  end
  
  @doc """
  Gets statistics about priority systems.
  """
  @spec priority_system_stats() :: %{count: non_neg_integer(), notifications_enabled: boolean()}
  def priority_system_stats do
    %{
      count: length(list_priority_systems()),
      notifications_enabled: Config.system_notifications_enabled?()
    }
  end
  
  @doc """
  Clears all priority systems.
  """
  @spec clear_priority_systems() :: :ok
  def clear_priority_systems do
    PersistentValues.put(@priority_systems_key, [])
    Logger.info("Cleared all priority systems", category: :config)
    :ok
  end
  
  # ──────────────────────────────────────────────────────────────────────────────
  # Private Helpers
  # ──────────────────────────────────────────────────────────────────────────────
  
  defp handle_system_notification(system, system_name) do
    notifications_enabled = Config.system_notifications_enabled?()
    is_priority = is_priority_system?(system_name)
    priority_only_mode = Config.priority_systems_only?()
    
    case {notifications_enabled, is_priority, priority_only_mode} do
      {_, true, _} ->
        # Priority systems always send notifications
        Logger.info("Sending priority system notification",
          system: system_name,
          priority_only_mode: priority_only_mode,
          category: :processor
        )
        
        # Add priority flag to system data
        system_with_priority = add_priority_flag(system, true)
        send_system_notification(system_with_priority)
        
      {true, false, false} ->
        # Regular notification path
        Logger.info("Sending system notification",
          system: system_name,
          priority: false,
          category: :processor
        )
        
        system_with_priority = add_priority_flag(system, false)
        send_system_notification(system_with_priority)
        
      {_, false, true} ->
        # Priority-only mode: skip non-priority systems
        Logger.info("Skipping non-priority system notification (priority-only mode)",
          system: system_name,
          category: :processor
        )
        :skip
        
      {false, false, false} ->
        # Skip notification - disabled and not priority
        Logger.info("Skipping system notification (disabled and not priority)",
          system: system_name,
          category: :processor
        )
        :skip
    end
  end
  
  defp add_priority_flag(system, is_priority) do
    case system do
      %System{} = s -> Map.put(s, :priority, is_priority)
      map -> Map.put(map, :priority, is_priority)
    end
  end
  
  defp send_system_notification(system) do
    case ApplicationService.process_notification(system) do
      {:ok, :sent} -> :ok
      {:ok, :skipped} -> :skip
      {:error, reason} -> {:error, reason}
    end
  end
  
  defp hash_system_name(system_name) do
    system_name
    |> String.trim()
    |> String.downcase()
    |> :erlang.phash2()
  end
end