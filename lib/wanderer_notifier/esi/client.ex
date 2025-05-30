defmodule WandererNotifier.ESI.Client do
  @moduledoc """
  Client for interacting with the EVE Online ESI API.
  """

  alias WandererNotifier.Logger.Logger, as: AppLogger
  @behaviour WandererNotifier.ESI.ClientBehaviour

  @base_url "https://esi.evetech.net/latest"
  @user_agent "WandererNotifier/1.0"
  @default_timeout 15000
  @default_recv_timeout 15000

  defp http_client do
    Application.get_env(:wanderer_notifier, :http_client, WandererNotifier.HttpClient.Httpoison)
  end

  defp default_opts do
    [
      timeout: @default_timeout,
      recv_timeout: @default_recv_timeout,
      follow_redirect: true
    ]
  end

  @impl true
  @doc """
  Gets killmail information from ESI.
  """
  def get_killmail(kill_id, hash, opts \\ []) do
    url = "#{@base_url}/killmails/#{kill_id}/#{hash}/"
    headers = default_headers()
    opts = Keyword.merge(default_opts(), opts)

    AppLogger.api_info(
      "ESI Client: Starting killmail request for kill_id=#{kill_id} hash=#{hash} with timeout=#{Keyword.get(opts, :timeout, @default_timeout)}ms"
    )

    start_time = System.monotonic_time()

    case http_client().get(url, headers, opts) do
      {:ok, %{status_code: status, body: nil}} when status in 200..299 ->
        AppLogger.api_error(
          "ESI Client: Received 200 with nil body for kill_id=#{kill_id} hash=#{hash}"
        )

        {:error, :esi_data_missing}

      {:ok, %{status_code: status, body: body}} when status in 200..299 ->
        duration = System.monotonic_time() - start_time

        AppLogger.api_info(
          "ESI Client: Received successful response for kill_id=#{kill_id} in #{duration}μs"
        )

        {:ok, body}

      {:ok, %{status_code: status}} ->
        duration = System.monotonic_time() - start_time

        AppLogger.api_error(
          "ESI Client: Received error status #{status} for kill_id=#{kill_id} after #{duration}μs"
        )

        {:error, {:http_error, status}}

      {:error, %{reason: :timeout}} ->
        duration = System.monotonic_time() - start_time

        AppLogger.api_error(
          "ESI Client: Request timed out for kill_id=#{kill_id} after #{duration}μs (timeout=#{Keyword.get(opts, :timeout, @default_timeout)}ms)"
        )

        {:error, :timeout}

      {:error, reason} ->
        duration = System.monotonic_time() - start_time

        AppLogger.api_error(
          "ESI Client: Request failed for kill_id=#{kill_id} after #{duration}μs with reason: #{inspect(reason)}"
        )

        {:error, reason}
    end
  end

  @impl true
  @doc """
  Gets character information from ESI.
  """
  def get_character_info(character_id, _opts \\ []) do
    url = "#{@base_url}/characters/#{character_id}/"
    headers = default_headers()

    case http_client().get(url, headers) do
      {:ok, %{status_code: status, body: body}} when status in 200..299 ->
        {:ok, body}

      {:ok, %{status_code: status}} ->
        AppLogger.api_error("ESI character info error response", %{
          character_id: character_id,
          status: status
        })

        {:error, {:http_error, status}}

      {:error, reason} ->
        AppLogger.api_error("ESI character info failed", %{
          character_id: character_id,
          error: inspect(reason)
        })

        {:error, reason}
    end
  end

  @impl true
  @doc """
  Gets corporation information from ESI.
  """
  def get_corporation_info(corporation_id, _opts \\ []) do
    url = "#{@base_url}/corporations/#{corporation_id}/"
    headers = default_headers()

    case http_client().get(url, headers) do
      {:ok, %{status_code: status, body: body}} when status in 200..299 ->
        {:ok, body}

      {:ok, %{status_code: status}} ->
        AppLogger.api_error("ESI corporation info error response", %{
          corporation_id: corporation_id,
          status: status
        })

        {:error, {:http_error, status}}

      {:error, reason} ->
        AppLogger.api_error("ESI corporation info failed", %{
          corporation_id: corporation_id,
          error: inspect(reason)
        })

        {:error, reason}
    end
  end

  @impl true
  @doc """
  Gets alliance information from ESI.
  """
  def get_alliance_info(alliance_id, _opts \\ []) do
    url = "#{@base_url}/alliances/#{alliance_id}/"
    headers = default_headers()

    case http_client().get(url, headers) do
      {:ok, %{status_code: status, body: body}} when status in 200..299 ->
        {:ok, body}

      {:ok, %{status_code: status}} ->
        AppLogger.api_error("ESI alliance info error response", %{
          alliance_id: alliance_id,
          status: status
        })

        {:error, {:http_error, status}}

      {:error, reason} ->
        AppLogger.api_error("ESI alliance info failed", %{
          alliance_id: alliance_id,
          error: inspect(reason)
        })

        {:error, reason}
    end
  end

  @impl true
  @doc """
  Gets type information from ESI.
  """
  def get_universe_type(type_id, _opts \\ []) do
    url = "#{@base_url}/universe/types/#{type_id}/"
    headers = default_headers()

    case http_client().get(url, headers) do
      {:ok, %{status_code: status, body: body}} when status in 200..299 ->
        {:ok, body}

      {:ok, %{status_code: status}} ->
        AppLogger.api_error("ESI type info error response", %{
          type_id: type_id,
          status: status
        })

        {:error, {:http_error, status}}

      {:error, reason} ->
        AppLogger.api_error("ESI type info failed", %{
          type_id: type_id,
          error: inspect(reason)
        })

        {:error, reason}
    end
  end

  @impl true
  @doc """
  Searches for inventory types in ESI.
  """
  def search_inventory_type(query, strict \\ false) do
    query_params = %{
      "categories" => "inventory_type",
      "search" => query,
      "strict" => to_string(strict)
    }

    url = "#{@base_url}/search/?#{URI.encode_query(query_params)}"
    headers = default_headers()

    AppLogger.api_info("ESI searching inventory type", %{
      query: query,
      strict: strict,
      method: "search_inventory_type"
    })

    case http_client().get(url, headers) do
      {:ok, %{status_code: status, body: body}} when status in 200..299 ->
        {:ok, body}

      {:ok, %{status_code: status}} ->
        AppLogger.api_error("ESI search error response", %{
          query: query,
          status: status
        })

        {:error, {:http_error, status}}

      {:error, reason} ->
        AppLogger.api_error("ESI search failed", %{
          query: query,
          error: inspect(reason)
        })

        {:error, reason}
    end
  end

  @impl true
  @doc """
  Gets solar system information from ESI.
  """
  def get_system(system_id, _opts \\ []) do
    url = "#{@base_url}/universe/systems/#{system_id}/?datasource=tranquility"
    headers = default_headers()

    case http_client().get(url, headers) do
      {:ok, %{status_code: status, body: body}} when status in 200..299 ->
        {:ok, body}

      {:ok, %{status_code: status, body: _body}} when status == 404 ->
        {:error, {:system_not_found, system_id}}

      {:ok, %{status_code: status, body: body}} ->
        AppLogger.api_error("ESI solar system error response", %{
          system_id: system_id,
          status: status,
          body: inspect(body)
        })

        {:error, {:http_error, status}}

      {:error, reason} ->
        AppLogger.api_error("ESI solar system failed", %{
          system_id: system_id,
          error: inspect(reason)
        })

        {:error, reason}
    end
  end

  @impl true
  @doc """
  Gets system kill statistics from ESI.
  """
  def get_system_kills(system_id, _limit \\ 5, _opts \\ []) do
    url = "#{@base_url}/universe/system_kills/"
    headers = default_headers()

    case http_client().get(url, headers) do
      {:ok, %{status_code: status, body: body}} when status in 200..299 ->
        {:ok, body}

      {:ok, %{status_code: status}} ->
        AppLogger.api_error("ESI system kills error response", %{
          system_id: system_id,
          status: status
        })

        {:error, {:http_error, status}}

      {:error, reason} ->
        AppLogger.api_error("ESI system kills failed", %{
          system_id: system_id,
          error: inspect(reason)
        })

        {:error, reason}
    end
  end

  # Private helper functions

  defp default_headers do
    [
      {"Accept", "application/json"},
      {"User-Agent", @user_agent}
    ]
  end
end
