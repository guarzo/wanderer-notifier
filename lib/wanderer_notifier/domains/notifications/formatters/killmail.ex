defmodule WandererNotifier.Domains.Notifications.Formatters.Killmail do
  @moduledoc """
  Killmail notification formatting utilities.
  Now delegates to the unified formatter for consistency.
  """

  alias WandererNotifier.Domains.Killmail.Killmail
  alias WandererNotifier.Domains.Notifications.Formatters.Unified

  @doc """
  Format a kill notification using the unified formatter.
  Maintains backward compatibility for existing callers.
  """
  def format_kill_notification(%Killmail{} = killmail) do
    Unified.format_notification(killmail)
  end

  @doc """
  Format a killmail for notification.
  Alias for backward compatibility.
  """
  def format_killmail(killmail) do
    format_kill_notification(killmail)
  end

  @doc """
  Get final blow attacker information.
  Exposed for backward compatibility.
  """
  def get_final_blow(attackers) when is_list(attackers) do
    Enum.find(attackers, fn att -> Map.get(att, "final_blow") == true end) ||
      Enum.max_by(attackers, fn att -> Map.get(att, "damage_done", 0) end, fn -> nil end)
  end

  def get_final_blow(_), do: nil
end
