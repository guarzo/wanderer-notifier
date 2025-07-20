defmodule WandererNotifier.Shared.Logger.Logger do
  @moduledoc """
  Simplified logging module for WandererNotifier.

  This replaces the complex logging infrastructure with simple delegations to Elixir's Logger.
  Provides minimal metadata handling and category helpers without macros or behaviors.
  """

  require Logger

  # Simple delegations to Elixir's Logger
  def debug(msg, metadata \\ []), do: Logger.debug(msg, metadata)
  def info(msg, metadata \\ []), do: Logger.info(msg, metadata)
  def warn(msg, metadata \\ []), do: Logger.warning(msg, metadata)
  def error(msg, metadata \\ []), do: Logger.error(msg, metadata)

  # Minimal category helpers
  def api_info(msg, metadata \\ []) do
    Logger.info(msg, Keyword.put(metadata, :category, :api))
  end

  def api_error(msg, metadata \\ []) do
    Logger.error(msg, Keyword.put(metadata, :category, :api))
  end

  def processor_info(msg, metadata \\ []) do
    Logger.info(msg, Keyword.put(metadata, :category, :processor))
  end

  def processor_error(msg, metadata \\ []) do
    Logger.error(msg, Keyword.put(metadata, :category, :processor))
  end

  def processor_warn(msg, metadata \\ []) do
    Logger.warning(msg, Keyword.put(metadata, :category, :processor))
  end

  def kill_info(msg, metadata \\ []) do
    Logger.info(msg, Keyword.put(metadata, :category, :kill))
  end

  def notification_error(msg, metadata \\ []) do
    Logger.error(msg, Keyword.put(metadata, :category, :notification))
  end

  def config_info(msg, metadata \\ []) do
    Logger.info(msg, Keyword.put(metadata, :category, :config))
  end

  def config_error(msg, metadata \\ []) do
    Logger.error(msg, Keyword.put(metadata, :category, :config))
  end

  # For backward compatibility with existing code
  def cache_debug(msg, metadata \\ []) do
    Logger.debug(msg, Keyword.put(metadata, :category, :cache))
  end

  def cache_info(msg, metadata \\ []) do
    Logger.info(msg, Keyword.put(metadata, :category, :cache))
  end

  def cache_error(msg, metadata \\ []) do
    Logger.error(msg, Keyword.put(metadata, :category, :cache))
  end

  # Discord logging methods that were missing
  def discord_info(msg, metadata \\ []) do
    Logger.info(msg, Keyword.put(metadata, :category, :discord))
  end

  def discord_error(msg, metadata \\ []) do
    Logger.error(msg, Keyword.put(metadata, :category, :discord))
  end

  def discord_warn(msg, metadata \\ []) do
    Logger.warning(msg, Keyword.put(metadata, :category, :discord))
  end

  def discord_debug(msg, metadata \\ []) do
    Logger.debug(msg, Keyword.put(metadata, :category, :discord))
  end

  # System logging
  def system_info(msg, metadata \\ []) do
    Logger.info(msg, Keyword.put(metadata, :category, :system))
  end

  def system_error(msg, metadata \\ []) do
    Logger.error(msg, Keyword.put(metadata, :category, :system))
  end

  def character_info(msg, metadata \\ []) do
    Logger.info(msg, Keyword.put(metadata, :category, :character))
  end

  def character_error(msg, metadata \\ []) do
    Logger.error(msg, Keyword.put(metadata, :category, :character))
  end

  # Additional backward compatibility methods
  def startup_info(msg, metadata \\ []) do
    Logger.info(msg, Keyword.put(metadata, :category, :startup))
  end

  def startup_error(msg, metadata \\ []) do
    Logger.error(msg, Keyword.put(metadata, :category, :startup))
  end

  def startup_warn(msg, metadata \\ []) do
    Logger.warning(msg, Keyword.put(metadata, :category, :startup))
  end

  def startup_debug(msg, metadata \\ []) do
    Logger.debug(msg, Keyword.put(metadata, :category, :startup))
  end

  def api_debug(msg, metadata \\ []) do
    Logger.debug(msg, Keyword.put(metadata, :category, :api))
  end

  def api_warn(msg, metadata \\ []) do
    Logger.warning(msg, Keyword.put(metadata, :category, :api))
  end

  def processor_debug(msg, metadata \\ []) do
    Logger.debug(msg, Keyword.put(metadata, :category, :processor))
  end

  def kill_error(msg, metadata \\ []) do
    Logger.error(msg, Keyword.put(metadata, :category, :kill))
  end

  def kill_warn(msg, metadata \\ []) do
    Logger.warning(msg, Keyword.put(metadata, :category, :kill))
  end

  def config_warn(msg, metadata \\ []) do
    Logger.warning(msg, Keyword.put(metadata, :category, :config))
  end

  def config_debug(msg, metadata \\ []) do
    Logger.debug(msg, Keyword.put(metadata, :category, :config))
  end

  def scheduler_info(msg, metadata \\ []) do
    Logger.info(msg, Keyword.put(metadata, :category, :scheduler))
  end

  def scheduler_error(msg, metadata \\ []) do
    Logger.error(msg, Keyword.put(metadata, :category, :scheduler))
  end

  def maintenance_info(msg, metadata \\ []) do
    Logger.info(msg, Keyword.put(metadata, :category, :maintenance))
  end

  def maintenance_error(msg, metadata \\ []) do
    Logger.error(msg, Keyword.put(metadata, :category, :maintenance))
  end
end
