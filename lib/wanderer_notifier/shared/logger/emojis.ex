defmodule WandererNotifier.Shared.Logger.Emojis do
  @moduledoc """
  Centralized emoji definitions for consistent use in log messages.
  """

  # Status Emojis
  @doc "Success emoji"
  def success, do: "✅"

  @doc "Error emoji"
  def error, do: "❌"

  @doc "Warning emoji"
  def warning, do: "⚠️"

  @doc "Info emoji"
  def info, do: "ℹ️"

  @doc "Debug emoji"
  def debug, do: "🔍"

  # Operation Emojis
  @doc "Start/Play emoji"
  def start, do: "▶️"

  @doc "Stop emoji"
  def stop, do: "⏹️"

  @doc "Pause emoji"
  def pause, do: "⏸️"

  @doc "Retry/Repeat emoji"
  def retry, do: "🔄"

  @doc "Skip emoji"
  def skip, do: "⏭️"

  # Cache Emojis
  @doc "Cache hit emoji"
  def cache_hit, do: "✨"

  @doc "Cache miss emoji"
  def cache_miss, do: "🔍"

  # Killmail Emojis
  @doc "Killmail/Death emoji"
  def killmail, do: "💀"

  @doc "Ship emoji"
  def ship, do: "🚀"

  @doc "Explosion emoji"
  def explosion, do: "💥"

  # Notification Emojis
  @doc "Bell/Notification emoji"
  def notification, do: "🔔"

  @doc "Message/Mail emoji"
  def message, do: "📧"

  @doc "Sent emoji"
  def sent, do: "📤"

  # System Emojis
  @doc "Clock/Time emoji"
  def time, do: "🕐"

  @doc "Calendar emoji"
  def calendar, do: "📅"

  @doc "Lock/Security emoji"
  def lock, do: "🔒"

  @doc "Key emoji"
  def key, do: "🔑"

  # Data Emojis
  @doc "Database emoji"
  def database, do: "🗄️"

  @doc "Folder emoji"
  def folder, do: "📁"

  @doc "Document emoji"
  def document, do: "📄"

  # Network Emojis
  @doc "Globe/Network emoji"
  def network, do: "🌐"

  @doc "Link emoji"
  def link, do: "🔗"

  @doc "Signal emoji"
  def signal, do: "📶"

  # Performance Emojis
  @doc "Chart/Metrics emoji"
  def metrics, do: "📊"

  @doc "Fire/Hot emoji"
  def hot, do: "🔥"

  @doc "Snowflake/Cold emoji"
  def cold, do: "❄️"

  # Helper Functions

  @doc """
  Returns an emoji based on HTTP status code.
  """
  def for_status_code(code) when code >= 200 and code < 300, do: success()
  def for_status_code(code) when code >= 300 and code < 400, do: warning()
  def for_status_code(code) when code >= 400 and code < 500, do: error()
  def for_status_code(code) when code >= 500, do: error()
  def for_status_code(_), do: info()

  @doc """
  Returns an emoji for killmail skip reasons.
  """
  def for_skip_reason(:no_tracked_character), do: skip()
  def for_skip_reason(:no_tracked_system), do: skip()
  def for_skip_reason(:duplicate), do: retry()
  def for_skip_reason(:low_value), do: "💸"
  def for_skip_reason(:npc_only), do: "🤖"
  def for_skip_reason(_), do: skip()
end
