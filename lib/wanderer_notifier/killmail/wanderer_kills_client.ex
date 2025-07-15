defmodule WandererNotifier.Killmail.WandererKillsClient do
  @moduledoc """
  HTTP client for the Wanderer Kills API.

  This client provides access to recent kills data from the Wanderer Kills service,
  replacing the previous ZKillboard integration for system notification features.
  """

  alias WandererNotifier.Logger.Logger, as: AppLogger
  alias WandererNotifier.HTTP
  alias WandererNotifier.Http.ResponseHandler
  alias WandererNotifier.Constants
  require Logger

  @base_url Application.compile_env(
              :wanderer_notifier,
              :wanderer_kills_base_url,
              "http://host.docker.internal:4004"
            )
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
      "#{@base_url}/api/v1/kills/system/#{system_id}?limit=#{limit}&since_hours=#{since_hours}"

    AppLogger.api_debug("WandererKills API request", %{
      method: :get_system_kills,
      url: url,
      system_id: system_id,
      limit: limit,
      since_hours: since_hours
    })

    perform_request(url)
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
      "#{@base_url}/api/v1/kills/character/#{character_id}?limit=#{limit}&since_hours=#{since_hours}"

    AppLogger.api_debug("WandererKills API request", %{
      method: :get_character_kills,
      url: url,
      character_id: character_id,
      limit: limit,
      since_hours: since_hours
    })

    perform_request(url)
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
    url = "#{@base_url}/api/v1/kills/recent?limit=#{limit}&since_hours=#{since_hours}"

    AppLogger.api_debug("WandererKills API request", %{
      method: :get_recent_kills,
      url: url,
      limit: limit,
      since_hours: since_hours
    })

    perform_request(url)
  end

  # Private functions

  defp perform_request(url) do
    # Configure middleware options for retry and rate limiting
    opts = [
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

    make_http_request(url, opts)
  end

  defp make_http_request(url, opts) do
    result = HTTP.get(url, http_headers(), opts)

    case ResponseHandler.handle_response(result,
           success_codes: [200],
           log_context: %{client: "WandererKills", url: url}
         ) do
      {:ok, body} ->
        handle_successful_response(body, url)

      {:error, reason} = error ->
        AppLogger.api_error("WandererKills request failed", %{url: url, error: inspect(reason)})
        error
    end
  end

  defp handle_successful_response(body, url) do
    AppLogger.api_debug("WandererKills response OK", %{url: url, sample: sample(body)})

    case decode_response(body) do
      {:ok, response} -> extract_kills_from_response(response, url)
      {:error, reason} -> {:error, reason}
    end
  end

  defp extract_kills_from_response(%{"kills" => kills}, _url) when is_list(kills),
    do: {:ok, kills}

  defp extract_kills_from_response(kills, _url) when is_list(kills), do: {:ok, kills}

  defp extract_kills_from_response(data, url) do
    AppLogger.api_warn("WandererKills unexpected response format", %{
      url: url,
      data: inspect(data)
    })

    {:ok, []}
  end

  defp http_headers do
    [
      {"Content-Type", "application/json"},
      {"Accept", "application/json"},
      {"User-Agent", "WandererNotifier/1.0"}
    ]
  end

  # Note: HTTP options are now passed directly to the unified client in perform_request

  defp decode_response(body) when is_binary(body) do
    case Jason.decode(body) do
      {:ok, decoded} -> {:ok, decoded}
      {:error, reason} -> {:error, {:json_decode_error, reason}}
    end
  end

  defp decode_response(data), do: {:ok, data}

  defp sample(body) when is_binary(body) do
    String.slice(body, 0, 100)
  end

  defp sample(_), do: nil
end
