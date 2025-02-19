defmodule ChainKills.Service.KillProcessor do
  @moduledoc """
  Handles kill messages from zKill, including enrichment and deciding
  whether to send a Discord notification.
  """
  require Logger
  alias ChainKills.Cache.Repository, as: CacheRepo
  alias ChainKills.ZKill.Service, as: ZKillService
  alias ChainKills.Discord.Notifier

  def process_zkill_message(message, state) do
    case decode_zkill_message(message) do
      {:ok, {kill_id, _system_id}} ->
        process_if_not_recent(kill_id, state)

      :error ->
        Logger.error("Failed to decode zKill message: #{message}")
        state
    end
  end

  def decode_zkill_message(json) do
    case Jason.decode(json) do
      {:ok, %{"kill_id" => kill_id, "solar_system_id" => sys_id}} ->
        {:ok, {kill_id, sys_id}}

      _ ->
        :error
    end
  end

  defp process_if_not_recent(kill_id, state) do
    now = :os.system_time(:second)
    already_processed = Map.get(state.processed_kill_ids, kill_id)

    if already_processed && now - already_processed < 3600 do
      Logger.info("Skipping kill #{kill_id}, processed recently.")
      state
    else
      do_enrich_and_maybe_notify(kill_id)
      %{state | processed_kill_ids: Map.put(state.processed_kill_ids, kill_id, now)}
    end
  end

  defp do_enrich_and_maybe_notify(kill_id) do
    case ZKillService.get_enriched_killmail(kill_id) do
      {:ok, enriched_kill} ->
        Logger.info("Enriched killmail: #{inspect(enriched_kill)}")

        if relevant_kill?(enriched_kill) do
          Notifier.send_message("Relevant kill detected (killID=#{kill_id})")
        else
          Logger.info("Kill #{kill_id} not in a tracked system or involving tracked characters.")
        end

      {:error, err} ->
        Notifier.send_message("Failed to process kill #{kill_id}: #{inspect(err)}")
    end
  end

  # Decide if kill is relevant (tracked system or characters)
  defp relevant_kill?(%{"solar_system_id" => sys_id} = kill) do
    system_tracked? = system_tracked?(sys_id)
    chars_tracked?  = kill_has_tracked_char?(kill)
    system_tracked? or chars_tracked?
  end

  defp system_tracked?(sys_id) do
    systems = CacheRepo.get("map:systems") || []
    tracked_ids = Enum.map(systems, & &1.system_id)
    sys_id in tracked_ids
  end

  defp kill_has_tracked_char?(kill) do
    chars = CacheRepo.get("map:characters") || []
    tracked_eve_ids = Enum.map(chars, & &1["eve_id"])

    victim_id = get_in(kill, ["victim", "character_id"])
    attacker_ids =
      kill
      |> Map.get("attackers", [])
      |> Enum.map(& &1["character_id"])
      |> Enum.reject(&is_nil/1)

    (victim_id in tracked_eve_ids) or Enum.any?(attacker_ids, &(&1 in tracked_eve_ids))
  end
end
