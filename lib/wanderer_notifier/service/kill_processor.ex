defmodule WandererNotifier.Service.KillProcessor do
  @moduledoc """
  Handles kill messages from zKill, including enrichment and deciding
  whether to send a Discord notification.
  Only notifies if the kill is from a tracked system or involves a tracked character.
  """
  require Logger
  alias WandererNotifier.ZKill.Service, as: ZKillService
  alias WandererNotifier.Discord.Notifier
  alias WandererNotifier.Cache.Repository, as: CacheRepo
  alias WandererNotifier.Config
  alias WandererNotifier.Features

  def process_zkill_message(message, state) do
    # Always process basic notifications regardless of license
    if Features.enabled?(:basic_notifications) do
      case decode_zkill_message(message) do
        {:ok, {kill_id, system_id}} ->
          # Check if this is a tracked system notification (requires valid license)
          tracked_system = kill_from_tracked_system?(system_id) && 
                          Features.enabled?(:tracked_systems_notifications)
          
          if tracked_system do
            Logger.info("Kill #{kill_id} is from tracked system #{system_id}.")
            process_kill(kill_id, state)
          else
            # Check if this involves a tracked character (requires valid license)
            if Features.enabled?(:tracked_characters_notifications) do
              case ZKillService.get_enriched_killmail(kill_id) do
                {:ok, enriched_kill} ->
                  if kill_includes_tracked_character?(enriched_kill) do
                    Logger.info("Kill #{kill_id} involves a tracked character.")
                    process_kill(kill_id, state)
                  else
                    Logger.info(
                      "Kill #{kill_id} ignored: not from tracked system or involving tracked character."
                    )

                    state
                  end

                {:error, err} ->
                  Logger.error("Error enriching kill #{kill_id}: #{inspect(err)}")
                  state
              end
            else
              Logger.info("Character tracking notifications disabled due to license restrictions")
              state
            end
          end

        :error ->
          Logger.error("Failed to decode zKill message: #{message}")
          state
      end
    else
      Logger.warning("All notifications disabled due to license restrictions")
      state
    end
  end

  def decode_zkill_message(json) do
    try do
      case Jason.decode(json, keys: :strings) do
        {:ok, %{"killmail_id" => kill_id, "solar_system_id" => sys_id}} ->
          {:ok, {kill_id, sys_id}}

        {:ok, %{"killmail_id" => kill_id, "zkb" => %{"locationID" => location_id}}} ->
          # Some messages might have locationID instead of solar_system_id
          {:ok, {kill_id, location_id}}

        {:ok, %{"kill_id" => kill_id, "solar_system_id" => sys_id}} ->
          # Alternative format sometimes used
          {:ok, {kill_id, sys_id}}

        {:ok, other} ->
          Logger.warning("Unrecognized zKill message format: #{inspect(other)}")
          :error

        {:error, err} ->
          Logger.error("Error decoding zKill JSON: #{inspect(err)}")
          :error
      end
    rescue
      e ->
        Logger.error("Exception decoding zKill message: #{inspect(e)}")
        :error
    end
  end

  defp process_kill(kill_id, state) do
    if Map.has_key?(state.processed_kill_ids, kill_id) do
      Logger.info("Kill mail #{kill_id} already processed, skipping.")
      state
    else
      do_enrich_and_notify(kill_id)

      %{
        state
        | processed_kill_ids: Map.put(state.processed_kill_ids, kill_id, :os.system_time(:second))
      }
    end
  end

  defp do_enrich_and_notify(kill_id) do
    case ZKillService.get_enriched_killmail(kill_id) do
      {:ok, enriched_kill} ->
        Logger.info("Enriched killmail for kill #{kill_id}: #{inspect(enriched_kill)}")
        Notifier.send_enriched_kill_embed(enriched_kill, kill_id)

      {:error, err} ->
        error_msg = "Failed to process kill #{kill_id}: #{inspect(err)}"
        Logger.error(error_msg)
        # Only log the error, don't send Discord notifications for processing errors
    end
  end

  defp kill_from_tracked_system?(system_id) do
    tracked_systems = CacheRepo.get("map:systems") || []
    tracked_ids = Enum.map(tracked_systems, fn s -> to_string(s.system_id) end)
    to_string(system_id) in tracked_ids
  end

  defp kill_includes_tracked_character?(enriched_kill) do
    tracked_characters = Config.tracked_characters()
    tracked_chars = Enum.map(tracked_characters, &to_string/1)

    victim_id = get_in(enriched_kill, ["victim", "character_id"])
    victim_id_str = if victim_id, do: to_string(victim_id), else: nil

    attackers = Map.get(enriched_kill, "attackers", [])
    attacker_ids = Enum.map(attackers, fn a -> to_string(a["character_id"]) end)

    Enum.any?([victim_id_str | attacker_ids], fn id ->
      id && id in tracked_chars
    end)
  end
end
