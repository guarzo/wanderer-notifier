defmodule WandererNotifier.Services.CharacterKillsService do
  @moduledoc """
  Service for fetching and processing character kills from ESI.
  """

  require Logger

  # Default implementations
  @default_deps %{
    logger: WandererNotifier.Logger,
    repository: WandererNotifier.Repository,
    esi_service: WandererNotifier.Api.ESI.Service,
    persistence: WandererNotifier.Resources.KillmailPersistence,
    zkill_client: WandererNotifier.Api.ZKill.Client,
    cache_helpers: WandererNotifier.Helpers.CacheHelpers
  }

  @doc """
  Gets kills for a character within a date range.
  """
  @spec get_kills_for_character(integer(), Keyword.t(), map()) ::
          {:ok, list(map())} | {:error, term()}
  def get_kills_for_character(character_id, opts \\ [], deps \\ @default_deps) do
    deps.logger.debug("[CHARACTER_KILLS] Fetching kills for character #{character_id}")

    case fetch_character_kills(character_id, 25, 1, deps) do
      {:ok, kills} when is_list(kills) ->
        filtered_kills = filter_kills_by_date(kills, opts[:from], opts[:to])
        transformed_kills = Enum.map(filtered_kills, &transform_kill(&1, deps))

        case Enum.find(transformed_kills, &match?({:error, _}, &1)) do
          nil -> {:ok, Enum.map(transformed_kills, fn {:ok, kill} -> kill end)}
          {:error, reason} -> {:error, reason}
        end

      {:error, reason} ->
        deps.logger.error("[CHARACTER_KILLS] Failed to fetch kills: #{inspect(reason)}")
        {:error, :api_error}
    end
  end

  @doc """
  Fetches and persists kills for all tracked characters.
  """
  @spec fetch_and_persist_all_tracked_character_kills(integer(), integer(), map()) ::
          {:ok, %{processed: integer(), persisted: integer(), characters: integer()}}
          | {:error, term()}
  def fetch_and_persist_all_tracked_character_kills(limit \\ 25, page \\ 1, deps \\ @default_deps) do
    deps.logger.debug(
      "[CHARACTER_KILLS] Fetching and persisting kills for all tracked characters"
    )

    tracked_characters = deps.repository.get_tracked_characters()

    if Enum.empty?(tracked_characters) do
      deps.logger.warn("[CHARACTER_KILLS] No tracked characters found")
      {:error, :no_tracked_characters}
    else
      process_tracked_characters(tracked_characters, limit, page, deps)
    end
  end

  defp process_tracked_characters(tracked_characters, limit, page, deps) do
    results =
      tracked_characters
      |> Enum.map(&extract_character_id/1)
      |> Enum.reject(&is_nil/1)
      |> Enum.map(fn character_id ->
        fetch_and_persist_character_kills(character_id, limit, page, deps)
      end)

    case Enum.filter(results, &match?({:ok, _}, &1)) do
      [] ->
        {:error, :no_successful_results}

      successful_results ->
        processed_count =
          Enum.reduce(successful_results, 0, fn
            {:ok, %{processed: count}}, acc -> acc + count
            _, acc -> acc
          end)

        persisted_count =
          Enum.reduce(successful_results, 0, fn
            {:ok, %{persisted: count}}, acc -> acc + count
            _, acc -> acc
          end)

        {:ok,
         %{
           processed: processed_count,
           persisted: persisted_count,
           characters: length(successful_results)
         }}
    end
  end

  @doc """
  Fetches and persists kills for a single character.
  """
  @spec fetch_and_persist_character_kills(integer(), integer(), integer(), map()) ::
          {:ok, %{processed: integer(), persisted: integer()}}
          | {:error, term()}
  def fetch_and_persist_character_kills(
        character_id,
        limit \\ 25,
        page \\ 1,
        deps \\ @default_deps
      ) do
    deps.logger.debug("[CHARACTER_KILLS] Fetching kills for character #{character_id}")

    case fetch_character_kills(character_id, limit, page, deps) do
      {:ok, kills} when is_list(kills) ->
        kill_count = Enum.count(kills)
        deps.logger.debug("[CHARACTER_KILLS] Processing #{kill_count} kills")
        process_kills_batch(kills, deps)

      {:error, reason} ->
        deps.logger.error("[CHARACTER_KILLS] Failed to fetch kills: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp fetch_character_kills(character_id, limit, page, deps) do
    case deps.cache_helpers.get_cached_kills(character_id) do
      {:ok, []} ->
        # No cached data, fetch from ZKill
        deps.zkill_client.get_character_kills(character_id, limit, page)

      {:ok, kills} ->
        # Use cached data
        {:ok, kills}

      {:error, _} ->
        # Cache error, try ZKill
        deps.zkill_client.get_character_kills(character_id, limit, page)
    end
  end

  defp process_kills_batch(kills, deps) do
    results =
      kills
      |> Enum.map(&enrich_killmail(&1, deps))
      |> Enum.map(&maybe_persist_killmail(&1, deps))
      |> Enum.split_with(&match?({:ok, _}, &1))

    {successful, failed} = results
    persisted = length(successful)
    processed = length(kills)

    if persisted > 0 do
      deps.logger.debug("[CHARACTER_KILLS] Successfully persisted #{persisted} kills")
    end

    if length(failed) > 0 do
      deps.logger.warn("[CHARACTER_KILLS] Failed to persist #{length(failed)} kills")
    end

    {:ok, %{processed: processed, persisted: persisted}}
  end

  defp enrich_killmail(kill, deps) do
    with victim_id when is_integer(victim_id) <- get_in(kill, ["victim", "character_id"]),
         ship_id when is_integer(ship_id) <- get_in(kill, ["victim", "ship_type_id"]),
         {:ok, victim} <- deps.esi_service.get_character(victim_id),
         {:ok, ship} <- deps.esi_service.get_type(ship_id) do
      Map.merge(kill, %{
        "victim_name" => victim["name"],
        "ship_name" => ship["name"]
      })
    else
      _ -> kill
    end
  end

  defp maybe_persist_killmail(kill, deps) do
    case deps.persistence.maybe_persist_killmail(kill) do
      {:ok, :persisted} = result ->
        result

      {:ok, :not_persisted} ->
        {:error, :not_persisted}

      other ->
        deps.logger.error("[CHARACTER_KILLS] Failed to persist killmail: #{inspect(other)}")
        {:error, :persistence_failed}
    end
  end

  defp extract_character_id(%{character_id: character_id}) when is_integer(character_id),
    do: character_id

  defp extract_character_id(%{"character_id" => character_id}) when is_integer(character_id),
    do: character_id

  defp extract_character_id(_), do: nil

  defp filter_kills_by_date(kills, from, to) do
    kills
    |> Enum.filter(fn kill ->
      case DateTime.from_iso8601(kill["killmail_time"]) do
        {:ok, kill_time, _} ->
          kill_date = DateTime.to_date(kill_time)
          Date.compare(kill_date, from) != :lt and Date.compare(kill_date, to) != :gt

        _ ->
          false
      end
    end)
  end

  defp transform_kill(kill, deps) do
    with victim_id when is_integer(victim_id) <- get_in(kill, ["victim", "character_id"]),
         ship_id when is_integer(ship_id) <- get_in(kill, ["victim", "ship_type_id"]),
         {:ok, victim} <- deps.esi_service.get_character(victim_id),
         {:ok, ship} <- deps.esi_service.get_type(ship_id) do
      {:ok,
       %{
         id: kill["killmail_id"],
         time: kill["killmail_time"],
         victim_name: victim["name"],
         ship_name: ship["name"]
       }}
    else
      {:error, reason} ->
        deps.logger.error("[CHARACTER_KILLS] Failed to enrich kill: #{inspect(reason)}")
        {:error, :api_error}

      _ ->
        deps.logger.error("[CHARACTER_KILLS] Failed to extract kill data")
        {:error, :invalid_kill_data}
    end
  end
end
