defmodule WandererNotifier.Domains.Notifications.Formatters.PlainText do
  @moduledoc """
  Provides plain text fallback formatting for notifications when license is invalid.
  """

  def plain_system_notification(system) do
    name = Map.get(system, :name) || Map.get(system, "name") || "unknown"
    id = Map.get(system, :solar_system_id) || Map.get(system, "solar_system_id") || "?"
    "System mapped: #{name} (ID: #{id})"
  end

  def plain_character_notification(character) do
    name = Map.get(character, :name) || Map.get(character, "name") || "Unknown Character"
    id = Map.get(character, :character_id) || Map.get(character, "character_id") || "?"
    corp = Map.get(character, :corporation_ticker) || Map.get(character, "corporation_ticker")
    base = "Character tracked: #{name} (ID: #{id})"
    if corp, do: base <> ", Corp: #{corp}", else: base
  end

  def plain_killmail_notification(killmail) do
    victim = get_in(killmail, [:esi_data, "victim"]) || %{}
    victim_name = Map.get(victim, "character_id") || "Unknown"
    ship = Map.get(victim, "ship_type_name") || "Unknown Ship"
    system = Map.get(killmail, :solar_system_id) || Map.get(killmail, "solar_system_id") || "?"
    time = Map.get(killmail, :killmail_time) || Map.get(killmail, "killmail_time") || "?"
    "Kill: Victim #{victim_name} lost #{ship} in system #{system} at #{time}"
  end
end
