defmodule WandererNotifier.ESI.Client do
  @moduledoc """
  Client for interacting with the EVE Online ESI API.
  """

  alias WandererNotifier.Logger.Logger, as: AppLogger
  alias WandererNotifier.Utils.TimeUtils
  alias WandererNotifier.Http.ResponseHandler
  alias WandererNotifier.Http.Headers
  alias WandererNotifier.HTTP
  @behaviour WandererNotifier.ESI.ClientBehaviour

  use WandererNotifier.Logger.ApiLoggerMacros

  @base_url "https://esi.evetech.net/latest"
  @default_timeout 15_000
  @default_recv_timeout 15_000

  defp default_opts do
    [
      timeout: @default_timeout,
      recv_timeout: @default_recv_timeout,
      # Configure middleware for ESI requests
      retry_options: [
        max_attempts: 3,
        base_backoff: 1000,
        retryable_errors: [:timeout, :connect_timeout, :econnrefused],
        retryable_status_codes: [429, 500, 502, 503, 504],
        context: "ESI request"
      ],
      rate_limit_options: [
        per_host: true,
        requests_per_second: 20,
        burst_capacity: 40
      ],
      telemetry_options: [
        service_name: "eve_esi"
      ]
    ]
  end

  @impl true
  @doc """
  Gets killmail information from ESI.
  """
  def get_killmail(kill_id, hash, opts \\ []) do
    url = "#{@base_url}/killmails/#{kill_id}/#{hash}/"

    with_timing(fn ->
      HTTP.get(url, default_headers(), Keyword.merge(default_opts(), opts))
    end)
    |> handle_response("killmail", %{kill_id: kill_id})
  end

  @impl true
  @doc """
  Gets character information from ESI.
  """
  def get_character_info(character_id, _opts \\ []) do
    url = "#{@base_url}/characters/#{character_id}/"

    HTTP.get(url, default_headers(), default_opts())
    |> handle_response("character", %{character_id: character_id})
  end

  @impl true
  @doc """
  Gets corporation information from ESI.
  """
  def get_corporation_info(corporation_id, _opts \\ []) do
    url = "#{@base_url}/corporations/#{corporation_id}/"

    HTTP.get(url, default_headers(), default_opts())
    |> handle_response("corporation", %{corporation_id: corporation_id})
  end

  @impl true
  @doc """
  Gets alliance information from ESI.
  """
  def get_alliance_info(alliance_id, _opts \\ []) do
    url = "#{@base_url}/alliances/#{alliance_id}/"

    HTTP.get(url, default_headers(), default_opts())
    |> handle_response("alliance", %{alliance_id: alliance_id})
  end

  @impl true
  @doc """
  Gets type information from ESI.
  """
  def get_universe_type(type_id, _opts \\ []) do
    url = "#{@base_url}/universe/types/#{type_id}/"

    HTTP.get(url, default_headers(), default_opts())
    |> handle_response("type", %{type_id: type_id})
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

    HTTP.get(url, headers, default_opts())
    |> handle_response("search", %{query: query})
  end

  @impl true
  @doc """
  Gets solar system information from ESI.
  """
  def get_system(system_id, _opts \\ []) do
    url = "#{@base_url}/universe/systems/#{system_id}/?datasource=tranquility"
    headers = default_headers()

    case HTTP.get(url, headers, default_opts()) do
      {:ok, %{status_code: status, body: body}} when status in 200..299 ->
        # HTTP client already decodes JSON responses
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

    HTTP.get(url, headers, default_opts())
    |> handle_response("system_kills", %{system_id: system_id})
  end

  # Private helper functions

  defp default_headers do
    Headers.esi_headers()
  end

  # Helper function to handle common HTTP response patterns
  defp handle_response(response, resource_type, context) do
    log_context =
      Map.merge(context, %{
        client: "ESI",
        resource_type: resource_type
      })

    ResponseHandler.handle_response(response,
      success_codes: 200..299,
      custom_handlers: [
        {404,
         fn _status, _body ->
           AppLogger.api_info("ESI #{resource_type} not found", context)
           {:error, :not_found}
         end}
      ],
      log_context: log_context
    )
  end

  # Helper function to measure request timing
  defp with_timing(request_fn) do
    {result, duration_ms} = TimeUtils.measure(request_fn)

    case result do
      {:ok, response} ->
        {:ok, response}

      {:error, reason} when is_map(reason) ->
        {:error, Map.put_new(reason, :duration_ms, duration_ms)}

      {:error, reason} ->
        {:error, reason}
    end
  end
end
