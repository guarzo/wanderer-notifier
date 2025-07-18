defmodule WandererNotifier.Killmail.WandererKillsAPI do
  @moduledoc """
  Enhanced type-safe HTTP client for the WandererKills API.

  This module provides a comprehensive interface to the WandererKills service,
  implementing type-safe patterns and supporting all available endpoints.
  It can be used as a fallback when WebSocket connection is unavailable or
  for bulk data operations.
  """

  alias WandererNotifier.Killmail.WandererKillsClient
  alias WandererNotifier.Logger.Logger, as: AppLogger
  alias WandererNotifier.HTTP
  alias WandererNotifier.Http.ResponseHandler
  alias WandererNotifier.Constants

  @behaviour WandererNotifier.Killmail.WandererKillsAPI.Behaviour

  @base_url Application.compile_env(
              :wanderer_notifier,
              :wanderer_kills_base_url,
              "http://host.docker.internal:4004"
            )
  @max_retries Application.compile_env(:wanderer_notifier, :wanderer_kills_max_retries, 3)

  # Type definitions for better type safety
  @type killmail_id :: integer()
  @type system_id :: integer()
  @type character_id :: integer()
  @type error_response :: {:error, %{type: atom(), message: String.t()}}
  @type killmail :: map()

  @doc """
  Fetches killmails for a single system with enhanced error handling.
  """
  @impl true
  @spec fetch_system_killmails(system_id(), integer(), integer()) ::
          {:ok, [killmail()]} | error_response()
  def fetch_system_killmails(system_id, hours \\ 24, limit \\ 100) do
    case WandererKillsClient.get_system_kills(system_id, limit, hours) do
      {:ok, kills} -> {:ok, transform_kills(kills)}
      {:error, reason} -> format_error(reason, :fetch_system_killmails)
    end
  end

  @doc """
  Fetches killmails for multiple systems in a single request.
  Returns a map of system_id => [killmails].
  """
  @impl true
  @spec fetch_systems_killmails([system_id()], integer(), integer()) ::
          {:ok, %{system_id() => [killmail()]}} | error_response()
  def fetch_systems_killmails(system_ids, hours \\ 24, limit_per_system \\ 50) do
    url = build_multi_system_url(system_ids, hours, limit_per_system)

    case perform_request(url) do
      {:ok, response} -> parse_multi_system_response(response)
      {:error, reason} -> format_error(reason, :fetch_systems_killmails)
    end
  end

  @doc """
  Fetches a specific killmail by ID.
  """
  @impl true
  @spec get_killmail(killmail_id()) :: {:ok, killmail()} | error_response()
  def get_killmail(killmail_id) do
    url = "#{@base_url}/api/v1/kills/#{killmail_id}"

    case perform_request(url) do
      {:ok, kill} -> {:ok, transform_kill(kill)}
      {:error, reason} -> format_error(reason, :get_killmail)
    end
  end

  @doc """
  Subscribes to real-time killmail updates for specified systems.
  This is primarily for HTTP webhook subscriptions, not WebSocket.
  """
  @impl true
  @spec subscribe_to_killmails(String.t(), [system_id()], String.t() | nil) ::
          {:ok, String.t()} | error_response()
  def subscribe_to_killmails(subscriber_id, system_ids, callback_url \\ nil) do
    url = "#{@base_url}/api/v1/subscriptions"

    body = %{
      subscriber_id: subscriber_id,
      system_ids: system_ids,
      callback_url: callback_url
    }

    case perform_post_request(url, body) do
      {:ok, %{"subscription_id" => sub_id}} -> {:ok, sub_id}
      {:error, reason} -> format_error(reason, :subscribe_to_killmails)
    end
  end

  @doc """
  Fetches killmails for a specific character.
  """
  @impl true
  @spec fetch_character_killmails(character_id(), integer(), integer()) ::
          {:ok, [killmail()]} | error_response()
  def fetch_character_killmails(character_id, hours \\ 24, limit \\ 100) do
    case WandererKillsClient.get_character_kills(character_id, limit, hours) do
      {:ok, kills} -> {:ok, transform_kills(kills)}
      {:error, reason} -> format_error(reason, :fetch_character_killmails)
    end
  end

  @doc """
  Bulk loads killmails for initial system setup or recovery scenarios.
  Useful when WebSocket connection is down or for historical data.
  """
  @spec bulk_load_system_kills([system_id()], integer()) ::
          {:ok, %{loaded: integer(), errors: [any()]}} | error_response()
  def bulk_load_system_kills(system_ids, hours \\ 24) do
    AppLogger.info("Starting bulk load for #{length(system_ids)} systems")

    results =
      system_ids
      # Process in chunks to avoid overwhelming the API
      |> Enum.chunk_every(10)
      |> Enum.map(&fetch_chunk(&1, hours))
      |> aggregate_bulk_results()

    {:ok, results}
  end

  @doc """
  Checks if the WandererKills API is available.
  Useful for health checks and fallback logic.
  """
  @spec health_check() :: {:ok, map()} | {:error, any()}
  def health_check do
    url = "#{@base_url}/api/v1/health"

    case perform_request(url, timeout: 5_000) do
      {:ok, response} -> {:ok, response}
      {:error, _} = error -> error
    end
  end

  # Private functions

  defp build_multi_system_url(system_ids, hours, limit_per_system) do
    params = %{
      system_ids: Enum.join(system_ids, ","),
      since_hours: hours,
      limit_per_system: limit_per_system
    }

    query = URI.encode_query(params)
    "#{@base_url}/api/v1/kills/systems?#{query}"
  end

  defp perform_request(url, extra_opts \\ []) do
    opts =
      [
        retry_options: [
          max_attempts: @max_retries,
          base_backoff: Constants.wanderer_kills_retry_backoff(),
          retryable_errors: [:timeout, :connect_timeout, :econnrefused],
          retryable_status_codes: [429, 500, 502, 503, 504],
          context: "WandererKills request"
        ],
        rate_limit_options: [
          per_host: true,
          requests_per_second: 10,
          burst_capacity: 20
        ],
        timeout: 10_000,
        recv_timeout: 10_000
      ]
      |> Keyword.merge(extra_opts)

    result = HTTP.get(url, http_headers(), opts)

    case ResponseHandler.handle_response(result,
           success_codes: [200],
           log_context: %{client: "WandererKillsAPI", url: url}
         ) do
      {:ok, body} -> decode_response(body)
      {:error, _} = error -> error
    end
  end

  defp perform_post_request(url, body) do
    json_body = Jason.encode!(body)

    opts = [
      retry_options: [
        max_attempts: @max_retries,
        base_backoff: Constants.wanderer_kills_retry_backoff()
      ],
      timeout: 10_000
    ]

    result = HTTP.post(url, json_body, http_headers(), opts)

    case ResponseHandler.handle_response(result,
           success_codes: [200, 201],
           log_context: %{client: "WandererKillsAPI", url: url}
         ) do
      {:ok, body} -> decode_response(body)
      {:error, _} = error -> error
    end
  end

  defp http_headers do
    [
      {"Content-Type", "application/json"},
      {"Accept", "application/json"},
      {"User-Agent", "WandererNotifier/1.0"}
    ]
  end

  defp decode_response(body) when is_binary(body) do
    case Jason.decode(body) do
      {:ok, decoded} -> {:ok, decoded}
      {:error, reason} -> {:error, {:json_decode_error, reason}}
    end
  end

  defp decode_response(data), do: {:ok, data}

  defp transform_kills(kills) when is_list(kills) do
    Enum.map(kills, &transform_kill/1)
  end

  defp transform_kill(kill) do
    # Ensure consistent structure matching WebSocket format
    kill
    |> Map.put("enriched", true)
    |> ensure_victim_structure()
    |> ensure_attackers_structure()
  end

  defp ensure_victim_structure(kill) do
    case Map.get(kill, "victim") do
      nil -> Map.put(kill, "victim", %{})
      victim -> Map.put(kill, "victim", normalize_participant(victim))
    end
  end

  defp ensure_attackers_structure(kill) do
    case Map.get(kill, "attackers") do
      nil ->
        Map.put(kill, "attackers", [])

      attackers when is_list(attackers) ->
        Map.put(kill, "attackers", Enum.map(attackers, &normalize_participant/1))

      _ ->
        Map.put(kill, "attackers", [])
    end
  end

  defp normalize_participant(participant) do
    participant
    |> Map.put_new("character_name", nil)
    |> Map.put_new("corporation_name", nil)
    |> Map.put_new("alliance_name", nil)
    |> Map.put_new("ship_name", nil)
  end

  defp parse_multi_system_response(%{"systems" => systems}) when is_map(systems) do
    result =
      systems
      |> Enum.map(fn {system_id, kills} ->
        {parse_system_id(system_id), transform_kills(kills)}
      end)
      |> Map.new()

    {:ok, result}
  end

  defp parse_multi_system_response(response) do
    AppLogger.warn("Unexpected multi-system response format", response: inspect(response))
    {:ok, %{}}
  end

  defp parse_system_id(system_id) when is_binary(system_id) do
    String.to_integer(system_id)
  end

  defp parse_system_id(system_id) when is_integer(system_id), do: system_id

  defp fetch_chunk(system_ids, hours) do
    Task.async(fn ->
      case fetch_systems_killmails(system_ids, hours, 50) do
        {:ok, data} -> {:ok, data}
        {:error, reason} -> {:error, {system_ids, reason}}
      end
    end)
  end

  defp aggregate_bulk_results(tasks) do
    results = Task.await_many(tasks, 30_000)

    Enum.reduce(results, %{loaded: 0, errors: []}, fn
      {:ok, system_data}, acc ->
        kill_count =
          system_data
          |> Map.values()
          |> Enum.map(&length/1)
          |> Enum.sum()

        %{acc | loaded: acc.loaded + kill_count}

      {:error, error}, acc ->
        %{acc | errors: [error | acc.errors]}
    end)
  end

  defp format_error(reason, context) do
    error_type = categorize_error(reason)
    message = format_error_message(reason, context)

    {:error, %{type: error_type, message: message}}
  end

  defp categorize_error({:timeout, _}), do: :timeout
  defp categorize_error({:connect_timeout, _}), do: :timeout
  defp categorize_error({:json_decode_error, _}), do: :invalid_response
  defp categorize_error({:http_error, 404}), do: :not_found
  defp categorize_error({:http_error, 429}), do: :rate_limit
  defp categorize_error({:http_error, code}) when code >= 500, do: :server_error
  defp categorize_error({:http_error, code}) when code >= 400, do: :client_error
  defp categorize_error(_), do: :unknown

  defp format_error_message(reason, context) do
    "#{context} failed: #{inspect(reason)}"
  end
end
