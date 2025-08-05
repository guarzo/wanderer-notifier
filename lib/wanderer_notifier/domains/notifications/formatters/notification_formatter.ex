defmodule WandererNotifier.Domains.Notifications.Formatters.NotificationFormatter do
  @moduledoc """
  Main notification formatter that delegates to focused formatters.

  This module acts as a dispatcher, routing notifications to the appropriate
  specialized formatter based on notification type.
  """

  alias WandererNotifier.Domains.Killmail.Killmail
  alias WandererNotifier.Domains.Tracking.Entities.{Character, System}

  alias WandererNotifier.Domains.Notifications.Formatters.{
    KillmailFormatter,
    CharacterFormatter,
    SystemFormatter
  }

  require Logger

  # ═══════════════════════════════════════════════════════════════════════════════
  # Public API
  # ═══════════════════════════════════════════════════════════════════════════════

  @doc """
  Format any notification based on its type.
  """
  def format_notification(%Killmail{} = killmail) do
    KillmailFormatter.format(killmail)
  end

  # Handle killmail notifications that have been converted to maps (e.g., from cache)
  def format_notification(%{killmail_id: _} = killmail_map)
      when is_map_key(killmail_map, :victim_character_id) do
    Logger.debug("NotificationFormatter received killmail as map, converting to struct")
    killmail = struct(Killmail, killmail_map)
    KillmailFormatter.format(killmail)
  end

  def format_notification(%Character{} = character) do
    CharacterFormatter.format(character)
  end

  # Handle character notifications that have been converted to maps (e.g., from cache)
  def format_notification(%{character_id: _} = character_map)
      when is_map_key(character_map, :character_name) and is_map_key(character_map, :tracked) do
    Logger.debug("NotificationFormatter received character as map, converting to struct")
    character = struct(Character, character_map)
    CharacterFormatter.format(character)
  end

  def format_notification(%System{} = system) do
    Logger.debug(
      "NotificationFormatter received System struct with keys: #{inspect(Map.keys(system))}"
    )

    SystemFormatter.format(system)
  end

  # Handle system notifications that have been converted to maps (e.g., from cache)
  def format_notification(%{solar_system_id: _} = system_map)
      when is_map_key(system_map, :name) and is_map_key(system_map, :tracked) do
    Logger.debug("NotificationFormatter received system as map, converting to struct")
    system = struct(System, system_map)
    SystemFormatter.format(system)
  end

  def format_notification(notification) do
    Logger.error("Unknown notification type: #{inspect(notification)}")
    {:error, :unknown_notification_type}
  end

  # ═══════════════════════════════════════════════════════════════════════════════
  # Legacy API - delegate to specific formatters
  # ═══════════════════════════════════════════════════════════════════════════════

  @doc """
  Format a killmail notification (legacy API).
  """
  def format_kill_notification(%Killmail{} = killmail) do
    KillmailFormatter.format(killmail)
  end

  @doc """
  Format a character notification (legacy API).
  """
  def format_character_notification(%Character{} = character) do
    CharacterFormatter.format(character)
  end

  @doc """
  Format a system notification (legacy API).
  """
  def format_system_notification(%System{} = system) do
    SystemFormatter.format(system)
  end

  @doc """
  Format plain text notification (legacy API).
  """
  def format_plain_text(notification) do
    case notification do
      %Killmail{} = killmail -> format_killmail_plain_text(killmail)
      %Character{} = character -> format_character_plain_text(character)
      %System{} = system -> format_system_plain_text(system)
      _ -> "Unknown notification type"
    end
  end

  # ═══════════════════════════════════════════════════════════════════════════════
  # Simple Plain Text Formatting
  # ═══════════════════════════════════════════════════════════════════════════════

  defp format_killmail_plain_text(%Killmail{} = killmail) do
    victim = killmail.victim_character_name || "Unknown pilot"
    system = killmail.system_name || "Unknown system"
    ship = killmail.victim_ship_name || "Unknown ship"

    value =
      if killmail.value && killmail.value > 0,
        do: " (#{format_isk_simple(killmail.value)})",
        else: ""

    "#{victim} lost a #{ship} in #{system}#{value}"
  end

  defp format_character_plain_text(%Character{} = character) do
    "Character #{character.name} is now being tracked"
  end

  defp format_system_plain_text(%System{} = system) do
    "System #{system.name} is now being tracked"
  end

  defp format_isk_simple(value) when is_number(value) do
    cond do
      value >= 1_000_000_000 -> "#{Float.round(value / 1_000_000_000, 1)}B ISK"
      value >= 1_000_000 -> "#{Float.round(value / 1_000_000, 1)}M ISK"
      value >= 1_000 -> "#{Float.round(value / 1_000, 1)}K ISK"
      true -> "#{Float.round(value, 0)} ISK"
    end
  end

  defp format_isk_simple(_), do: "0 ISK"
end
