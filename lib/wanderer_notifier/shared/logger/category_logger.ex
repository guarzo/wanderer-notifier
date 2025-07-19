defmodule WandererNotifier.Shared.Logger.CategoryLogger do
  @moduledoc """
  Category-specific logging functions for WandererNotifier.

  This module provides specialized logging functions for different application categories,
  reducing the main Logger module complexity by ~450 lines.

  ## Categories
  - Processor: For killmail and event processing
  - API: For external API interactions
  - Cache: For caching operations
  - Websocket: For WebSocket connections
  - Notification: For notification sending
  - Kill: For killmail-specific events
  - Character: For character-related events
  - System: For system-related events
  - Config: For configuration loading
  - Scheduler: For background jobs
  - Startup: For application startup
  - Maintenance: For maintenance tasks

  ## Usage
  ```elixir
  alias WandererNotifier.Shared.Logger.CategoryLogger

  CategoryLogger.api_info("API request received", endpoint: "/systems")
  CategoryLogger.cache_debug("Cache miss", key: "users:123")
  CategoryLogger.processor_error("Failed to process killmail", error: reason)
  ```
  """

  require Logger
  alias WandererNotifier.Shared.Logger.Logger, as: MainLogger

  # Category constants
  @category_processor :processor
  @category_scheduler :scheduler
  @category_config :config
  @category_startup :startup
  @category_kill :kill
  @category_character :character
  @category_system :system
  @category_notification :notification
  @category_api :api
  @category_cache :cache
  @category_websocket :websocket
  @category_maintenance :maintenance

  # Level constants
  @level_debug :debug
  @level_info :info
  @level_warn :warning
  @level_error :error

  # ========== Processor Category ==========
  def processor_debug(message, metadata \\ []) do
    MainLogger.log(@level_debug, @category_processor, message, metadata)
  end

  def processor_info(message, metadata \\ []) do
    MainLogger.log(@level_info, @category_processor, message, metadata)
  end

  def processor_warn(message, metadata \\ []) do
    MainLogger.log(@level_warn, @category_processor, message, metadata)
  end

  def processor_error(message, metadata \\ []) do
    MainLogger.log(@level_error, @category_processor, message, metadata)
  end

  def processor_kv(message, value) do
    MainLogger.info_kv(@category_processor, message, value)
  end

  # ========== API Category ==========
  def api_debug(message, metadata \\ []) do
    MainLogger.log(@level_debug, @category_api, message, metadata)
  end

  def api_info(message, metadata \\ []) do
    MainLogger.log(@level_info, @category_api, message, metadata)
  end

  def api_warn(message, metadata \\ []) do
    MainLogger.log(@level_warn, @category_api, message, metadata)
  end

  def api_error(message, metadata \\ []) do
    MainLogger.log(@level_error, @category_api, message, metadata)
  end

  def api_kv(message, value) do
    MainLogger.info_kv(@category_api, message, value)
  end

  # ========== Cache Category ==========
  def cache_debug(message, metadata \\ []) do
    MainLogger.log(@level_debug, @category_cache, message, metadata)
  end

  def cache_info(message, metadata \\ []) do
    MainLogger.log(@level_info, @category_cache, message, metadata)
  end

  def cache_warn(message, metadata \\ []) do
    MainLogger.log(@level_warn, @category_cache, message, metadata)
  end

  def cache_error(message, metadata \\ []) do
    MainLogger.log(@level_error, @category_cache, message, metadata)
  end

  def cache_kv(message, value) do
    MainLogger.info_kv(@category_cache, message, value)
  end

  # ========== WebSocket Category ==========
  def websocket_debug(message, metadata \\ []) do
    MainLogger.log(@level_debug, @category_websocket, message, metadata)
  end

  def websocket_info(message, metadata \\ []) do
    MainLogger.log(@level_info, @category_websocket, message, metadata)
  end

  def websocket_warn(message, metadata \\ []) do
    MainLogger.log(@level_warn, @category_websocket, message, metadata)
  end

  def websocket_error(message, metadata \\ []) do
    MainLogger.log(@level_error, @category_websocket, message, metadata)
  end

  def websocket_kv(message, value) do
    MainLogger.info_kv(@category_websocket, message, value)
  end

  # ========== Notification Category ==========
  def notification_debug(message, metadata \\ []) do
    MainLogger.log(@level_debug, @category_notification, message, metadata)
  end

  def notification_info(message, metadata \\ []) do
    MainLogger.log(@level_info, @category_notification, message, metadata)
  end

  def notification_warn(message, metadata \\ []) do
    MainLogger.log(@level_warn, @category_notification, message, metadata)
  end

  def notification_error(message, metadata \\ []) do
    MainLogger.log(@level_error, @category_notification, message, metadata)
  end

  def notification_kv(message, value) do
    MainLogger.info_kv(@category_notification, message, value)
  end

  # ========== Kill Category ==========
  def kill_debug(message, metadata \\ []) do
    MainLogger.log(@level_debug, @category_kill, message, metadata)
  end

  def kill_info(message, metadata \\ []) do
    MainLogger.log(@level_info, @category_kill, message, metadata)
  end

  def kill_warn(message, metadata \\ []) do
    MainLogger.log(@level_warn, @category_kill, message, metadata)
  end

  def kill_warning(message, metadata \\ []) do
    kill_warn(message, metadata)
  end

  def kill_error(message, metadata \\ []) do
    MainLogger.log(@level_error, @category_kill, message, metadata)
  end

  def kill_kv(message, value) do
    MainLogger.info_kv(@category_kill, message, value)
  end

  # ========== Character Category ==========
  def character_debug(message, metadata \\ []) do
    MainLogger.log(@level_debug, @category_character, message, metadata)
  end

  def character_info(message, metadata \\ []) do
    MainLogger.log(@level_info, @category_character, message, metadata)
  end

  def character_warn(message, metadata \\ []) do
    MainLogger.log(@level_warn, @category_character, message, metadata)
  end

  def character_error(message, metadata \\ []) do
    MainLogger.log(@level_error, @category_character, message, metadata)
  end

  def character_kv(message, value) do
    MainLogger.info_kv(@category_character, message, value)
  end

  # ========== System Category ==========
  def system_debug(message, metadata \\ []) do
    MainLogger.log(@level_debug, @category_system, message, metadata)
  end

  def system_info(message, metadata \\ []) do
    MainLogger.log(@level_info, @category_system, message, metadata)
  end

  def system_warn(message, metadata \\ []) do
    MainLogger.log(@level_warn, @category_system, message, metadata)
  end

  def system_error(message, metadata \\ []) do
    MainLogger.log(@level_error, @category_system, message, metadata)
  end

  def system_kv(message, value) do
    MainLogger.info_kv(@category_system, message, value)
  end

  # ========== Config Category ==========
  def config_debug(message, metadata \\ []) do
    MainLogger.log(@level_debug, @category_config, message, metadata)
  end

  def config_info(message, metadata \\ []) do
    MainLogger.log(@level_info, @category_config, message, metadata)
  end

  def config_warn(message, metadata \\ []) do
    MainLogger.log(@level_warn, @category_config, message, metadata)
  end

  def config_error(message, metadata \\ []) do
    MainLogger.log(@level_error, @category_config, message, metadata)
  end

  def config_kv(message, value) do
    MainLogger.info_kv(@category_config, message, value)
  end

  # ========== Scheduler Category ==========
  def scheduler_debug(message, metadata \\ []) do
    MainLogger.log(@level_debug, @category_scheduler, message, metadata)
  end

  def scheduler_info(message, metadata \\ []) do
    MainLogger.log(@level_info, @category_scheduler, message, metadata)
  end

  def scheduler_warn(message, metadata \\ []) do
    MainLogger.log(@level_warn, @category_scheduler, message, metadata)
  end

  def scheduler_error(message, metadata \\ []) do
    MainLogger.log(@level_error, @category_scheduler, message, metadata)
  end

  def scheduler_kv(message, value) do
    MainLogger.info_kv(@category_scheduler, message, value)
  end

  # ========== Startup Category ==========
  def startup_debug(message, metadata \\ []) do
    MainLogger.log(@level_debug, @category_startup, message, metadata)
  end

  def startup_info(message, metadata \\ []) do
    MainLogger.log(@level_info, @category_startup, message, metadata)
  end

  def startup_warn(message, metadata \\ []) do
    MainLogger.log(@level_warn, @category_startup, message, metadata)
  end

  def startup_error(message, metadata \\ []) do
    MainLogger.log(@level_error, @category_startup, message, metadata)
  end

  def startup_kv(message, value) do
    MainLogger.info_kv(@category_startup, message, value)
  end

  # ========== Maintenance Category ==========
  def maintenance_debug(message, metadata \\ []) do
    MainLogger.log(@level_debug, @category_maintenance, message, metadata)
  end

  def maintenance_info(message, metadata \\ []) do
    MainLogger.log(@level_info, @category_maintenance, message, metadata)
  end

  def maintenance_warn(message, metadata \\ []) do
    MainLogger.log(@level_warn, @category_maintenance, message, metadata)
  end

  def maintenance_error(message, metadata \\ []) do
    MainLogger.log(@level_error, @category_maintenance, message, metadata)
  end

  def maintenance_kv(message, value) do
    MainLogger.info_kv(@category_maintenance, message, value)
  end
end
