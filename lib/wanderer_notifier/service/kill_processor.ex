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
  alias WandererNotifier.ESI.Service, as: ESIService

  def process_zkill_message(message, state) when is_binary(message) do
    case Jason.decode(message) do
      {:ok, decoded} -> process_decoded_message(decoded, state)
      {:error, error} ->
        Logger.error("Failed to decode zkill message: #{inspect(error)}")
        state
    end
  end

  def process_zkill_message(message, state) when is_map(message) do
    process_decoded_message(message, state)
  end

  defp process_decoded_message(decoded_message, state) do
    kill_id = Map.get(decoded_message, "killmail_id")
    system_id = Map.get(decoded_message, "solar_system_id")

    if kill_in_tracked_system?(system_id) do
      case get_enriched_killmail(kill_id) do
        {:ok, []} ->
          # If enrichment fails, try using the raw message
          if kill_includes_tracked_character?(decoded_message) do
            notify_kill(decoded_message, kill_id)
          end
          state

        {:ok, enriched_kill} ->
          if kill_includes_tracked_character?(enriched_kill) do
            notify_kill(enriched_kill, kill_id)
          end
          state

        {:error, reason} ->
          Logger.error("Failed to get enriched killmail for #{kill_id}: #{inspect(reason)}")
          state
      end
    else
      state
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

  defp kill_in_tracked_system?(system_id) do
    tracked_systems = CacheRepo.get("map:systems") || []
    tracked_ids = Enum.map(tracked_systems, fn s -> to_string(s.system_id) end)
    to_string(system_id) in tracked_ids
  end

  defp kill_includes_tracked_character?(kill_data) do
    tracked_characters = Config.tracked_characters()
    tracked_chars = Enum.map(tracked_characters, &to_string/1)

    # Get victim ID safely
    victim = Map.get(kill_data, "victim", %{})
    victim_id = Map.get(victim, "character_id")
    victim_id_str = if victim_id, do: to_string(victim_id), else: nil

    # Get attacker IDs safely
    attackers = Map.get(kill_data, "attackers", [])
    attacker_ids = Enum.map(attackers, fn a -> to_string(Map.get(a, "character_id")) end)

    # Check if any ID matches tracked characters
    Enum.any?([victim_id_str | attacker_ids], fn id ->
      id && id in tracked_chars
    end)
  end

  defp get_enriched_killmail(kill_id) do
    case ZKillService.get_enriched_killmail(kill_id) do
      {:ok, enriched_kill} ->
        {:ok, enriched_kill}
      {:error, err} ->
        {:error, err}
    end
  end

  defp notify_kill(kill_data, kill_id) do
    if Features.enabled?(:tracked_systems_notifications) do
      Logger.info("Kill #{kill_id} is from tracked system.")
      process_kill(kill_id, %{})
    else
      if Features.enabled?(:tracked_characters_notifications) do
        case get_enriched_killmail(kill_id) do
          {:ok, enriched_kill} ->
            if kill_includes_tracked_character?(enriched_kill) do
              Logger.info("Kill #{kill_id} involves a tracked character.")
              process_kill(kill_id, %{})
            else
              Logger.info(
                "Kill #{kill_id} ignored: not from tracked system or involving tracked character."
              )
              %{}
            end
          {:error, err} ->
            Logger.error("Failed to get enriched killmail for #{kill_id}: #{inspect(err)}")
            %{}
        end
      else
        Logger.info("Character tracking notifications disabled due to license restrictions")
        %{}
      end
    end
  end
end
