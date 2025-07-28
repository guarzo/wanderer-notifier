defmodule WandererNotifier.Infrastructure.Adapters.ESI.Client do
  @moduledoc """
  Client for interacting with the EVE Online ESI API.
  """

  require Logger
  alias WandererNotifier.Infrastructure.Http.ResponseHandler
  alias WandererNotifier.Infrastructure.Http.Headers
  alias WandererNotifier.Infrastructure.Http, as: HTTP
  @behaviour WandererNotifier.Infrastructure.Adapters.ESI.ClientBehaviour

  @base_url "https://esi.evetech.net/latest"

  defp service_opts(additional_opts \\ []) do
    # Use the :esi service configuration which provides:
    # - timeout: 30_000
    # - retry_count: 3
    # - rate_limit: [requests_per_second: 20, burst_capacity: 40]
    # - middlewares: [Retry, RateLimiter]
    # - decode_json: true
    Keyword.merge([service: :esi], additional_opts)
  end

  @impl true
  @doc """
  Gets killmail information from ESI.
  """
  def get_killmail(kill_id, hash, opts \\ []) do
    url = "#{@base_url}/killmails/#{kill_id}/#{hash}/"

    HTTP.request(:get, url, nil, default_headers(), service_opts(opts))
    |> handle_response("killmail", %{kill_id: kill_id})
  end

  @impl true
  @doc """
  Gets character information from ESI.
  """
  def get_character_info(character_id, _opts \\ []) do
    url = "#{@base_url}/characters/#{character_id}/"

    HTTP.request(:get, url, nil, default_headers(), service_opts())
    |> handle_response("character", %{character_id: character_id})
  end

  @impl true
  @doc """
  Gets corporation information from ESI.
  """
  def get_corporation_info(corporation_id, _opts \\ []) do
    url = "#{@base_url}/corporations/#{corporation_id}/"

    HTTP.request(:get, url, nil, default_headers(), service_opts())
    |> handle_response("corporation", %{corporation_id: corporation_id})
  end

  @impl true
  @doc """
  Gets alliance information from ESI.
  """
  def get_alliance_info(alliance_id, _opts \\ []) do
    url = "#{@base_url}/alliances/#{alliance_id}/"

    HTTP.request(:get, url, nil, default_headers(), service_opts())
    |> handle_response("alliance", %{alliance_id: alliance_id})
  end

  @impl true
  @doc """
  Gets type information from ESI.
  """
  def get_universe_type(type_id, _opts \\ []) do
    url = "#{@base_url}/universe/types/#{type_id}/"

    HTTP.request(:get, url, nil, default_headers(), service_opts())
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

    Logger.info("ESI searching inventory type",
      query: query,
      strict: strict,
      method: "search_inventory_type",
      category: :api
    )

    HTTP.request(:get, url, nil, headers, service_opts())
    |> handle_response("search", %{query: query})
  end

  @impl true
  @doc """
  Gets solar system information from ESI.
  """
  def get_system(system_id, _opts \\ []) do
    url = "#{@base_url}/universe/systems/#{system_id}/?datasource=tranquility"
    headers = default_headers()

    case HTTP.request(:get, url, nil, headers, service_opts()) do
      {:ok, %{status_code: status, body: body}} when status in 200..299 ->
        # HTTP client already decodes JSON responses
        {:ok, body}

      {:ok, %{status_code: status, body: _body}} when status == 404 ->
        {:error, {:system_not_found, system_id}}

      {:ok, %{status_code: status, body: body}} ->
        Logger.error("ESI solar system error response",
          system_id: system_id,
          status: status,
          body: inspect(body),
          category: :api
        )

        {:error, {:http_error, status}}

      {:error, reason} ->
        Logger.error("ESI solar system failed",
          system_id: system_id,
          error: inspect(reason),
          category: :api
        )

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

    HTTP.request(:get, url, nil, headers, service_opts())
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
           Logger.info(
             "ESI #{resource_type} not found",
             Map.to_list(Map.put(context, :category, :api))
           )

           {:error, :not_found}
         end}
      ],
      log_context: log_context
    )
  end

  # Timing functionality is now handled by the unified HTTP client's telemetry
end
