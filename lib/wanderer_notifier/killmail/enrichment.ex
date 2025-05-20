defmodule WandererNotifier.Killmail.Enrichment do
  @moduledoc """
  Handles enrichment of killmail data with additional information from ESI
  and fetching recent kills via ZKillboard.
  """

  alias WandererNotifier.Killmail.Killmail
  require Logger

  @zkill_client Application.compile_env(
                  :wanderer_notifier,
                  :zkill_client,
                  WandererNotifier.Killmail.ZKillClient
                )

  defp esi_service do
    Application.get_env(:wanderer_notifier, :esi_service, WandererNotifier.ESI.Service)
  end

  @doc """
  Enriches a `%Killmail{}` with ESI lookups.
  """
  @spec enrich_killmail_data(Killmail.t()) ::
          {:ok, Killmail.t()} | {:error, :service_unavailable | :esi_data_missing}
  def enrich_killmail_data(%Killmail{esi_data: existing} = km)
      when is_map(existing) and map_size(existing) > 0 do
    {:ok, km}
    |> with_ok(&add_victim_info/1)
    |> with_ok(&add_system_info/1)
    |> with_ok(&add_attackers/1)
    |> case do
      {:ok, enriched} -> {:ok, enriched}
      {:error, :service_unavailable} = err -> err
      _ -> {:error, :esi_data_missing}
    end
  end

  def enrich_killmail_data(%Killmail{killmail_id: id, zkb: %{"hash" => hash}} = km) do
    km
    |> maybe_use_cache(%{})
    |> fetch_esi(:get_killmail, [id, hash])
    |> with_ok(&add_victim_info/1)
    |> with_ok(&add_system_info/1)
    |> with_ok(&add_attackers/1)
    |> case do
      {:ok, enriched} -> {:ok, enriched}
      {:error, :service_unavailable} = err -> err
      _ -> {:error, :esi_data_missing}
    end
  end

  # If esi_data is already present, skip fetching.
  defp maybe_use_cache(killmail, esi) when map_size(esi) > 0, do: {:ok, killmail}
  defp maybe_use_cache(km, _), do: {:ok, km}

  defp fetch_esi({:ok, %Killmail{} = km}, :get_killmail, [id, hash]) do
    case esi_service().get_killmail(id, hash, []) do
      {:ok, data} -> {:ok, %{km | esi_data: data}}
      {:error, :service_unavailable} -> {:error, :service_unavailable}
      _ -> {:error, :esi_data_missing}
    end
  end

  defp fetch_esi({:ok, %Killmail{esi_data: esi} = km}, fun, [key]) do
    apply(esi_service(), fun, [key, []])
    |> case do
      {:ok, %{"name" => name}} ->
        {:ok, %{km | esi_data: Map.put_new(esi, to_string(fun), name)}}

      {:ok, info} ->
        {:ok, %{km | esi_data: Map.put_new(esi, to_string(fun), info)}}

      {:error, :service_unavailable} ->
        {:error, :service_unavailable}

      _ ->
        {:error, :esi_data_missing}
    end
  end

  # --- Enrichment helpers ---

  # Adds victim info fields
  defp add_victim_info({:ok, km}) do
    with %{"victim" => victim} = _esi <- km.esi_data,
         {:ok, victim_info} <- fetch_victim_info(victim) do
      {:ok, Map.merge(km, victim_info)}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  defp fetch_victim_info(victim) do
    with {:ok, char} <- get_character(victim["character_id"]),
         {:ok, corp} <- get_corporation(victim["corporation_id"]),
         {:ok, alli} <- get_alliance(victim["alliance_id"]),
         {:ok, ship} <- get_ship(victim["ship_type_id"]) do
      {:ok,
       %{
         victim_name: char["name"],
         victim_corporation: corp["name"],
         victim_corp_ticker: corp["ticker"],
         victim_alliance: alli["name"],
         ship_name: ship["name"]
       }}
    end
  end

  # Adds system name and id
  defp add_system_info({:ok, km}) do
    case get_system(km.esi_data["solar_system_id"]) do
      {:ok, name} ->
        {:ok, %{km | system_name: name, system_id: km.esi_data["solar_system_id"]}}

      {:error, :service_unavailable} = err ->
        err

      _ ->
        {:error, :esi_data_missing}
    end
  end

  # Adds enriched attackers list
  defp add_attackers({:ok, km}) do
    case km.esi_data["attackers"] do
      nil -> {:ok, %{km | attackers: []}}
      attackers when is_list(attackers) -> process_attackers(km, attackers)
    end
  end

  defp process_attackers(km, attackers) do
    attackers
    |> Enum.reduce_while({:ok, []}, &process_attacker/2)
    |> case do
      {:ok, list} -> {:ok, %{km | attackers: Enum.reverse(list)}}
      err -> err
    end
  end

  defp process_attacker(atk, {:ok, acc}) do
    case enrich_attacker(atk) do
      {:ok, e} -> {:cont, {:ok, [e | acc]}}
      err -> {:halt, err}
    end
  end

  # Restore get_system/1
  defp get_system(nil), do: {:ok, "Unknown System"}

  defp get_system(system_id) when is_integer(system_id) or is_binary(system_id) do
    case esi_service().get_system(system_id, []) do
      {:ok, %{"name" => name}} -> {:ok, name}
      {:error, :service_unavailable} -> {:error, :service_unavailable}
      _ -> {:error, :esi_data_missing}
    end
  end

  # Individual ESI lookups
  defp get_character(nil), do: {:error, :esi_data_missing}
  defp get_character(id), do: simple_fetch(:get_character_info, id)

  defp get_corporation(nil), do: {:error, :esi_data_missing}
  defp get_corporation(id), do: simple_fetch(:get_corporation_info, id)

  defp get_alliance(nil), do: {:ok, %{"name" => "Unknown"}}
  defp get_alliance(id), do: simple_fetch(:get_alliance_info, id)

  defp get_ship(nil), do: {:error, :esi_data_missing}
  defp get_ship(id), do: simple_fetch(:get_universe_type, id)

  # Pulls a single record via ESI and uniformly maps errors
  defp simple_fetch(fun, id) do
    apply(esi_service(), fun, [id, []])
    |> case do
      {:ok, info} -> {:ok, info}
      {:error, :service_unavailable} -> {:error, :service_unavailable}
      _ -> {:error, :esi_data_missing}
    end
  end

  # Builds each attacker record
  defp enrich_attacker(atk) do
    with {:ok, attacker_info} <- fetch_attacker_info(atk) do
      {:ok, Map.merge(atk, attacker_info)}
    end
  end

  defp fetch_attacker_info(atk) do
    with {:ok, char} <- get_character(atk["character_id"]),
         {:ok, corp} <- get_corporation(atk["corporation_id"]),
         {:ok, alli} <- get_alliance(atk["alliance_id"]),
         {:ok, ship} <- get_ship(atk["ship_type_id"]) do
      {:ok,
       %{
         "character_name" => char["name"],
         "corporation_name" => corp["name"],
         "corporation_ticker" => corp["ticker"],
         "alliance_name" => alli["name"],
         "ship_name" => ship["name"]
       }}
    end
  end

  # --- Recent kills via ZKillboard ---

  @doc """
  Fetches and formats the latest kills for a system (default 3).
  """
  @spec recent_kills_for_system(integer(), non_neg_integer()) :: String.t()
  def recent_kills_for_system(system_id, limit \\ 3) do
    Logger.info("Fetching recent kills for system=#{system_id} limit=#{limit}")

    @zkill_client.get_system_kills(system_id, limit)
    |> case do
      {:ok, strs} when is_list(strs) and length(strs) > 0 ->
        Logger.info("Found #{length(strs)} kills", system_id: system_id)
        Enum.join(strs, "\n")

      {:ok, []} ->
        Logger.info("No kills found", system_id: system_id)
        "No recent kills found"

      {:error, reason} ->
        Logger.warning("Error getting kills", system_id: system_id, reason: inspect(reason))
        "Error retrieving kill data"

      resp ->
        Logger.warning("Unexpected ZKill response", system_id: system_id, resp: inspect(resp))
        "Unexpected kill data response"
    end
  rescue
    e ->
      Logger.error("Exception in recent_kills_for_system",
        system_id: system_id,
        error: Exception.format(:error, e, __STACKTRACE__)
      )

      "Error retrieving kill data"
  end

  # --- Utilities ---

  # Chains {:ok, val} into fun, propagating errors
  defp with_ok({:ok, val}, fun), do: fun.({:ok, val})
  defp with_ok({:error, _} = err, _fun), do: err
end
