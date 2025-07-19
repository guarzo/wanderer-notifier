defmodule WandererNotifier.Domains.Killmail.WandererKillsAPIV2 do
  @moduledoc """
  Enhanced type-safe HTTP client for the WandererKills API.

  This module provides a comprehensive interface to the WandererKills service,
  implementing type-safe patterns and supporting all available endpoints.
  It can be used as a fallback when WebSocket connection is unavailable or
  for bulk data operations.

  This is the refactored version using the unified HTTP client base.
  """

  use WandererNotifier.Infrastructure.Http.ClientBase,
    base_url:
      Application.compile_env(
        :wanderer_notifier,
        :wanderer_kills_base_url,
        "http://host.docker.internal:4004"
      ),
    timeout: 10_000,
    recv_timeout: 10_000,
    service_name: "wanderer_kills"

  alias WandererNotifier.Domains.Killmail.WandererKillsClient
  alias WandererNotifier.Shared.Types.Constants

  @behaviour WandererNotifier.Domains.Killmail.WandererKillsAPI.Behaviour

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

    request(:get, url,
      headers: build_headers(),
      opts: build_request_opts()
    )
    |> handle_response(resource_type: "multi_system_killmails")
    |> case do
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
    url = "#{base_url()}/api/v1/kills/#{killmail_id}"

    request(:get, url,
      headers: build_headers(),
      opts: build_request_opts()
    )
    |> handle_response(resource_type: "killmail")
    |> case do
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
    url = "#{base_url()}/api/v1/subscriptions"

    body =
      Jason.encode!(%{
        subscriber_id: subscriber_id,
        system_ids: system_ids,
        callback_url: callback_url
      })

    request(:post, url,
      body: body,
      headers: build_headers(),
      opts: build_request_opts()
    )
    |> handle_response(resource_type: "subscription", success_codes: [200, 201])
    |> case do
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
    log_api_info("Starting bulk load for #{length(system_ids)} systems", %{
      system_count: length(system_ids),
      hours: hours
    })

    results =
      system_ids
      # Process in chunks to avoid overwhelming the API
      |> Enum.chunk_every(10)
      |> Task.async_stream(
        fn chunk ->
          case fetch_systems_killmails(chunk, hours, 50) do
            {:ok, data} -> {:ok, data}
            {:error, reason} -> {:error, {chunk, reason}}
          end
        end,
        max_concurrency: 5,
        timeout: 30_000
      )
      |> aggregate_stream_results()

    {:ok, results}
  end

  @doc """
  Checks if the WandererKills API is available.
  Useful for health checks and fallback logic.
  """
  @spec health_check() :: {:ok, map()} | {:error, any()}
  def health_check do
    url = "#{base_url()}/api/v1/health"

    request(:get, url,
      headers: build_headers(),
      opts: build_request_opts(timeout: 5_000)
    )
    |> handle_response(resource_type: "health_check")
  end

  # Private functions

  defp build_multi_system_url(system_ids, hours, limit_per_system) do
    params = %{
      system_ids: Enum.join(system_ids, ","),
      since_hours: hours,
      limit_per_system: limit_per_system
    }

    query = URI.encode_query(params)
    "#{base_url()}/api/v1/kills/systems?#{query}"
  end

  defp build_request_opts(extra_opts \\ []) do
    config = %{
      timeout: Keyword.get(extra_opts, :timeout, default_timeout()),
      recv_timeout: Keyword.get(extra_opts, :recv_timeout, default_recv_timeout()),
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
      telemetry_options: [
        service_name: service_name()
      ]
    }

    build_default_opts([], config)
  end

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
    log_api_debug("Unexpected multi-system response format", %{
      response: inspect(response)
    })

    {:ok, %{}}
  end

  defp parse_system_id(system_id) when is_binary(system_id) do
    String.to_integer(system_id)
  end

  defp parse_system_id(system_id) when is_integer(system_id), do: system_id

  defp aggregate_stream_results(stream) do
    stream
    |> Enum.reduce(%{loaded: 0, errors: []}, fn
      {:ok, {:ok, system_data}}, acc ->
        kill_count =
          system_data
          |> Map.values()
          |> Enum.map(&length/1)
          |> Enum.sum()

        %{acc | loaded: acc.loaded + kill_count}

      {:ok, {:error, error}}, acc ->
        %{acc | errors: [error | acc.errors]}

      {:error, reason}, acc ->
        # Handle Task.async_stream timeouts or exits
        %{acc | errors: [{:task_error, reason} | acc.errors]}
    end)
  end

  defp format_error(reason, context) do
    error_type = categorize_error(reason)
    message = format_error_message(reason, context)

    {:error, %{type: error_type, message: message}}
  end

  defp categorize_error(:timeout), do: :timeout
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
