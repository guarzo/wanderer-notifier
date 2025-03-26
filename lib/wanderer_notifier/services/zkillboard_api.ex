defmodule WandererNotifier.Services.ZKillboardApi do
  @moduledoc """
  Service for interacting with the zKillboard API.
  """

  require Logger
  alias WandererNotifier.Logger, as: AppLogger

  @base_url "https://zkillboard.com/api"

  # Rate limiting configuration
  # Max 1 request per second (conservative)
  @requests_per_second 1
  # 2 second initial backoff
  @backoff_base_ms 2000
  # 30 seconds maximum backoff
  @max_backoff_ms 30_000

  @doc """
  Gets kills for a specific character.
  Since startTime/endTime are no longer supported by the API, this gets all recent kills.
  Date filtering should be done in memory after fetching the kills.

  ## Parameters
    - character_id: The character ID to get kills for

  ## Returns
    {:ok, kills} | {:error, reason}
  """
  def get_character_kills(character_id) do
    url = "#{@base_url}/characterID/#{character_id}/"
    make_request_with_rate_limiting(url)
  end

  @doc """
  Gets details for a specific killmail.

  ## Parameters
    - kill_id: The killmail ID to fetch

  ## Returns
    {:ok, kill_data} | {:error, reason}
  """
  def get_killmail(kill_id) do
    url = "#{@base_url}/killID/#{kill_id}/"
    make_request_with_rate_limiting(url)
  end

  # Private functions

  # Make a request with basic rate limiting
  defp make_request_with_rate_limiting(url) do
    # Basic rate limiting - sleep between requests
    Process.sleep(div(1000, @requests_per_second))

    case HTTPoison.get(url, get_headers()) do
      {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
        case Jason.decode(body) do
          {:ok, data} when is_list(data) ->
            {:ok, data}

          {:ok, %{"error" => error}} ->
            AppLogger.api_error("zKillboard API returned error", %{error: error})
            {:error, error}

          {:ok, data} when is_map(data) ->
            # Normalize to list for consistency
            {:ok, [data]}

          error ->
            handle_json_error(error)
        end

      {:ok, %HTTPoison.Response{status_code: 429}} ->
        # Handle rate limiting with backoff
        backoff_ms = calculate_backoff()

        AppLogger.api_warn("zKillboard API rate limit exceeded, backing off", %{
          backoff_ms: backoff_ms
        })

        # Sleep for the backoff period
        Process.sleep(backoff_ms)

        # Retry request after backoff
        make_request_with_rate_limiting(url)

      {:ok, %HTTPoison.Response{status_code: code}} ->
        AppLogger.api_error("zKillboard API error", %{status_code: code})
        {:error, "HTTP #{code}"}

      {:error, %HTTPoison.Error{reason: reason}} ->
        AppLogger.api_error("zKillboard API request failed", %{error: inspect(reason)})
        {:error, reason}
    end
  end

  # Calculate progressive backoff based on process dictionary
  defp calculate_backoff do
    # Get current consecutive 429 count from process dictionary
    consecutive_429s = Process.get(:zkb_429_count, 0)

    # Increment the count
    Process.put(:zkb_429_count, consecutive_429s + 1)

    # Calculate exponential backoff with jitter
    base_backoff = @backoff_base_ms * :math.pow(2, consecutive_429s)
    # Add up to 1 second of jitter
    jitter = :rand.uniform(1000)

    # Cap at max backoff and add jitter
    min(trunc(base_backoff) + jitter, @max_backoff_ms)
  end

  defp get_headers do
    user_agent = "WandererNotifier/1.0 (https://github.com/guarzo/wanderer-notifier)"

    [
      {"User-Agent", user_agent},
      {"Accept", "application/json"}
    ]
  end

  defp handle_json_error({:error, reason} = error) do
    AppLogger.api_error("JSON decode error", error: inspect(reason))
    error
  end
end
