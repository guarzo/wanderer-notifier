defmodule WandererNotifier.Domains.Killmail.WandererKillsAPI do
  @moduledoc """
  WandererKills API client for bulk operations and killmail management.

  This module provides an enhanced interface to the WandererKills service,
  including bulk loading capabilities and advanced killmail operations.
  """

  @behaviour WandererNotifier.Domains.Killmail.WandererKillsAPI.Behaviour

  alias WandererNotifier.Infrastructure.Http
  alias WandererNotifier.Shared.Logger.Logger, as: AppLogger
  alias WandererNotifier.Shared.Config

  @base_url_key :wanderer_kills_url

  defp base_url do
    Config.get(@base_url_key, "http://host.docker.internal:4004")
  end

  @impl true
  def fetch_system_killmails(system_id, hours \\ 24, limit \\ 50) do
    url = "#{base_url()}/api/v1/systems/#{system_id}/killmails"

    params = %{
      "hours" => hours,
      "limit" => limit
    }

    query_string = URI.encode_query(params)
    full_url = "#{url}?#{query_string}"

    AppLogger.api_info("Fetching system killmails",
      system_id: system_id,
      hours: hours,
      limit: limit
    )

    full_url
    |> Http.get(default_headers(), service: :wanderer_kills)
    |> handle_killmails_response()
  end

  @impl true
  def fetch_systems_killmails(system_ids, hours \\ 24, limit_per_system \\ 20)
      when is_list(system_ids) do
    url = "#{base_url()}/api/v1/systems/bulk/killmails"

    body = %{
      "system_ids" => system_ids,
      "hours" => hours,
      "limit_per_system" => limit_per_system
    }

    AppLogger.api_info("Fetching bulk system killmails",
      system_count: length(system_ids),
      hours: hours,
      limit_per_system: limit_per_system
    )

    case Http.post(url, Jason.encode!(body), default_headers(), service: :wanderer_kills) do
      {:ok, %{status_code: 200, body: data}} when is_map(data) ->
        {:ok, convert_system_ids_to_integers(data)}

      {:ok, %{status_code: status, body: body}} ->
        {:error, %{type: :http_error, message: "HTTP #{status}: #{inspect(body)}"}}

      {:error, reason} ->
        {:error, %{type: :network_error, message: inspect(reason)}}
    end
  end

  @impl true
  def get_killmail(killmail_id) do
    url = "#{base_url()}/api/v1/killmails/#{killmail_id}"

    AppLogger.api_debug("Fetching killmail", killmail_id: killmail_id)

    case Http.get(url, default_headers(), service: :wanderer_kills) do
      {:ok, %{status_code: 200, body: killmail}} when is_map(killmail) ->
        transformed = transform_kill(killmail)
        {:ok, Map.put(transformed, "enriched", true)}

      {:ok, %{status_code: 404}} ->
        {:error, %{type: :not_found, message: "Killmail #{killmail_id} not found"}}

      {:ok, %{status_code: status, body: body}} ->
        {:error, %{type: :http_error, message: "HTTP #{status}: #{inspect(body)}"}}

      {:error, reason} ->
        {:error, %{type: :network_error, message: inspect(reason)}}
    end
  end

  @impl true
  def subscribe_to_killmails(subscriber_id, system_ids, callback_url \\ nil) do
    url = "#{base_url()}/api/v1/subscriptions"

    body = %{
      "subscriber_id" => subscriber_id,
      "system_ids" => system_ids,
      "callback_url" => callback_url
    }

    AppLogger.api_info("Creating killmail subscription",
      subscriber_id: subscriber_id,
      system_count: length(system_ids)
    )

    case Http.post(url, Jason.encode!(body), default_headers(), service: :wanderer_kills) do
      {:ok, %{status_code: 201, body: %{"subscription_id" => subscription_id}}} ->
        {:ok, subscription_id}

      {:ok, %{status_code: status, body: body}} ->
        {:error, %{type: :http_error, message: "HTTP #{status}: #{inspect(body)}"}}

      {:error, reason} ->
        {:error, %{type: :network_error, message: inspect(reason)}}
    end
  end

  @impl true
  def fetch_character_killmails(character_id, hours \\ 24, limit \\ 50) do
    url = "#{base_url()}/api/v1/characters/#{character_id}/killmails"

    params = %{
      "hours" => hours,
      "limit" => limit
    }

    query_string = URI.encode_query(params)
    full_url = "#{url}?#{query_string}"

    AppLogger.api_info("Fetching character killmails",
      character_id: character_id,
      hours: hours,
      limit: limit
    )

    full_url
    |> Http.get(default_headers(), service: :wanderer_kills)
    |> handle_killmails_response()
  end

  @impl true
  def health_check do
    url = "#{base_url()}/api/health"

    AppLogger.api_debug("Checking API health")

    case Http.get(url, default_headers(), service: :wanderer_kills) do
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
    AppLogger.info("Starting bulk load for #{length(system_ids)} systems")

    # Process in chunks to avoid overwhelming the API
    chunk_size = 10
    chunks = Enum.chunk_every(system_ids, chunk_size)

    results =
      chunks
      |> Enum.with_index()
      |> Enum.map(fn {chunk, index} ->
        AppLogger.debug("Processing chunk #{index + 1}/#{length(chunks)}")
        fetch_systems_killmails(chunk, hours, 20)
      end)

    # Aggregate results
    {loaded_count, errors} = aggregate_bulk_results(results)

    AppLogger.info("Bulk load completed",
      loaded: loaded_count,
      errors: length(errors),
      total_systems: length(system_ids)
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
