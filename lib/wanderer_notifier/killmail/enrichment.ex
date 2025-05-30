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
    Logger.info("Starting enrichment with existing ESI data",
      kill_id: km.killmail_id,
      esi_data_keys: if(is_map(existing), do: Map.keys(existing), else: []),
      esi_data_size: if(is_map(existing), do: map_size(existing), else: 0),
      zkb_data: inspect(km.zkb)
    )

    {:ok, km}
    |> with_ok(&add_victim_info/1)
    |> with_ok(&add_system_info/1)
    |> with_ok(&add_attackers/1)
    |> case do
      {:ok, enriched} ->
        Logger.info("Successfully enriched killmail with existing data",
          kill_id: km.killmail_id,
          victim_name: enriched.victim_name,
          system_name: enriched.system_name,
          attacker_count: length(enriched.attackers)
        )

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
    Logger.info("Starting enrichment with fresh ESI data",
      kill_id: id,
      hash: hash,
      zkb_data: inspect(km.zkb)
    )

    km
    |> maybe_use_cache(%{})
    |> fetch_esi(:get_killmail, [id, hash])
    |> with_ok(&add_victim_info/1)
    |> with_ok(&add_system_info/1)
    |> with_ok(&add_attackers/1)
    |> case do
      {:ok, enriched} ->
        Logger.info("Successfully enriched killmail with fresh data",
          kill_id: id,
          victim_name: enriched.victim_name,
          system_name: enriched.system_name,
          attacker_count: length(enriched.attackers)
        )

        {:ok, enriched}

      {:error, :service_unavailable} = err ->
        Logger.error("Service unavailable during fresh data enrichment",
          kill_id: id,
          error: inspect(err)
        )

        err

      error ->
        Logger.error("Failed to enrich with fresh data",
          kill_id: id,
          error: inspect(error)
        )

        {:error, :esi_data_missing}
    end
  end

  # If esi_data is already present, skip fetching.
  defp maybe_use_cache(killmail, esi) when map_size(esi) > 0, do: {:ok, killmail}
  defp maybe_use_cache(km, _), do: {:ok, km}

  defp fetch_esi({:ok, %Killmail{} = km}, :get_killmail, [id, hash]) do
    Logger.info("Enrichment: Starting ESI fetch for kill_id=#{id} hash=#{hash}")

    # Log the raw response from ESI service
    response = esi_service().get_killmail(id, hash, [])

    Logger.info(
      "Enrichment: Raw ESI service response: #{inspect(response, pretty: true, limit: :infinity)}"
    )

    case response do
      {:ok, nil} ->
        Logger.error("Enrichment: ESI service returned nil data for kill_id=#{id} hash=#{hash}")
        {:error, :esi_data_missing}

      {:ok, data} when is_map(data) ->
        Logger.info(
          "Enrichment: Successfully fetched ESI data for kill_id=#{id} with keys=#{inspect(Map.keys(data))}"
        )

        {:ok, %{km | esi_data: data}}

      {:ok, data} ->
        Logger.error(
          "Enrichment: Invalid ESI data format for kill_id=#{id}: #{inspect(data, pretty: true, limit: :infinity)}"
        )

        {:error, :esi_data_missing}

      {:error, :service_unavailable} ->
        Logger.warning("Enrichment: ESI service unavailable for kill_id=#{id} hash=#{hash}")
        {:error, :service_unavailable}

      {:error, :timeout} ->
        Logger.warning("Enrichment: ESI request timed out for kill_id=#{id} hash=#{hash}")
        {:error, :service_unavailable}

      {:error, reason} ->
        Logger.error(
          "Enrichment: ESI request failed for kill_id=#{id} hash=#{hash} reason=#{inspect(reason)}"
        )

        {:error, :service_unavailable}

      error ->
        Logger.error(
          "Enrichment: Unexpected error from ESI for kill_id=#{id}: #{inspect(error, pretty: true, limit: :infinity)}"
        )

        {:error, :service_unavailable}
    end
  end

  defp fetch_esi({:ok, %Killmail{esi_data: esi} = km}, fun, [key]) do
    Logger.info("Fetching additional ESI data",
      kill_id: km.killmail_id,
      function: fun,
      key: key,
      existing_esi_keys: if(is_map(esi), do: Map.keys(esi), else: [])
    )

    apply(esi_service(), fun, [key, []])
    |> case do
      {:ok, %{"name" => name}} ->
        Logger.info("Successfully fetched name data",
          kill_id: km.killmail_id,
          function: fun,
          name: name,
          key: key
        )

        {:ok, %{km | esi_data: Map.put_new(esi, to_string(fun), name)}}

      {:ok, info} when is_map(info) ->
        Logger.info("Successfully fetched info data",
          kill_id: km.killmail_id,
          function: fun,
          info_keys: Map.keys(info),
          info_size: map_size(info)
        )

        {:ok, %{km | esi_data: Map.put_new(esi, to_string(fun), info)}}

      {:ok, invalid_data} ->
        Logger.error("Invalid data format from ESI",
          kill_id: km.killmail_id,
          function: fun,
          data_type: get_error_type(invalid_data),
          data: inspect(invalid_data)
        )

        {:error, :esi_data_missing}

      {:error, :service_unavailable} ->
        Logger.warning("ESI service unavailable for additional data",
          kill_id: km.killmail_id,
          function: fun,
          key: key
        )

        {:error, :service_unavailable}

      error ->
        Logger.error("Failed to fetch additional ESI data",
          kill_id: km.killmail_id,
          function: fun,
          error: inspect(error),
          error_type: get_error_type(error)
        )

        {:error, :esi_data_missing}
    end
  end

  # --- Enrichment helpers ---

  # Adds victim info fields
  defp add_victim_info({:ok, km}) do
    victim = get_in(km.esi_data, ["victim"])

    Logger.info("Processing victim info",
      kill_id: km.killmail_id,
      victim_present: not is_nil(victim),
      victim_type: if(victim, do: get_error_type(victim), else: nil),
      victim_keys: if(is_map(victim), do: Map.keys(victim), else: []),
      esi_data_keys: if(is_map(km.esi_data), do: Map.keys(km.esi_data), else: [])
    )

    with victim when is_map(victim) <- victim,
         {:ok, victim_info} <- fetch_victim_info(victim) do
      Logger.info("Successfully processed victim info",
        kill_id: km.killmail_id,
        victim_info: inspect(victim_info)
      )

      {:ok, Map.merge(km, victim_info)}
    else
      {:error, reason} ->
        Logger.error("Error fetching victim info",
          kill_id: km.killmail_id,
          reason: inspect(reason),
          reason_type: get_error_type(reason)
        )

        {:error, reason}

      nil ->
        Logger.error("Missing victim data in ESI response",
          kill_id: km.killmail_id,
          esi_data_keys: if(is_map(km.esi_data), do: Map.keys(km.esi_data), else: []),
          esi_data: inspect(km.esi_data)
        )

        {:error, :esi_data_missing}

      invalid ->
        Logger.error("Invalid victim data format",
          kill_id: km.killmail_id,
          victim_type: get_error_type(invalid),
          victim_data: inspect(invalid)
        )

        {:error, :esi_data_missing}
    end
  end

  defp fetch_victim_info(victim) when is_map(victim) do
    Logger.info("Fetching victim details",
      character_id: victim["character_id"],
      corporation_id: victim["corporation_id"],
      alliance_id: victim["alliance_id"],
      ship_type_id: victim["ship_type_id"],
      victim_keys: Map.keys(victim)
    )

    # TODO: Re-enable caching once we fix the issue with error responses being cached
    # Temporarily skip cache for all lookups
    with {:ok, char} <- esi_service().get_character_info(victim["character_id"], cache_name: nil),
         {:ok, corp} <-
           esi_service().get_corporation_info(victim["corporation_id"], cache_name: nil),
         {:ok, ship} <- esi_service().get_type_info(victim["ship_type_id"], cache_name: nil) do
      # Handle alliance separately since it can be nil
      alliance_name =
        case victim["alliance_id"] do
          nil ->
            "Unknown"

          alliance_id ->
            case esi_service().get_alliance_info(alliance_id, cache_name: nil) do
              {:ok, alli} -> alli["name"]
              _ -> "Unknown"
            end
        end

      victim_info = %{
        victim_name: char["name"],
        victim_corporation: corp["name"],
        victim_corp_ticker: corp["ticker"],
        victim_alliance: alliance_name,
        ship_name: ship["name"],
        ship_type_id: victim["ship_type_id"],
        character_id: victim["character_id"]
      }

      Logger.info("Successfully fetched all victim details",
        victim_info: inspect(victim_info)
      )

      {:ok, victim_info}
    else
      error ->
        Logger.error("Failed to fetch victim details",
          error: inspect(error),
          error_type: get_error_type(error),
          victim_data: victim,
          victim_keys: Map.keys(victim)
        )

        error
    end
  end

  defp fetch_victim_info(invalid) do
    Logger.error("Invalid victim data format",
      victim_type: get_error_type(invalid),
      victim_data: inspect(invalid)
    )

    {:error, :esi_data_missing}
  end

  # Adds system name and id
  defp add_system_info({:ok, km}) do
    system_id = km.esi_data["solar_system_id"] || km.system_id

    Logger.info("Processing system info",
      kill_id: km.killmail_id,
      system_id: system_id,
      esi_data_keys: if(is_map(km.esi_data), do: Map.keys(km.esi_data), else: [])
    )

    case get_system(system_id) do
      {:ok, name} ->
        Logger.info("Successfully fetched system info",
          kill_id: km.killmail_id,
          system_id: system_id,
          name: name
        )

        {:ok, %{km | system_name: name, system_id: system_id}}

      {:error, :service_unavailable} = err ->
        Logger.warning("ESI service unavailable for system info",
          kill_id: km.killmail_id,
          system_id: system_id
        )

        err

      error ->
        Logger.error("Failed to fetch system info",
          kill_id: km.killmail_id,
          system_id: system_id,
          error: inspect(error),
          error_type: get_error_type(error)
        )

        {:error, :esi_data_missing}
    end
  end

  # Adds enriched attackers list
  defp add_attackers({:ok, km}) do
    attackers = get_in(km.esi_data, ["attackers"])

    Logger.info("Processing attackers",
      kill_id: km.killmail_id,
      attackers_present: not is_nil(attackers),
      attackers_type: if(attackers, do: get_error_type(attackers), else: nil),
      attacker_count: if(is_list(attackers), do: length(attackers), else: 0),
      esi_data_keys: if(is_map(km.esi_data), do: Map.keys(km.esi_data), else: [])
    )

    case attackers do
      nil ->
        Logger.warning("No attackers found in ESI data",
          kill_id: km.killmail_id,
          esi_data_keys: if(is_map(km.esi_data), do: Map.keys(km.esi_data), else: []),
          esi_data: inspect(km.esi_data)
        )

        {:ok, %{km | attackers: []}}

      attackers when is_list(attackers) ->
        process_attackers(km, attackers)

      invalid ->
        Logger.error("Invalid attackers data format",
          kill_id: km.killmail_id,
          attackers_type: get_error_type(invalid),
          attackers: inspect(invalid)
        )

        {:error, :esi_data_missing}
    end
  end

  defp process_attackers(km, attackers) do
    Logger.info("Processing attacker list",
      kill_id: km.killmail_id,
      count: length(attackers),
      first_attacker: if(length(attackers) > 0, do: inspect(hd(attackers)), else: :none)
    )

    attackers
    |> Enum.reduce_while({:ok, []}, &process_attacker/2)
    |> case do
      {:ok, list} ->
        Logger.info("Successfully processed all attackers",
          kill_id: km.killmail_id,
          count: length(list),
          first_attacker: if(length(list) > 0, do: inspect(hd(list)), else: :none)
        )

        {:ok, %{km | attackers: Enum.reverse(list)}}

      err ->
        Logger.error("Failed to process attackers",
          kill_id: km.killmail_id,
          error: inspect(err),
          error_type: get_error_type(err)
        )

        err
    end
  end

  defp process_attacker(atk, {:ok, acc}) when is_map(atk) do
    Logger.info("Processing attacker",
      character_id: atk["character_id"],
      corporation_id: atk["corporation_id"],
      alliance_id: atk["alliance_id"],
      ship_type_id: atk["ship_type_id"],
      attacker_keys: Map.keys(atk)
    )

    case enrich_attacker(atk) do
      {:ok, e} ->
        Logger.info("Successfully enriched attacker",
          attacker_info: inspect(e)
        )

        {:cont, {:ok, [e | acc]}}

      err ->
        Logger.error("Failed to enrich attacker",
          error: inspect(err),
          error_type: get_error_type(err),
          attacker_data: atk,
          attacker_keys: Map.keys(atk)
        )

        {:halt, err}
    end
  end

  defp process_attacker(invalid, {:ok, _acc}) do
    Logger.error("Invalid attacker data format",
      attacker_type: get_error_type(invalid),
      attacker_data: inspect(invalid)
    )

    {:halt, {:error, :esi_data_missing}}
  end

  # Restore get_system/1
  defp get_system(nil), do: {:ok, "Unknown System"}

  defp get_system(system_id) when is_integer(system_id) or is_binary(system_id) do
    Logger.info("Fetching system info",
      system_id: system_id
    )

    case esi_service().get_system(system_id, []) do
      {:ok, %{"name" => name}} ->
        Logger.info("Successfully fetched system name",
          system_id: system_id,
          name: name
        )

        {:ok, name}

      {:error, :service_unavailable} ->
        Logger.warning("ESI service unavailable for system",
          system_id: system_id
        )

        {:error, :service_unavailable}

      error ->
        Logger.error("Failed to fetch system",
          system_id: system_id,
          error: inspect(error),
          error_type: get_error_type(error)
        )

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
    Logger.info("Fetching ESI data",
      function: fun,
      id: id
    )

    response = apply(esi_service(), fun, [id, [cache_name: nil]])

    Logger.info("Raw ESI response",
      function: fun,
      id: id,
      response: inspect(response, pretty: true, limit: :infinity)
    )

    case response do
      {:ok, info} when is_map(info) ->
        Logger.info("Successfully fetched ESI data",
          function: fun,
          id: id,
          info_keys: Map.keys(info),
          info_size: map_size(info)
        )

        {:ok, info}

      {:ok, invalid_data} ->
        Logger.error("Invalid data format from ESI",
          function: fun,
          id: id,
          data_type: get_error_type(invalid_data),
          data: inspect(invalid_data, pretty: true, limit: :infinity)
        )

        {:error, :esi_data_missing}

      {:error, :service_unavailable} ->
        Logger.warning("ESI service unavailable",
          function: fun,
          id: id
        )

        {:error, :service_unavailable}

      error ->
        Logger.error("Failed to fetch ESI data",
          function: fun,
          id: id,
          error: inspect(error, pretty: true, limit: :infinity),
          error_type: get_error_type(error)
        )

        {:error, :esi_data_missing}
    end
  end

  # Builds each attacker record
  defp enrich_attacker(atk) when is_map(atk) do
    Logger.info("Enriching attacker data",
      attacker_keys: Map.keys(atk)
    )

    # Get character info, defaulting to "Unknown" if lookup fails
    character_name =
      case get_character(atk["character_id"]) do
        {:ok, char} -> char["name"]
        _ -> "Unknown"
      end

    # Get corporation info, defaulting to "Unknown" if lookup fails
    {corp_name, corp_ticker} =
      case get_corporation(atk["corporation_id"]) do
        {:ok, corp} -> {corp["name"], corp["ticker"]}
        _ -> {"Unknown", "???"}
      end

    # Get alliance info, defaulting to "Unknown" if lookup fails
    alliance_name =
      case get_alliance(atk["alliance_id"]) do
        {:ok, alli} -> alli["name"]
        _ -> "Unknown"
      end

    # Get ship info, defaulting to "Unknown" if lookup fails
    ship_name =
      case get_ship(atk["ship_type_id"]) do
        {:ok, ship} -> ship["name"]
        _ -> "Unknown"
      end

    enriched =
      Map.merge(atk, %{
        "character_name" => character_name,
        "corporation_name" => corp_name,
        "corporation_ticker" => corp_ticker,
        "alliance_name" => alliance_name,
        "ship_name" => ship_name
      })

    Logger.info("Successfully enriched attacker",
      enriched_keys: Map.keys(enriched)
    )

    {:ok, enriched}
  end

  defp enrich_attacker(invalid) do
    Logger.error("Invalid attacker data format",
      attacker_type: get_error_type(invalid),
      attacker_data: inspect(invalid)
    )

    {:error, :esi_data_missing}
  end

  # --- Recent kills via ZKillboard ---

  @doc """
  Fetches and formats the latest kills for a system (default 3).
  """
  @spec recent_kills_for_system(integer(), non_neg_integer()) :: String.t()
  def recent_kills_for_system(system_id, limit \\ 3) do
    Logger.info("Fetching recent kills for system=#{system_id} limit=#{limit}")

    try do
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
  end

  # --- Utilities ---

  # Chains {:ok, val} into fun, propagating errors
  defp with_ok({:ok, value}, fun), do: fun.({:ok, value})
  defp with_ok(error, _fun), do: error

  # Helper function to safely get error type
  defp get_error_type(nil), do: nil
  defp get_error_type({:error, reason}) when is_atom(reason), do: reason

  defp get_error_type({:error, reason}) when is_map(reason),
    do: Map.get(reason, :__struct__) || :not_struct

  defp get_error_type(error) when is_map(error), do: Map.get(error, :__struct__) || :not_struct
  defp get_error_type(_), do: :unknown_error
end
