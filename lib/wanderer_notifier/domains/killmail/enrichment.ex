defmodule WandererNotifier.Domains.Killmail.Enrichment do
  @moduledoc """
  Handles fetching recent kills via WandererKills API for system notifications.

  This module was previously responsible for ESI enrichment, but with the migration
  to WebSocket with pre-enriched data, it now only handles recent kills lookup.
  """

  alias WandererNotifier.Domains.Killmail.WandererKillsClient
  require Logger

  @doc """
  Fetches and formats the latest kills for a system (default 3).
  """
  @spec recent_kills_for_system(integer(), non_neg_integer()) :: String.t()
  def recent_kills_for_system(system_id, limit \\ 3) do
    try do
      case WandererKillsClient.get_system_kills(system_id, limit) do
        {:ok, kills} when is_list(kills) and length(kills) > 0 ->
          kills
          |> Enum.map(&format_wanderer_kill/1)
          |> Enum.join("\n")

        {:ok, []} ->
          "No recent kills found"

        {:error, _reason} ->
          "Error retrieving kill data"

        _resp ->
          "Unexpected kill data response"
      end
    rescue
      _e ->
        "Error retrieving kill data"
    end
  end

  # --- Private Functions ---

  # Format a kill from WandererKills API
  defp format_wanderer_kill(kill) do
    killmail_id = Map.get(kill, "killmail_id", "Unknown")
    victim_name = get_in(kill, ["victim", "character_name"]) || "Unknown"
    ship_name = get_in(kill, ["victim", "ship_name"]) || "Unknown Ship"
    value = Map.get(kill, "total_value", 0)

    # Format relative time
    time_str =
      case Map.get(kill, "kill_time") do
        nil -> ""
        time -> format_kill_time(time)
      end

    "[#{ship_name} (#{format_isk_value(value)})](https://zkillboard.com/kill/#{killmail_id}/) - #{victim_name} #{time_str}"
  rescue
    e ->
      Logger.warning("Error formatting WandererKills kill: #{Exception.message(e)}")
      "Unknown kill"
  end

  defp format_kill_time(time_str) when is_binary(time_str) do
    case DateTime.from_iso8601(time_str) do
      {:ok, dt, _} ->
        diff_seconds = DateTime.diff(DateTime.utc_now(), dt, :second)
        format_time_diff(diff_seconds)

      _ ->
        ""
    end
  end

  defp format_kill_time(_), do: ""

  defp format_time_diff(sec) when sec < 60, do: "(just now)"
  defp format_time_diff(sec) when sec < 3_600, do: "(#{div(sec, 60)}m ago)"
  defp format_time_diff(sec) when sec < 86_400, do: "(#{div(sec, 3_600)}h ago)"
  defp format_time_diff(sec), do: "(#{div(sec, 86_400)}d ago)"

  defp format_isk_value(v) when is_number(v) do
    cond do
      v >= 1_000_000_000 -> "#{Float.round(v / 1_000_000_000, 1)}B ISK"
      v >= 1_000_000 -> "#{Float.round(v / 1_000_000, 1)}M ISK"
      v >= 1_000 -> "#{Float.round(v / 1_000, 1)}K ISK"
      true -> "#{trunc(v)} ISK"
    end
  end

  defp format_isk_value(_), do: "0 ISK"
end
