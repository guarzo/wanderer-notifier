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

  defp esi_service, do: WandererNotifier.Core.Dependencies.esi_service()

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
      {:ok, enriched} ->
        {:ok, enriched}

      {:error, :service_unavailable} = err ->
        Logger.error("Service unavailable during enrichment with existing data",
          kill_id: km.killmail_id,
          error: inspect(err)
        )

        err

      error ->
        Logger.error("Failed to enrich with existing data",
          kill_id: km.killmail_id,
          error: inspect(error)
        )

        {:error, :esi_data_missing}
    end
  end

  def enrich_killmail_data(%Killmail{killmail_id: id, zkb: %{"hash" => hash}} = km) do
    km
    |> maybe_use_cache(%{})
    |> fetch_esi(:get_killmail, [id, hash])
    |> with_ok(&add_victim_info/1)
    |> with_ok(&add_system_info/1)
    |> with_ok(&add_attackers/1)
    |> handle_enrichment_result(id)
  end

  # If esi_data is already present, skip fetching.
  defp maybe_use_cache(km, _), do: {:ok, km}

  defp fetch_esi({:ok, %Killmail{} = km}, :get_killmail, [id, hash]) do
    response = esi_service().get_killmail(id, hash, [])

    case response do
      {:ok, nil} ->
        {:error, :esi_data_missing}

      {:ok, data} when is_map(data) ->
        {:ok, %{km | esi_data: data}}

      {:ok, _data} ->
        {:error, :esi_data_missing}

      {:error, :service_unavailable} ->
        {:error, :service_unavailable}

      {:error, :timeout} ->
        {:error, :service_unavailable}

      {:error, _reason} ->
        {:error, :service_unavailable}

      _error ->
        {:error, :service_unavailable}
    end
  end

  defp fetch_esi({:ok, %Killmail{esi_data: esi} = km}, fun, [key]) do
    apply(esi_service(), fun, [key, []])
    |> case do
      {:ok, %{"name" => name}} ->
        {:ok, %{km | esi_data: Map.put_new(esi, to_string(fun), name)}}

      {:ok, info} when is_map(info) ->
        {:ok, %{km | esi_data: Map.put_new(esi, to_string(fun), info)}}

      {:ok, _invalid_data} ->
        {:error, :esi_data_missing}

      {:error, :service_unavailable} ->
        {:error, :service_unavailable}

      _error ->
        {:error, :esi_data_missing}
    end
  end

  # --- Enrichment helpers ---

  # Adds victim info fields
  defp add_victim_info({:ok, km}) do
    victim = get_in(km.esi_data, ["victim"])

    with victim when is_map(victim) <- victim,
         {:ok, victim_info} <- fetch_victim_info(victim) do
      {:ok, Map.merge(km, victim_info)}
    else
      {:error, reason} ->
        {:error, reason}

      nil ->
        {:error, :esi_data_missing}

      _invalid ->
        {:error, :esi_data_missing}
    end
  end

  defp fetch_victim_info(victim) when is_map(victim) do
    with {:ok, char} <- esi_service().get_character_info(victim["character_id"], cache_name: nil),
         {:ok, corp} <-
           esi_service().get_corporation_info(victim["corporation_id"], cache_name: nil),
         {:ok, ship} <- esi_service().get_type_info(victim["ship_type_id"], cache_name: nil) do
      alliance_name = fetch_alliance_name(victim["alliance_id"])
      victim_info = build_victim_info(char, corp, alliance_name, ship, victim)

      {:ok, victim_info}
    else
      error ->
        error
    end
  end

  defp fetch_alliance_name(nil), do: "Unknown"

  defp fetch_alliance_name(alliance_id) do
    case get_alliance(alliance_id) do
      {:ok, alli} -> alli["name"]
      _ -> "Unknown"
    end
  end

  defp build_victim_info(char, corp, alliance_name, ship, victim) do
    %{
      victim_name: char["name"],
      victim_corporation: corp["name"],
      victim_corp_ticker: corp["ticker"],
      victim_alliance: alliance_name,
      ship_name: ship["name"],
      ship_type_id: victim["ship_type_id"],
      character_id: victim["character_id"]
    }
  end

  # Adds system name and id
  defp add_system_info({:ok, km}) do
    system_id = km.esi_data["solar_system_id"] || km.system_id

    case get_system_name_from_killmail(km, system_id) do
      {:ok, updated_km} -> {:ok, updated_km}
      {:needs_fetch} -> fetch_system_name(km, system_id)
    end
  end

  defp get_system_name_from_killmail(km, system_id) do
    cond do
      km.system_name && km.system_name != "" ->
        {:ok, %{km | system_id: system_id}}

      is_binary(km.esi_data["solar_system_name"]) ->
        {:ok, %{km | system_name: km.esi_data["solar_system_name"], system_id: system_id}}

      true ->
        {:needs_fetch}
    end
  end

  defp fetch_system_name(km, system_id) do
    case get_system(system_id) do
      {:ok, name} ->
        {:ok, %{km | system_name: name, system_id: system_id}}

      {:error, :service_unavailable} = err ->
        err

      _error ->
        {:error, :esi_data_missing}
    end
  end

  # Adds enriched attackers list
  defp add_attackers({:ok, km}) do
    attackers = get_in(km.esi_data, ["attackers"])

    case attackers do
      nil ->
        {:ok, %{km | attackers: []}}

      attackers when is_list(attackers) ->
        process_attackers(km, attackers)

      _invalid ->
        {:error, :esi_data_missing}
    end
  end

  defp process_attackers(km, attackers) do
    attackers
    |> Enum.reduce_while({:ok, []}, &process_attacker/2)
    |> case do
      {:ok, list} ->
        {:ok, %{km | attackers: Enum.reverse(list)}}

      err ->
        err
    end
  end

  defp process_attacker(atk, {:ok, acc}) when is_map(atk) do
    case enrich_attacker(atk) do
      {:ok, e} ->
        {:cont, {:ok, [e | acc]}}
    end
  end

  # Restore get_system/1
  defp get_system(nil), do: {:ok, "Unknown System"}

  defp get_system(system_id) when is_integer(system_id) or is_binary(system_id) do
    case esi_service().get_system(system_id, []) do
      {:ok, %{"name" => name}} ->
        {:ok, name}

      {:error, :service_unavailable} ->
        {:error, :service_unavailable}

      _error ->
        {:error, :esi_data_missing}
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
  defp get_ship(id), do: simple_fetch(:get_type_info, id)

  # Pulls a single record via ESI and uniformly maps errors
  defp simple_fetch(fun, id) do
    response = apply(esi_service(), fun, [id, [cache_name: nil]])

    case response do
      {:ok, info} when is_map(info) ->
        {:ok, info}

      {:ok, _invalid_data} ->
        {:error, :esi_data_missing}

      {:error, :service_unavailable} ->
        {:error, :service_unavailable}

      _error ->
        {:error, :esi_data_missing}
    end
  end

  # Builds each attacker record
  defp enrich_attacker(atk) when is_map(atk) do
    # Fetch all entity information
    character_name = fetch_character_name(atk["character_id"])
    {corp_name, corp_ticker} = fetch_corporation_info(atk["corporation_id"])
    alliance_name = fetch_alliance_name(atk["alliance_id"])
    ship_name = fetch_ship_name(atk["ship_type_id"])

    # Build enriched attacker
    enriched =
      build_enriched_attacker(
        atk,
        character_name,
        corp_name,
        corp_ticker,
        alliance_name,
        ship_name
      )

    {:ok, enriched}
  end

  # Fetch character name with fallback
  defp fetch_character_name(character_id) do
    case get_character(character_id) do
      {:ok, char} -> char["name"]
      _ -> "Unknown"
    end
  end

  # Fetch corporation info with fallback
  defp fetch_corporation_info(corporation_id) do
    case get_corporation(corporation_id) do
      {:ok, corp} -> {corp["name"], corp["ticker"]}
      _ -> {"Unknown", "???"}
    end
  end

  # Fetch ship name with fallback
  defp fetch_ship_name(ship_type_id) do
    case get_ship(ship_type_id) do
      {:ok, ship} -> ship["name"]
      _ -> "Unknown"
    end
  end

  # Build the final enriched attacker map
  defp build_enriched_attacker(
         atk,
         character_name,
         corp_name,
         corp_ticker,
         alliance_name,
         ship_name
       ) do
    Map.merge(atk, %{
      "character_name" => character_name,
      "corporation_name" => corp_name,
      "corporation_ticker" => corp_ticker,
      "alliance_name" => alliance_name,
      "ship_name" => ship_name
    })
  end

  # --- Recent kills via ZKillboard ---

  @doc """
  Fetches and formats the latest kills for a system (default 3).
  """
  @spec recent_kills_for_system(integer(), non_neg_integer()) :: String.t()
  def recent_kills_for_system(system_id, limit \\ 3) do
    try do
      @zkill_client.get_system_kills(system_id, limit)
      |> case do
        {:ok, strs} when is_list(strs) and length(strs) > 0 ->
          Enum.join(strs, "\n")

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

  # --- Utilities ---

  # Chains {:ok, val} into fun, propagating errors
  defp with_ok({:ok, value}, fun), do: fun.({:ok, value})
  defp with_ok(error, _fun), do: error

  # Handle the final result of the enrichment pipeline
  defp handle_enrichment_result({:ok, enriched}, _id), do: {:ok, enriched}

  defp handle_enrichment_result({:error, :service_unavailable} = err, id) do
    Logger.error("Service unavailable during fresh data enrichment",
      kill_id: id,
      error: inspect(err)
    )

    err
  end

  defp handle_enrichment_result(error, id) do
    Logger.error("Failed to enrich with fresh data",
      kill_id: id,
      error: inspect(error)
    )

    {:error, :esi_data_missing}
  end
end
