defmodule WandererNotifier.Domains.Killmail.WandererKillsClientV2 do
  @moduledoc """
  HTTP client for the Wanderer Kills API.

  This client provides access to recent kills data from the Wanderer Kills service,
  replacing the previous ZKillboard integration for system notification features.

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
    service_name: "wanderer_kills_client"

  alias WandererNotifier.Shared.Types.Constants
  alias WandererNotifier.Shared.Utils.ErrorHandler

  @max_retries Application.compile_env(:wanderer_notifier, :wanderer_kills_max_retries, 3)

  @doc """
  Fetches recent kills for a specific system.

  ## Parameters
  - system_id: The solar system ID to fetch kills for
  - limit: Maximum number of kills to return (default: 5)
  - since_hours: How many hours back to look for kills (default: 168 = 1 week)

  ## Returns
  - `{:ok, kills}` - List of recent kill data
  - `{:error, reason}` - Error fetching data
  """
  @spec get_system_kills(integer(), non_neg_integer(), non_neg_integer()) ::
          {:ok, [map()]} | {:error, any()}
  def get_system_kills(system_id, limit \\ 5, since_hours \\ 168) do
    url =
      "#{base_url()}/api/v1/kills/system/#{system_id}?limit=#{limit}&since_hours=#{since_hours}"

    log_api_debug("WandererKills API request", %{
      method: :get_system_kills,
      url: url,
      system_id: system_id,
      limit: limit,
      since_hours: since_hours
    })

    ErrorHandler.with_retry(
      fn ->
        request(:get, url,
          headers: build_headers(),
          opts: build_request_opts(),
          log_context: %{client: "WandererKillsClient", url: url}
        )
        |> handle_wanderer_kills_response(url)
      end,
      max_attempts: @max_retries,
      retry_on: [:timeout, :network_error, :service_unavailable],
      base_delay: Constants.wanderer_kills_retry_backoff()
    )
  end

  @doc """
  Fetches recent kills for a specific character.

  ## Parameters
  - character_id: The character ID to fetch kills for
  - limit: Maximum number of kills to return (default: 10)
  - since_hours: How many hours back to look for kills (default: 168 = 1 week)

  ## Returns
  - `{:ok, kills}` - List of recent kill data
  - `{:error, reason}` - Error fetching data
  """
  @spec get_character_kills(integer(), non_neg_integer(), non_neg_integer()) ::
          {:ok, [map()]} | {:error, any()}
  def get_character_kills(character_id, limit \\ 10, since_hours \\ 168) do
    url =
      "#{base_url()}/api/v1/kills/character/#{character_id}?limit=#{limit}&since_hours=#{since_hours}"

    log_api_debug("WandererKills API request", %{
      method: :get_character_kills,
      url: url,
      character_id: character_id,
      limit: limit,
      since_hours: since_hours
    })

    ErrorHandler.with_retry(
      fn ->
        request(:get, url,
          headers: build_headers(),
          opts: build_request_opts(),
          log_context: %{client: "WandererKillsClient", url: url}
        )
        |> handle_wanderer_kills_response(url)
      end,
      max_attempts: @max_retries,
      retry_on: [:timeout, :network_error, :service_unavailable],
      base_delay: Constants.wanderer_kills_retry_backoff()
    )
  end

  @doc """
  Fetches recent kills across all systems.

  ## Parameters
  - limit: Maximum number of kills to return (default: 10)
  - since_hours: How many hours back to look for kills (default: 168 = 1 week)

  ## Returns
  - `{:ok, kills}` - List of recent kill data
  - `{:error, reason}` - Error fetching data
  """
  @spec get_recent_kills(non_neg_integer(), non_neg_integer()) :: {:ok, [map()]} | {:error, any()}
  def get_recent_kills(limit \\ 10, since_hours \\ 168) do
    url = "#{base_url()}/api/v1/kills/recent?limit=#{limit}&since_hours=#{since_hours}"

    log_api_debug("WandererKills API request", %{
      method: :get_recent_kills,
      url: url,
      limit: limit,
      since_hours: since_hours
    })

    ErrorHandler.with_retry(
      fn ->
        request(:get, url,
          headers: build_headers(),
          opts: build_request_opts(),
          log_context: %{client: "WandererKillsClient", url: url}
        )
        |> handle_wanderer_kills_response(url)
      end,
      max_attempts: @max_retries,
      retry_on: [:timeout, :network_error, :service_unavailable],
      base_delay: Constants.wanderer_kills_retry_backoff()
    )
  end

  # Private functions

  defp build_request_opts do
    config = %{
      timeout: default_timeout(),
      recv_timeout: default_recv_timeout(),
      retry_options: [
        max_attempts: @max_retries,
        base_backoff: Constants.wanderer_kills_retry_backoff(),
        retryable_errors: [:timeout, :connect_timeout, :econnrefused],
        retryable_status_codes: [429, 500, 502, 503, 504],
        context: "WandererKills request"
      ],
      rate_limit_options: [
        per_host: true,
        # Conservative rate limits - actual API limits should be confirmed
        # NOTE: These values are conservative estimates; contact Wanderer API team for official limits
        requests_per_second: 10,
        burst_capacity: 20
      ],
      telemetry_options: [
        service_name: service_name()
      ]
    }

    build_default_opts([], config)
  end

  defp handle_wanderer_kills_response(response, url) do
    case handle_response(response,
           success_codes: [200],
           resource_type: "wanderer_kills",
           context: %{url: url}
         ) do
      {:ok, body} ->
        handle_successful_response(body, url)

      {:error, reason} ->
        normalized = ErrorHandler.normalize_error({:error, reason})
        ErrorHandler.log_error("WandererKills request failed", elem(normalized, 1), %{url: url})
        normalized
    end
  end

  defp handle_successful_response(body, url) do
    log_api_debug("WandererKills response OK", %{url: url, sample: sample(body)})

    case decode_json_response(body) do
      {:ok, response} -> extract_kills_from_response(response, url)
      {:error, reason} -> {:error, reason}
    end
  end

  defp extract_kills_from_response(%{"kills" => kills}, _url) when is_list(kills),
    do: {:ok, kills}

  defp extract_kills_from_response(kills, _url) when is_list(kills), do: {:ok, kills}

  defp extract_kills_from_response(data, url) do
    ErrorHandler.log_error(
      "WandererKills unexpected response format",
      :invalid_data,
      %{url: url, data: inspect(data)}
    )

    {:ok, []}
  end

  defp sample(body) when is_binary(body) do
    String.slice(body, 0, 100)
  end

  defp sample(_), do: nil
end
