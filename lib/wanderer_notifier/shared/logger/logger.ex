defmodule WandererNotifier.Shared.Logger.Logger do
  @moduledoc """
  Simplified logging module for WandererNotifier.

  This replaces the complex logging infrastructure with simple delegations to Elixir's Logger.
  Provides minimal metadata handling and category helpers without macros or behaviors.
  """

  require Logger

  # Convert maps to keyword lists for Logger compatibility
  defp ensure_keyword_list(metadata) when is_map(metadata), do: Map.to_list(metadata)
  defp ensure_keyword_list(metadata) when is_list(metadata), do: metadata
  defp ensure_keyword_list(_), do: []

  # Simple delegations to Elixir's Logger
  def debug(msg, metadata \\ []), do: Logger.debug(msg, metadata)
  def info(msg, metadata \\ []), do: Logger.info(msg, metadata)
  def warn(msg, metadata \\ []), do: Logger.warning(msg, metadata)
  def error(msg, metadata \\ []), do: Logger.error(msg, metadata)

  # Minimal category helpers
  def api_info(msg, metadata \\ []) do
    Logger.info(msg, ensure_keyword_list(metadata) |> Keyword.put(:category, :api))
  end

  def api_error(msg, metadata \\ []) do
    Logger.error(msg, ensure_keyword_list(metadata) |> Keyword.put(:category, :api))
  end

  def processor_info(msg, metadata \\ []) do
    Logger.info(msg, ensure_keyword_list(metadata) |> Keyword.put(:category, :processor))
  end

  def processor_error(msg, metadata \\ []) do
    Logger.error(msg, ensure_keyword_list(metadata) |> Keyword.put(:category, :processor))
  end

  def processor_warn(msg, metadata \\ []) do
    Logger.warning(msg, ensure_keyword_list(metadata) |> Keyword.put(:category, :processor))
  end

  def kill_info(msg, metadata \\ []) do
    Logger.info(msg, ensure_keyword_list(metadata) |> Keyword.put(:category, :kill))
  end

  def kill_debug(msg, metadata \\ []) do
    Logger.debug(msg, ensure_keyword_list(metadata) |> Keyword.put(:category, :kill))
  end

  def notification_error(msg, metadata \\ []) do
    Logger.error(msg, ensure_keyword_list(metadata) |> Keyword.put(:category, :notification))
  end

  def config_info(msg, metadata \\ []) do
    Logger.info(msg, ensure_keyword_list(metadata) |> Keyword.put(:category, :config))
  end

  def config_error(msg, metadata \\ []) do
    Logger.error(msg, ensure_keyword_list(metadata) |> Keyword.put(:category, :config))
  end

  # For backward compatibility with existing code
  def cache_debug(msg, metadata \\ []) do
    Logger.debug(msg, ensure_keyword_list(metadata) |> Keyword.put(:category, :cache))
  end

  def cache_info(msg, metadata \\ []) do
    Logger.info(msg, ensure_keyword_list(metadata) |> Keyword.put(:category, :cache))
  end

  def cache_error(msg, metadata \\ []) do
    Logger.error(msg, ensure_keyword_list(metadata) |> Keyword.put(:category, :cache))
  end

  # Discord logging methods that were missing
  def discord_info(msg, metadata \\ []) do
    Logger.info(msg, ensure_keyword_list(metadata) |> Keyword.put(:category, :discord))
  end

  def discord_error(msg, metadata \\ []) do
    Logger.error(msg, ensure_keyword_list(metadata) |> Keyword.put(:category, :discord))
  end

  def discord_warn(msg, metadata \\ []) do
    Logger.warning(msg, ensure_keyword_list(metadata) |> Keyword.put(:category, :discord))
  end

  def discord_debug(msg, metadata \\ []) do
    Logger.debug(msg, ensure_keyword_list(metadata) |> Keyword.put(:category, :discord))
  end

  # System logging
  def system_info(msg, metadata \\ []) do
    Logger.info(msg, ensure_keyword_list(metadata) |> Keyword.put(:category, :system))
  end

  def system_error(msg, metadata \\ []) do
    Logger.error(msg, ensure_keyword_list(metadata) |> Keyword.put(:category, :system))
  end

  def character_info(msg, metadata \\ []) do
    Logger.info(msg, ensure_keyword_list(metadata) |> Keyword.put(:category, :character))
  end

  def character_error(msg, metadata \\ []) do
    Logger.error(msg, ensure_keyword_list(metadata) |> Keyword.put(:category, :character))
  end

  # Additional backward compatibility methods
  def startup_info(msg, metadata \\ []) do
    Logger.info(msg, ensure_keyword_list(metadata) |> Keyword.put(:category, :startup))
  end

  def startup_error(msg, metadata \\ []) do
    Logger.error(msg, ensure_keyword_list(metadata) |> Keyword.put(:category, :startup))
  end

  def startup_warn(msg, metadata \\ []) do
    Logger.warning(msg, ensure_keyword_list(metadata) |> Keyword.put(:category, :startup))
  end

  def startup_debug(msg, metadata \\ []) do
    Logger.debug(msg, ensure_keyword_list(metadata) |> Keyword.put(:category, :startup))
  end

  def api_debug(msg, metadata \\ []) do
    Logger.debug(msg, ensure_keyword_list(metadata) |> Keyword.put(:category, :api))
  end

  def api_warn(msg, metadata \\ []) do
    Logger.warning(msg, ensure_keyword_list(metadata) |> Keyword.put(:category, :api))
  end

  def processor_debug(msg, metadata \\ []) do
    Logger.debug(msg, ensure_keyword_list(metadata) |> Keyword.put(:category, :processor))
  end

  def kill_error(msg, metadata \\ []) do
    Logger.error(msg, ensure_keyword_list(metadata) |> Keyword.put(:category, :kill))
  end

  def kill_warn(msg, metadata \\ []) do
    Logger.warning(msg, ensure_keyword_list(metadata) |> Keyword.put(:category, :kill))
  end

  def config_warn(msg, metadata \\ []) do
    Logger.warning(msg, ensure_keyword_list(metadata) |> Keyword.put(:category, :config))
  end

  def config_debug(msg, metadata \\ []) do
    Logger.debug(msg, ensure_keyword_list(metadata) |> Keyword.put(:category, :config))
  end

  def scheduler_info(msg, metadata \\ []) do
    Logger.info(msg, ensure_keyword_list(metadata) |> Keyword.put(:category, :scheduler))
  end

  def scheduler_error(msg, metadata \\ []) do
    Logger.error(msg, ensure_keyword_list(metadata) |> Keyword.put(:category, :scheduler))
  end

  def maintenance_info(msg, metadata \\ []) do
    Logger.info(msg, ensure_keyword_list(metadata) |> Keyword.put(:category, :maintenance))
  end

  def maintenance_error(msg, metadata \\ []) do
    Logger.error(msg, ensure_keyword_list(metadata) |> Keyword.put(:category, :maintenance))
  end
end
