defmodule WandererNotifier.Domains.Killmail.WandererKillsAPI do
  @moduledoc """
  WandererKills API client for bulk operations and killmail management.

  This module provides an enhanced interface to the WandererKills service,
  including bulk loading capabilities and advanced killmail operations.
  """

  require Logger
  alias WandererNotifier.Infrastructure.Http
  alias WandererNotifier.Infrastructure.Http.Utils.HttpUtils
  alias WandererNotifier.Shared.Config

  defp base_url do
    Config.wanderer_kills_url()
  end

  def fetch_system_killmails(system_id, hours \\ 24, limit \\ 50) do
    url = "#{base_url()}/api/v1/systems/#{system_id}/killmails"

    params = %{
      "hours" => hours,
      "limit" => limit
    }

    full_url = HttpUtils.build_url_with_query(url, params)

    Logger.info("Fetching system killmails",
      system_id: system_id,
      hours: hours,
      limit: limit,
      category: :api
    )

    full_url
    |> then(&Http.wanderer_kills_get(&1, default_headers()))
    |> handle_killmails_response()
  end

  def fetch_systems_killmails(system_ids, hours \\ 24, limit_per_system \\ 20)
      when is_list(system_ids) do
    url = "#{base_url()}/api/v1/systems/bulk/killmails"

    body = build_systems_request_body(system_ids, hours, limit_per_system)
    log_systems_request(system_ids, hours, limit_per_system)

    url
    |> Http.wanderer_kills_post(body, default_headers())
    |> handle_systems_response(url, body, system_ids)
  end

  defp build_systems_request_body(system_ids, hours, limit_per_system) do
    %{
      "system_ids" => system_ids,
      "hours" => hours,
      "limit_per_system" => limit_per_system
    }
  end

  defp log_systems_request(system_ids, hours, limit_per_system) do
    Logger.info("Fetching bulk system killmails",
      system_count: length(system_ids),
      hours: hours,
      limit_per_system: limit_per_system,
      category: :api
    )
  end

  defp handle_systems_response(response, url, body, system_ids) do
    case response do
      {:ok, %{status_code: 200, body: data}} when is_map(data) ->
        {:ok, convert_system_ids_to_integers(data)}

      {:ok, %{status_code: status, body: response_body}} ->
        log_systems_http_error(status, response_body, url, body, system_ids)
        {:error, %{type: :http_error, message: "HTTP #{status}: #{inspect(response_body)}"}}

      {:error, reason} ->
        log_systems_network_error(reason, url, system_ids)
        {:error, %{type: :network_error, message: inspect(reason)}}
    end
  end

  defp log_systems_http_error(status, response_body, url, body, system_ids) do
    Logger.error("Bulk killmails API returned error status",
      status: status,
      response_body: inspect(response_body),
      url: url,
      request_body: inspect(body),
      system_count: length(system_ids)
    )
  end

  defp log_systems_network_error(reason, url, system_ids) do
    Logger.error("Bulk killmails API network error",
      error: inspect(reason, pretty: true),
      url: url,
      system_count: length(system_ids)
    )
  end

  def get_killmail(killmail_id) do
    url = "#{base_url()}/api/v1/killmail/#{killmail_id}"

    Logger.debug("Fetching killmail from URL: #{url}", killmail_id: killmail_id, category: :api)

    result = Http.wanderer_kills_get(url, default_headers())
    Logger.debug("HTTP request result: #{inspect(result)}", category: :api)

    handle_killmail_response(result, killmail_id)
  end

  defp handle_killmail_response({:ok, %{status_code: 200, body: response_body}}, _killmail_id)
       when is_map(response_body) do
    Logger.debug("Got 200 response with body keys: #{inspect(Map.keys(response_body))}",
      category: :api
    )

    killmail_data = extract_killmail_data(response_body)
    transformed = transform_kill(killmail_data)
    {:ok, transformed}
  end

  defp handle_killmail_response({:ok, %{status_code: 404} = response}, killmail_id) do
    Logger.debug("Got 404 response: #{inspect(response)}", category: :api)
    {:error, %{type: :not_found, message: "Killmail #{killmail_id} not found"}}
  end

  defp handle_killmail_response(
         {:ok, %{status_code: status, body: body} = response},
         _killmail_id
       ) do
    Logger.debug("Got #{status} response: #{inspect(response)}", category: :api)
    {:error, %{type: :http_error, message: "HTTP #{status}: #{inspect(body)}"}}
  end

  defp handle_killmail_response({:error, reason}, _killmail_id) do
    Logger.error("HTTP request error: #{inspect(reason)}", category: :api)
    {:error, %{type: :network_error, message: inspect(reason)}}
  end

  defp extract_killmail_data(%{"data" => data}) when is_map(data) do
    Logger.debug("Found data wrapped in 'data' field", category: :api)
    data
  end

  defp extract_killmail_data(data) when is_map(data) do
    Logger.debug("Using response body directly", category: :api)
    data
  end

  def subscribe_to_killmails(subscriber_id, system_ids, callback_url \\ nil) do
    url = "#{base_url()}/api/v1/subscriptions"

    body = %{
      "subscriber_id" => subscriber_id,
      "system_ids" => system_ids,
      "callback_url" => callback_url
    }

    Logger.info("Creating killmail subscription",
      subscriber_id: subscriber_id,
      system_count: length(system_ids),
      category: :api
    )

    case Http.wanderer_kills_post(url, body, default_headers()) do
      {:ok, %{status_code: 201, body: %{"subscription_id" => subscription_id}}} ->
        {:ok, subscription_id}

      {:ok, %{status_code: status, body: body}} ->
        {:error, %{type: :http_error, message: "HTTP #{status}: #{inspect(body)}"}}

      {:error, reason} ->
        {:error, %{type: :network_error, message: inspect(reason)}}
    end
  end

  def fetch_character_killmails(character_id, hours \\ 24, limit \\ 50) do
    url = "#{base_url()}/api/v1/characters/#{character_id}/killmails"

    params = %{
      "hours" => hours,
      "limit" => limit
    }

    full_url = HttpUtils.build_url_with_query(url, params)

    Logger.info("Fetching character killmails",
      character_id: character_id,
      hours: hours,
      limit: limit,
      category: :api
    )

    full_url
    |> then(&Http.wanderer_kills_get(&1, default_headers()))
    |> handle_killmails_response()
  end

  def health_check do
    url = "#{base_url()}/api/health"

    Logger.debug("Checking API health", category: :api)

    case Http.wanderer_kills_get(url, default_headers()) do
      {:ok, %{status_code: 200, body: health_data}} when is_map(health_data) ->
        {:ok, health_data}

      {:ok, %{status_code: status, body: body}} ->
        {:error, %{type: :http_error, message: "HTTP #{status}: #{inspect(body)}"}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Bulk loads system kills for the fallback handler.

  This function is called by the fallback handler when WebSocket connection is down.
  """
  def bulk_load_system_kills(system_ids, hours \\ 1) when is_list(system_ids) do
    Logger.info("Starting bulk load for #{length(system_ids)} systems", category: :api)

    # Process in chunks to avoid overwhelming the API
    chunk_size = 10
    chunks = Enum.chunk_every(system_ids, chunk_size)

    results =
      chunks
      |> Enum.with_index()
      |> Enum.map(fn {chunk, index} ->
        Logger.debug("Processing chunk #{index + 1}/#{length(chunks)}", category: :api)
        fetch_systems_killmails(chunk, hours, 20)
      end)

    # Aggregate results
    {loaded_count, errors} = aggregate_bulk_results(results)

    Logger.info("Bulk load completed",
      loaded: loaded_count,
      errors: length(errors),
      total_systems: length(system_ids),
      category: :api
    )

    {:ok, %{loaded: loaded_count, errors: errors}}
  end

  # Transformation functions

  defp transform_kill(killmail) do
    killmail
    |> transform_victim()
    |> transform_attackers()
  end

  defp transform_victim(%{"victim" => victim} = killmail) when is_map(victim) do
    normalized_victim =
      victim
      |> Map.put_new("character_name", nil)
      |> Map.put_new("corporation_name", nil)
      |> Map.put_new("alliance_name", nil)
      |> Map.put_new("ship_name", nil)

    Map.put(killmail, "victim", normalized_victim)
  end

  defp transform_victim(killmail), do: killmail

  defp transform_attackers(%{"attackers" => attackers} = killmail) when is_list(attackers) do
    normalized_attackers =
      Enum.map(attackers, fn attacker ->
        attacker
        |> Map.put_new("character_name", nil)
        |> Map.put_new("corporation_name", nil)
        |> Map.put_new("alliance_name", nil)
        |> Map.put_new("ship_name", nil)
      end)

    Map.put(killmail, "attackers", normalized_attackers)
  end

  defp transform_attackers(killmail), do: killmail

  # Private helper functions

  defp default_headers do
    [
      {"Content-Type", "application/json"},
      {"Accept", "application/json"},
      {"User-Agent", "WandererNotifier/1.0"}
    ]
  end

  defp handle_killmails_response(response) do
    case response do
      {:ok, %{status_code: 200, body: killmails}} when is_list(killmails) ->
        {:ok, killmails}

      {:ok, %{status_code: 200, body: %{"kills" => killmails}}} when is_list(killmails) ->
        # Transform killmails to add enriched flag
        transformed_kills = Enum.map(killmails, &Map.put(&1, "enriched", true))
        {:ok, transformed_kills}

      {:ok, %{status_code: 404}} ->
        {:ok, []}

      {:ok, %{status_code: status, body: body}} ->
        {:error, %{type: :http_error, message: "HTTP #{status}: #{inspect(body)}"}}

      {:error, reason} ->
        {:error, %{type: :network_error, message: inspect(reason)}}
    end
  end

  defp convert_system_ids_to_integers(%{"systems" => systems_data}) when is_map(systems_data) do
    converted_systems =
      systems_data
      |> Enum.map(fn {system_id_str, killmails} ->
        {String.to_integer(system_id_str), killmails}
      end)
      |> Map.new()

    converted_systems
  end

  defp convert_system_ids_to_integers(data) when is_map(data) do
    data
    |> Enum.map(fn {system_id_str, killmails} ->
      {String.to_integer(system_id_str), killmails}
    end)
    |> Map.new()
  end

  defp aggregate_bulk_results(results) do
    loaded_count =
      results
      |> Enum.reduce(0, fn
        {:ok, system_killmails}, acc when is_map(system_killmails) ->
          killmail_count =
            system_killmails
            |> Map.values()
            |> Enum.map(&length/1)
            |> Enum.sum()

          acc + killmail_count

        _, acc ->
          acc
      end)

    errors =
      results
      |> Enum.filter(&match?({:error, _}, &1))
      |> Enum.map(fn {:error, error} -> error end)

    {loaded_count, errors}
  end
end
