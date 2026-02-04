defmodule WandererNotifier.Domains.Notifications.Formatters.NotificationFormatter do
  @moduledoc """
  Main notification formatter that delegates to focused formatters.

  This module acts as a dispatcher, routing notifications to the appropriate
  specialized formatter based on notification type.
  """

  alias WandererNotifier.Domains.Killmail.Killmail
  alias WandererNotifier.Domains.Tracking.Entities.{Character, System}
  alias WandererNotifier.Shared.Utils.FormattingUtils

  alias WandererNotifier.Domains.Notifications.Formatters.{
    KillmailFormatter,
    CharacterFormatter,
    SystemFormatter,
    RallyFormatter
  }

  require Logger

  # ═══════════════════════════════════════════════════════════════════════════════
  # Public API
  # ═══════════════════════════════════════════════════════════════════════════════

  @doc """
  Format any notification based on its type.

  ## Options for killmail notifications
    - `:use_custom_system_name` - When true, uses Wanderer custom/temporary name for system.
      When false, uses EVE system name. Defaults to false.
  """
  def format_notification(notification, opts \\ [])

  def format_notification(%Killmail{} = killmail, opts) do
    {:ok, KillmailFormatter.format(killmail, opts)}
  end

  # Handle killmail notifications that have been converted to maps (e.g., from cache)
  def format_notification(%{killmail_id: _} = killmail_map, opts)
      when is_map_key(killmail_map, :victim_character_id) do
    Logger.debug("NotificationFormatter received killmail as map, converting to struct")
    killmail = struct(Killmail, killmail_map)
    {:ok, KillmailFormatter.format(killmail, opts)}
  end

  def format_notification(%Character{} = character, opts) do
    {:ok, CharacterFormatter.format_embed(character, opts)}
  end

  # Handle character notifications that have been converted to maps (e.g., from cache)
  def format_notification(%{character_id: _} = character_map, opts)
      when is_map_key(character_map, :character_name) and is_map_key(character_map, :tracked) do
    Logger.debug("NotificationFormatter received character as map, converting to struct")
    character = struct(Character, character_map)
    {:ok, CharacterFormatter.format_embed(character, opts)}
  end

  def format_notification(%System{} = system, opts) do
    Logger.debug(
      "NotificationFormatter received System struct with keys: #{inspect(Map.keys(system))}"
    )

    {:ok, SystemFormatter.format_embed(system, opts)}
  end

  # Handle system notifications that have been converted to maps (e.g., from cache)
  def format_notification(%{solar_system_id: _} = system_map, opts)
      when is_map_key(system_map, :name) and is_map_key(system_map, :tracked) do
    Logger.debug("NotificationFormatter received system as map, converting to struct")
    system = struct(System, system_map)
    {:ok, SystemFormatter.format_embed(system, opts)}
  end

  # Handle rally point notifications
  def format_notification(%{id: _, system_id: _, character_eve_id: _} = rally_point, _opts) do
    Logger.debug("NotificationFormatter received rally point: #{inspect(rally_point)}")
    {:ok, RallyFormatter.format_embed(rally_point)}
  end

  # Handle alternate rally point format
  def format_notification(%{id: _, system_name: _, character_name: _} = rally_point, _opts) do
    Logger.debug("NotificationFormatter received rally point: #{inspect(rally_point)}")
    {:ok, RallyFormatter.format_embed(rally_point)}
  end

  def format_notification(notification, _opts) do
    Logger.error("Unknown notification type: #{inspect(notification)}")
    {:error, :unknown_notification_type}
  end

  # ═══════════════════════════════════════════════════════════════════════════════
  # Convenience Functions
  # ═══════════════════════════════════════════════════════════════════════════════

  @doc """
  Format a killmail notification.
  """
  def format_kill_notification(%Killmail{} = killmail) do
    KillmailFormatter.format(killmail)
  end

  @doc """
  Format a character notification.
  """
  def format_character_notification(%Character{} = character) do
    CharacterFormatter.format_embed(character)
  end

  @doc """
  Format a system notification.
  """
  def format_system_notification(%System{} = system) do
    SystemFormatter.format_embed(system)
  end

  @doc """
  Format plain text notification.
  """
  def format_plain_text(notification) do
    case notification do
      %Killmail{} = killmail -> format_killmail_plain_text(killmail)
      %Character{} = character -> format_character_plain_text(character)
      %System{} = system -> format_system_plain_text(system)
      %{id: _} = rally_point -> format_rally_plain_text(rally_point)
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
        do: " (#{format_isk_simple(killmail.value)} ISK)",
        else: ""

    "#{victim} lost a #{ship} in #{system}#{value}"
  end

  defp format_character_plain_text(%Character{} = character) do
    "Character #{character.name} is now being tracked"
  end

  defp format_system_plain_text(%System{} = system) do
    "System #{system.name} is now being tracked"
  end

  defp format_rally_plain_text(rally_point) do
    RallyFormatter.format_plain_text(rally_point)
  end

  # Use centralized ISK formatting
  defp format_isk_simple(value), do: FormattingUtils.format_isk(value)
end
